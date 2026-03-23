import Foundation
import SwiftCMA

struct EpochSnapshot: Identifiable {
	let id: Int  // globalEpoch
	let restartIndex: Int
	let regime: String
	let x: Double  // xmean[0]
	let y: Double  // xmean[1]
	let stepSigma: Double
	let bestFitness: Double
	let populationSize: Int
}

struct RestartInfo: Identifiable {
	let id: Int  // index
	let regime: String
	let populationSize: Int
	let evaluationsUsed: Int
	let bestFitness: Double?
}

struct BudgetEntry: Identifiable {
	let id: String  // "\(runIndex)-\(type)"
	let runIndex: Int
	let type: String  // "Large" or "Small"
	let cumulativeEvals: Int
}

/// A single data point for the parallel coordinates chart.
/// Each candidate produces one entry per parameter dimension.
struct CandidatePoint: Identifiable {
	let id: String  // "\(epochIndex)-\(candidateIndex)-\(parameterName)"
	let candidateIndex: Int
	let parameterName: String
	let value: Double
	let fitness: Double
}

/// All candidate data for a single epoch.
struct EpochCandidates: Identifiable {
	let id: Int  // globalEpoch
	let regime: String
	let restartIndex: Int
	let bestFitness: Double
	let points: [CandidatePoint]
}

@Observable
class BIPOPRunner {
	var snapshots: [EpochSnapshot] = []
	var restarts: [RestartInfo] = []
	var budgetEntries: [BudgetEntry] = []
	var restartBoundaries: [Int] = []
	var epochCandidates: [EpochCandidates] = []
	var isRunning = false
	var isComplete = false

	func run() {
		isRunning = true
		snapshots = []
		restarts = []
		budgetEntries = []
		restartBoundaries = []
		epochCandidates = []

		let bounds: [ClosedRange<Double>?] = [-5.0...5.0, -5.0...5.0]
		let config = CMAES.SearchSpaceConfiguration(
			bounds: bounds,
			scalingFactors: [1.0, 1.0],
			bchm: .darwinianReflection
		)

		let bipop = BIPOPCMAES(
			startSolution: [3.0, 3.0],
			stepSigma: 2.0,
			maxRestarts: 3,
			maxEpochsPerRestart: 6,
			searchSpaceConfiguration: config
		)

		var evaluator = RastriginObjectiveEvaluator()
		var globalEpoch = 0
		var prevRestartIndex = 0

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }

			// Detect restart
			if bipop.currentRestartIndex != prevRestartIndex {
				restartBoundaries.append(globalEpoch)
				prevRestartIndex = bipop.currentRestartIndex
			}

			// Evaluate candidates
			let fitnesses = candidates.map { candidate in
				evaluator.objective(genome: candidate) { _, _ in }
			}

			// Capture candidate data for parallel coordinates BEFORE finishEpoch
			let regime: String
			switch bipop.currentRegime {
			case .initial: regime = "Initial"
			case .large: regime = "Large"
			case .small: regime = "Small"
			}

			let paramNames = ["x₁", "x₂"]
			var points: [CandidatePoint] = []
			for (ci, candidate) in candidates.enumerated() {
				for (pi, value) in candidate.enumerated() {
					points.append(CandidatePoint(
						id: "\(globalEpoch)-\(ci)-\(paramNames[pi])",
						candidateIndex: ci,
						parameterName: paramNames[pi],
						value: value,
						fitness: fitnesses[ci]
					))
				}
			}

			let epochBestFitness = fitnesses.min() ?? .infinity

			epochCandidates.append(EpochCandidates(
				id: globalEpoch,
				regime: regime,
				restartIndex: bipop.currentRestartIndex,
				bestFitness: epochBestFitness,
				points: points
			))

			bipop.finishEpoch(candidateFitnesses: Array(zip(candidates, fitnesses)))

			// Capture overview snapshot
			let snapshot = EpochSnapshot(
				id: globalEpoch,
				restartIndex: bipop.currentRestartIndex,
				regime: regime,
				x: bipop.cmaes.xmean[0],
				y: bipop.cmaes.xmean[1],
				stepSigma: bipop.cmaes.stepSigma,
				bestFitness: bipop.bestSolution?.value ?? Double.infinity,
				populationSize: bipop.cmaes.populationSize
			)
			snapshots.append(snapshot)
			globalEpoch += 1
		}

		// Collect restart history
		for record in bipop.restartHistory {
			let regime: String
			switch record.regime {
			case .initial: regime = "Initial"
			case .large: regime = "Large"
			case .small: regime = "Small"
			}
			restarts.append(RestartInfo(
				id: record.index,
				regime: regime,
				populationSize: record.populationSize,
				evaluationsUsed: record.evaluationsUsed,
				bestFitness: record.bestFitness
			))
		}

		// Build cumulative budget data
		var cumulativeLarge = 0
		var cumulativeSmall = 0
		for record in bipop.restartHistory {
			switch record.regime {
			case .initial, .large:
				cumulativeLarge += record.evaluationsUsed
			case .small:
				cumulativeSmall += record.evaluationsUsed
			}
			budgetEntries.append(BudgetEntry(
				id: "\(record.index)-Large",
				runIndex: record.index,
				type: "Large",
				cumulativeEvals: cumulativeLarge
			))
			budgetEntries.append(BudgetEntry(
				id: "\(record.index)-Small",
				runIndex: record.index,
				type: "Small",
				cumulativeEvals: cumulativeSmall
			))
		}

		isRunning = false
		isComplete = true
	}
}
