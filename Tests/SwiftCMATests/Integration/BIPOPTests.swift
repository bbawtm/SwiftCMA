//
//  BIPOPTests.swift
//  SwiftCMAESTests
//

import XCTest
import SwiftCMA

final class BIPOPTests: XCTestCase {

	// MARK: - Initialization

	/// Default maxRestarts is 5 and maxEpochsPerRestart is 100.
	func testDefaultInit() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0, 3.0],
			stepSigma: 0.3
		)
		XCTAssertEqual(bipop.n, 3)
		XCTAssertEqual(bipop.maxRestarts, 5)
		XCTAssertEqual(bipop.maxEpochsPerRestart, 100)
		XCTAssertEqual(bipop.currentRestartIndex, 0)
		XCTAssertEqual(bipop.currentRegime, .initial)
		XCTAssertFalse(bipop.isFinished)
		XCTAssertNil(bipop.bestSolution)
		XCTAssertTrue(bipop.restartHistory.isEmpty)
		XCTAssertEqual(bipop.largeBudgetUsed, 0)
		XCTAssertEqual(bipop.smallBudgetUsed, 0)
		XCTAssertEqual(bipop.totalEvaluations, 0)
		XCTAssertEqual(bipop.totalEpochsCompleted, 0)
	}

	/// Custom maxRestarts and maxEpochsPerRestart are stored correctly.
	func testCustomInit() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.5,
			maxRestarts: 3,
			maxEpochsPerRestart: 10
		)
		XCTAssertEqual(bipop.maxRestarts, 3)
		XCTAssertEqual(bipop.maxEpochsPerRestart, 10)
	}

	/// Custom populationSize overrides the default.
	func testCustomPopulationSize() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0, 3.0],
			populationSize: 20,
			stepSigma: 0.3
		)
		XCTAssertEqual(bipop.defaultPopulationSize, 20)
		XCTAssertEqual(bipop.cmaes.populationSize, 20)
	}

	/// SearchSpaceConfiguration is passed through to the underlying CMAES.
	func testSearchSpaceConfigPassthrough() {
		let config = CMAES.SearchSpaceConfiguration(
			bounds: [0.0...1.0, 0.0...1.0],
			scalingFactors: [1.0, 1.0],
			bchm: .darwinianReflection
		)
		let bipop = BIPOPCMAES(
			startSolution: [0.5, 0.5],
			stepSigma: 0.3,
			searchSpaceConfiguration: config
		)
		XCTAssertNotNil(bipop.cmaes.searchSpaceConfiguration)
		XCTAssertEqual(bipop.cmaes.searchSpaceConfiguration!.bounds.count, 2)
	}

	// MARK: - Single Epoch

	/// A single startEpoch + finishEpoch cycle works and updates state.
	func testSingleEpoch() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0, 3.0],
			stepSigma: 0.3,
			maxRestarts: 0,
			maxEpochsPerRestart: 5
		)
		let candidates = bipop.startEpoch()
		XCTAssertEqual(candidates.count, bipop.defaultPopulationSize)

		let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)

		XCTAssertEqual(bipop.epochsInCurrentRun, 1)
		XCTAssertNotNil(bipop.bestSolution)
		XCTAssertFalse(bipop.isFinished)
	}

	// MARK: - Restart Triggering

	/// After maxEpochsPerRestart epochs, the next startEpoch triggers a restart.
	func testRestartTriggeredAfterMaxEpochs() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 3
		)

		// Run 3 epochs (initial run)
		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}
		XCTAssertEqual(bipop.currentRestartIndex, 0)
		XCTAssertEqual(bipop.restartHistory.count, 0)

		// Next startEpoch triggers restart
		let candidates = bipop.startEpoch()
		XCTAssertFalse(candidates.isEmpty)
		XCTAssertEqual(bipop.currentRestartIndex, 1)
		XCTAssertEqual(bipop.restartHistory.count, 1)
		XCTAssertEqual(bipop.restartHistory[0].index, 0)
		XCTAssertEqual(bipop.restartHistory[0].regime, .initial)
		XCTAssertEqual(bipop.restartHistory[0].epochsCompleted, 3)
	}

	/// After all restarts are exhausted, isFinished becomes true and startEpoch returns [].
	func testIsFinishedAfterAllRestarts() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 1,
			maxEpochsPerRestart: 2
		)

		// Initial run: 2 epochs
		for _ in 0..<2 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Restart 1: 2 epochs
		for _ in 0..<2 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Should trigger finish on next startEpoch
		let candidates = bipop.startEpoch()
		XCTAssertTrue(candidates.isEmpty)
		XCTAssertTrue(bipop.isFinished)
		XCTAssertEqual(bipop.restartHistory.count, 2)  // initial + 1 restart
	}

	/// maxRestarts=0 means only the initial run, no restarts.
	func testMaxRestartsZero() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0],
			stepSigma: 0.3,
			maxRestarts: 0,
			maxEpochsPerRestart: 2
		)

		for _ in 0..<2 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let candidates = bipop.startEpoch()
		XCTAssertTrue(candidates.isEmpty)
		XCTAssertTrue(bipop.isFinished)
		XCTAssertEqual(bipop.restartHistory.count, 1)
		XCTAssertEqual(bipop.restartHistory[0].regime, .initial)
	}

	// MARK: - Regime Selection

	/// First restart after initial run uses the large regime (initial run counts as large budget).
	/// Since largeBudgetUsed > 0 and smallBudgetUsed == 0, first restart should be small.
	func testFirstRestartIsSmallRegime() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 1
		)

		// Initial run: 1 epoch (adds to largeBudget)
		let candidates = bipop.startEpoch()
		let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)

		// Trigger restart 1
		_ = bipop.startEpoch()
		XCTAssertEqual(bipop.currentRestartIndex, 1)
		// largeBudgetUsed > 0, smallBudgetUsed == 0 → small regime
		XCTAssertEqual(bipop.currentRegime, .small)
	}

	/// Large restart doubles the population size from the previous large run.
	func testLargeRestartDoublesPopulation() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 1
		)

		// Run through restarts and collect population sizes for large-regime runs
		var largePopSizes: [Int] = []

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		largePopSizes = bipop.restartHistory
			.filter { $0.regime == .initial || $0.regime == .large }
			.map { $0.populationSize }

		// Initial run uses defaultPopulationSize (4).
		// Each subsequent large restart doubles.
		XCTAssertEqual(largePopSizes.first, 4)  // initial
		if largePopSizes.count >= 2 {
			for i in 1..<largePopSizes.count {
				XCTAssertEqual(largePopSizes[i], largePopSizes[i - 1] * 2,
					"Large restart \(i) should double population from \(largePopSizes[i-1])")
			}
		}
	}

	/// Small restart population is at least 2 and at most defaultPopulationSize.
	func testSmallRestartPopulationBounds() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 10,
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let smallRuns = bipop.restartHistory.filter { $0.regime == .small }
		for run in smallRuns {
			XCTAssertGreaterThanOrEqual(run.populationSize, 2,
				"Small restart population must be >= 2")
			XCTAssertLessThanOrEqual(run.populationSize, 10,
				"Small restart population must be <= defaultPopulationSize")
		}
	}

	/// Small restart uses small step sigma in range (0, 0.02].
	func testSmallRestartStepSigma() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 10,
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 1
		)

		// Force a small restart by running initial (adds to largeBudget)
		let candidates = bipop.startEpoch()
		let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)

		// Trigger restart (should be small since largeBudget > smallBudget)
		_ = bipop.startEpoch()
		if bipop.currentRegime == .small {
			// Step sigma for small restart: 0.01 * 2 * rand ∈ (0, 0.02]
			XCTAssertLessThanOrEqual(bipop.cmaes.stepSigma, 0.02)
			XCTAssertGreaterThan(bipop.cmaes.stepSigma, 0.0)
		}
	}

	// MARK: - Global Best Preservation

	/// Best solution is preserved across restarts (never regresses).
	func testGlobalBestPreservedAcrossRestarts() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0, 3.0],
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 5
		)

		var bestFitnessSoFar: Double = .infinity

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)

			if let best = bipop.bestSolution {
				XCTAssertLessThanOrEqual(best.value, bestFitnessSoFar,
					"Global best fitness must never regress")
				bestFitnessSoFar = best.value
			}
		}

		XCTAssertNotNil(bipop.bestSolution)
	}

	/// Restart starts from best known solution, not original start.
	func testRestartStartsFromBestSolution() {
		let bipop = BIPOPCMAES(
			startSolution: [5.0, 5.0],
			stepSigma: 0.3,
			maxRestarts: 1,
			maxEpochsPerRestart: 3
		)

		// Run initial
		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}
		let bestAfterInitial = bipop.bestSolution

		// Trigger restart
		_ = bipop.startEpoch()

		// The new CMAES should have xmean near the best solution, not [5, 5]
		XCTAssertNotNil(bestAfterInitial)
		// xmean should be derived from bestSolution, not originalStartSolution
		XCTAssertNotEqual(bipop.cmaes.xmean, [5.0, 5.0],
			"Restart should use best solution as start, not original")
	}

	// MARK: - Budget Tracking

	/// Total evaluations across all restarts sums correctly.
	func testTotalEvaluationsAccuracy() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 2
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let historyEvals = bipop.restartHistory.reduce(0) { $0 + $1.evaluationsUsed }
		XCTAssertEqual(bipop.largeBudgetUsed + bipop.smallBudgetUsed, historyEvals)
	}

	/// Total epochs across all restarts sums correctly.
	func testTotalEpochsAccuracy() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 3
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let expectedTotal = bipop.restartHistory.reduce(0) { $0 + $1.epochsCompleted }
		XCTAssertEqual(bipop.totalEpochsCompleted, expectedTotal)
		// 3 runs × 3 epochs = 9 total
		XCTAssertEqual(bipop.totalEpochsCompleted, 9)
	}

	/// largeBudgetUsed includes the initial run.
	func testInitialRunCountsAsLargeBudget() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 0,
			maxEpochsPerRestart: 2
		)

		for _ in 0..<2 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}
		_ = bipop.startEpoch()  // triggers finish

		XCTAssertGreaterThan(bipop.largeBudgetUsed, 0)
		XCTAssertEqual(bipop.smallBudgetUsed, 0)
	}

	// MARK: - Restart History

	/// RestartRecord captures correct data for each run.
	func testRestartRecordAccuracy() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 6,
			stepSigma: 0.3,
			maxRestarts: 1,
			maxEpochsPerRestart: 2
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertEqual(bipop.restartHistory.count, 2)

		let initial = bipop.restartHistory[0]
		XCTAssertEqual(initial.index, 0)
		XCTAssertEqual(initial.regime, .initial)
		XCTAssertEqual(initial.populationSize, 6)
		XCTAssertEqual(initial.epochsCompleted, 2)
		XCTAssertGreaterThan(initial.evaluationsUsed, 0)
		XCTAssertNotNil(initial.bestFitness)

		let restart1 = bipop.restartHistory[1]
		XCTAssertEqual(restart1.index, 1)
		XCTAssertEqual(restart1.epochsCompleted, 2)
	}

	// MARK: - Stop

	/// Calling stop() mid-run sets isFinished and records the current run.
	func testStopMidRun() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 100
		)

		// Run 2 epochs then stop
		for _ in 0..<2 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		bipop.stop()
		XCTAssertTrue(bipop.isFinished)
		XCTAssertEqual(bipop.restartHistory.count, 1)
		XCTAssertEqual(bipop.restartHistory[0].epochsCompleted, 2)

		// Further startEpoch should return empty
		let candidates = bipop.startEpoch()
		XCTAssertTrue(candidates.isEmpty)
	}

	/// finishEpoch after stop is a no-op (doesn't crash).
	func testFinishEpochAfterStopIsNoop() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0],
			stepSigma: 0.3,
			maxRestarts: 0,
			maxEpochsPerRestart: 1
		)
		bipop.stop()

		// Should not crash
		bipop.finishEpoch(candidateFitnesses: [([1.0], 1.0)])
		XCTAssertTrue(bipop.isFinished)
	}

	// MARK: - Checkpointing

	/// Full BIPOP state survives checkpoint save/restore cycle.
	func testCheckpointRoundTrip() throws {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0, 3.0],
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 2
		)

		// Run initial + trigger one restart
		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Save checkpoint
		let url = URL(fileURLWithPath: "/tmp/bipop_test_checkpoint_\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: url) }
		try bipop.save(checkpoint: url)

		// Restore
		let restored = try BIPOPCMAES.from(checkpoint: url)

		XCTAssertEqual(restored.n, bipop.n)
		XCTAssertEqual(restored.maxRestarts, bipop.maxRestarts)
		XCTAssertEqual(restored.maxEpochsPerRestart, bipop.maxEpochsPerRestart)
		XCTAssertEqual(restored.currentRestartIndex, bipop.currentRestartIndex)
		XCTAssertEqual(restored.currentRegime, bipop.currentRegime)
		XCTAssertEqual(restored.epochsInCurrentRun, bipop.epochsInCurrentRun)
		XCTAssertEqual(restored.largeBudgetUsed, bipop.largeBudgetUsed)
		XCTAssertEqual(restored.smallBudgetUsed, bipop.smallBudgetUsed)
		XCTAssertEqual(restored.nextLargePopulationSize, bipop.nextLargePopulationSize)
		XCTAssertEqual(restored.restartHistory.count, bipop.restartHistory.count)
		XCTAssertEqual(restored.isFinished, bipop.isFinished)
		XCTAssertEqual(restored.bestSolution?.value, bipop.bestSolution?.value)
	}

	/// Checkpoint mid-restart preserves partial run progress.
	func testCheckpointMidRestart() throws {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 5
		)

		// Run 3 of 5 epochs
		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}
		XCTAssertEqual(bipop.epochsInCurrentRun, 3)

		let url = URL(fileURLWithPath: "/tmp/bipop_test_mid_\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: url) }
		try bipop.save(checkpoint: url)

		let restored = try BIPOPCMAES.from(checkpoint: url)
		XCTAssertEqual(restored.epochsInCurrentRun, 3)
		XCTAssertFalse(restored.isFinished)

		// Can continue from checkpoint
		let candidates = restored.startEpoch()
		XCTAssertFalse(candidates.isEmpty)
	}

	/// Corrupt checkpoint file throws on decode (does not crash).
	func testCorruptCheckpointThrows() {
		let url = URL(fileURLWithPath: "/tmp/bipop_test_corrupt_\(UUID().uuidString).json")
		defer { try? FileManager.default.removeItem(at: url) }

		try! Data("not json".utf8).write(to: url)
		XCTAssertThrowsError(try BIPOPCMAES.from(checkpoint: url))
	}

	// MARK: - Edge Cases

	/// 1-dimensional search space works correctly.
	func testOneDimensional() {
		let bipop = BIPOPCMAES(
			startSolution: [5.0],
			stepSigma: 1.0,
			maxRestarts: 1,
			maxEpochsPerRestart: 3
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertNotNil(bipop.bestSolution)
		XCTAssertEqual(bipop.restartHistory.count, 2)
	}

	/// High-dimensional search space (20D) runs without numerical issues.
	func testHighDimensional() {
		let n = 20
		let bipop = BIPOPCMAES(
			startSolution: Array(repeating: 1.0, count: n),
			stepSigma: 0.3,
			maxRestarts: 1,
			maxEpochsPerRestart: 5
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertNotNil(bipop.bestSolution)
		// Default pop for 20D = 4 + floor(3*ln(20)) = 4 + 8 = 12
		// Large restart should use 24
		let largeRuns = bipop.restartHistory.filter { $0.regime == .large }
		for run in largeRuns {
			XCTAssertGreaterThanOrEqual(run.populationSize, 24)
		}
	}

	/// Very large maxRestarts value doesn't cause issues (just runs longer).
	func testLargeMaxRestarts() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0],
			populationSize: 2,
			stepSigma: 0.3,
			maxRestarts: 100,
			maxEpochsPerRestart: 1
		)

		// Run a few, then stop
		for _ in 0..<5 {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		bipop.stop()
		XCTAssertTrue(bipop.isFinished)
		XCTAssertGreaterThan(bipop.restartHistory.count, 0)
	}

	/// All candidates have the same fitness (flat landscape) doesn't crash.
	func testFlatFitnessLandscape() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 1,
			maxEpochsPerRestart: 3
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			// All candidates get the same fitness
			let fitnesses = candidates.map { ($0, 42.0) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Should complete without crash
		XCTAssertTrue(bipop.isFinished)
	}

	/// Very small step sigma (near zero) doesn't cause NaN or crash.
	func testVerySmallStepSigma() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 1e-10,
			maxRestarts: 0,
			maxEpochsPerRestart: 3
		)

		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)

			// No NaN in candidates
			for c in candidates {
				for val in c {
					XCTAssertFalse(val.isNaN, "Candidate value should not be NaN")
				}
			}
		}
	}

	/// Very large step sigma doesn't cause overflow.
	func testVeryLargeStepSigma() {
		let bipop = BIPOPCMAES(
			startSolution: [0.0, 0.0],
			stepSigma: 1e6,
			maxRestarts: 0,
			maxEpochsPerRestart: 3
		)

		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)

			for c in candidates {
				for val in c {
					XCTAssertFalse(val.isInfinite, "Candidate value should not be infinite")
				}
			}
		}
	}

	/// Population size 2 (minimum for small restart) works.
	func testMinimumPopulationSize() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 2,
			stepSigma: 0.3,
			maxRestarts: 0,
			maxEpochsPerRestart: 3
		)

		for _ in 0..<3 {
			let candidates = bipop.startEpoch()
			XCTAssertEqual(candidates.count, 2)
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}
	}

	/// SearchSpaceConfiguration with bounds is preserved across restarts.
	func testBoundsPreservedAcrossRestarts() {
		let config = CMAES.SearchSpaceConfiguration(
			bounds: [0.0...10.0, -5.0...5.0],
			scalingFactors: [1.0, 1.0],
			bchm: .darwinianReflection
		)
		let bipop = BIPOPCMAES(
			startSolution: [5.0, 0.0],
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 1,
			searchSpaceConfiguration: config
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// After restarts, the underlying CMAES should still have search space config
		XCTAssertNotNil(bipop.searchSpaceConfiguration)
		XCTAssertEqual(bipop.searchSpaceConfiguration!.bounds.count, 2)
	}

	// MARK: - Integration: Rastrigin Function (multimodal)

	/// BIPOP should find a better solution than single-run CMA-ES on Rastrigin
	/// (a challenging multimodal function). This is a statistical test — it may
	/// occasionally fail due to randomness, but should pass the vast majority of runs.
	func testBIPOPOnRastrigin() {
		let n = 3
		let startSolution = [3.0, 3.0, 3.0]  // far from optimum at [0,0,0]
		var evaluator = RastriginObjectiveEvaluator()

		// Single-run CMA-ES baseline
		let singleRun = CMAES(
			startSolution: startSolution,
			populationSize: CMAES.populationSize(forDimensions: n),
			stepSigma: 1.0
		)
		for _ in 0..<50 {
			singleRun.epoch(evaluator: &evaluator) { _, _ in }
		}
		let singleBest = singleRun.bestSolution!.value

		// BIPOP-CMA-ES
		var evaluator2 = RastriginObjectiveEvaluator()
		let bipop = BIPOPCMAES(
			startSolution: startSolution,
			stepSigma: 1.0,
			maxRestarts: 5,
			maxEpochsPerRestart: 50
		)
		bipop.run(evaluator: &evaluator2)
		let bipopBest = bipop.bestSolution!.value

		// BIPOP should find at least as good a solution
		print("Single-run best: \(singleBest), BIPOP best: \(bipopBest)")
		XCTAssertLessThanOrEqual(bipopBest, singleBest + 1.0,
			"BIPOP should find a competitive solution on Rastrigin")
	}

	// MARK: - Statistical Correctness

	/// Small restart population sizes follow floor(defaultPop * (0.5*U)^2) with correct bounds and mean.
	func testSmallPopulationDistribution_MeanAndBounds() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 100,
			stepSigma: 0.3,
			maxRestarts: 200,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let smallPops = bipop.restartHistory
			.filter { $0.regime == .small }
			.map { $0.populationSize }

		XCTAssertGreaterThan(smallPops.count, 20, "Need enough small restarts for statistics")

		// All pop sizes must be in [2, 25] since max(2, floor(100 * (0.5*1)^2)) = 25
		for pop in smallPops {
			XCTAssertGreaterThanOrEqual(pop, 2)
			XCTAssertLessThanOrEqual(pop, 25)
		}

		// Mean: E[100*(0.5U)^2] = 25*E[U^2] = 25/3 ≈ 8.33, shifted by floor/max
		let mean = Double(smallPops.reduce(0, +)) / Double(smallPops.count)
		XCTAssertGreaterThan(mean, 3.0, "Mean small pop should be > 3")
		XCTAssertLessThan(mean, 15.0, "Mean small pop should be < 15")

		// At least some values should hit the floor of 2
		XCTAssertTrue(smallPops.contains(2), "Some small pops should be at minimum (2)")

		// Variance should be nonzero
		let variance = smallPops.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(smallPops.count)
		XCTAssertGreaterThan(variance, 0.0, "Population sizes should vary")
	}

	/// Small population distribution is right-skewed (most values near minimum).
	func testSmallPopulationDistribution_SkewedTowardMinimum() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 100,
			stepSigma: 0.3,
			maxRestarts: 200,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let smallPops = bipop.restartHistory
			.filter { $0.regime == .small }
			.map { $0.populationSize }
			.sorted()

		XCTAssertGreaterThan(smallPops.count, 20)

		let mean = Double(smallPops.reduce(0, +)) / Double(smallPops.count)
		let median = Double(smallPops[smallPops.count / 2])

		// Right-skewed: median < mean
		XCTAssertLessThan(median, mean, "Distribution should be right-skewed (median < mean)")

		// More than 30% of samples should be at the minimum value of 2
		let countAtMin = smallPops.filter { $0 == 2 }.count
		let fractionAtMin = Double(countAtMin) / Double(smallPops.count)
		XCTAssertGreaterThan(fractionAtMin, 0.3,
			"More than 30% of small pops should be at minimum (2), got \(fractionAtMin)")
	}

	/// Small restart sigma values are uniformly distributed in (0, 0.02].
	func testSmallSigmaDistribution_UniformInRange() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 10,
			stepSigma: 0.3,
			maxRestarts: 200,
			maxEpochsPerRestart: 1
		)

		var smallSigmas: [Double] = []
		var lastRestartIndex = bipop.currentRestartIndex

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }

			// Detect restart transition and capture sigma for small restarts
			if bipop.currentRestartIndex != lastRestartIndex {
				if bipop.currentRegime == .small {
					smallSigmas.append(bipop.cmaes.stepSigma)
				}
				lastRestartIndex = bipop.currentRestartIndex
			}

			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertGreaterThan(smallSigmas.count, 30, "Need enough small restarts for statistics")

		// All values in (0, 0.02]
		for sigma in smallSigmas {
			XCTAssertGreaterThan(sigma, 0.0)
			XCTAssertLessThanOrEqual(sigma, 0.02)
		}

		// Mean should be approximately 0.01 for Uniform(0, 0.02)
		let mean = smallSigmas.reduce(0, +) / Double(smallSigmas.count)
		XCTAssertGreaterThan(mean, 0.006, "Mean sigma should be near 0.01")
		XCTAssertLessThan(mean, 0.014, "Mean sigma should be near 0.01")

		// Check quartiles for approximate uniformity
		let sorted = smallSigmas.sorted()
		let q1 = sorted[sorted.count / 4]
		let q3 = sorted[(sorted.count * 3) / 4]
		XCTAssertGreaterThan(q1, 0.001, "Q1 should be near 0.005")
		XCTAssertLessThan(q1, 0.01, "Q1 should be near 0.005")
		XCTAssertGreaterThan(q3, 0.01, "Q3 should be near 0.015")
		XCTAssertLessThan(q3, 0.02, "Q3 should be near 0.015")
	}

	/// Large restart population sizes form exact geometric sequence (doubling each time).
	func testLargePopulationGeometricProgression_ExactDoubling() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 10,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		let largePops = bipop.restartHistory
			.filter { $0.regime == .initial || $0.regime == .large }
			.sorted(by: { $0.index < $1.index })
			.map { $0.populationSize }

		XCTAssertGreaterThanOrEqual(largePops.count, 2, "Need at least 2 large restarts")
		XCTAssertEqual(largePops[0], 4, "Initial run uses defaultPopulationSize")

		for i in 1..<largePops.count {
			XCTAssertEqual(largePops[i], largePops[i - 1] * 2,
				"Large restart \(i) pop (\(largePops[i])) should be 2x previous (\(largePops[i-1]))")
		}
	}

	/// Regime alternation exactly follows the budget comparison rule.
	func testRegimeAlternation_FollowsBudgetRule() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 10,
			stepSigma: 0.3,
			maxRestarts: 10,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Reconstruct running budgets and verify each regime choice
		var runningLarge = 0
		var runningSmall = 0

		for i in 0..<bipop.restartHistory.count {
			let record = bipop.restartHistory[i]

			if i == 0 {
				XCTAssertEqual(record.regime, .initial, "First run must be initial")
			} else {
				// Regime was chosen based on budget BEFORE this run started
				if runningLarge <= runningSmall {
					XCTAssertTrue(record.regime == .large,
						"Restart \(i): largeBudget(\(runningLarge)) <= smallBudget(\(runningSmall)) should select .large, got \(record.regime)")
				} else {
					XCTAssertEqual(record.regime, .small,
						"Restart \(i): largeBudget(\(runningLarge)) > smallBudget(\(runningSmall)) should select .small")
				}
			}

			// Update running budgets after this run
			switch record.regime {
			case .initial, .large:
				runningLarge += record.evaluationsUsed
			case .small:
				runningSmall += record.evaluationsUsed
			}
		}

		XCTAssertEqual(runningLarge, bipop.largeBudgetUsed)
		XCTAssertEqual(runningSmall, bipop.smallBudgetUsed)
	}

	/// When large budget dominates, all subsequent restarts are small until budget balances.
	func testRegimeAlternation_ContinuousSmallWhenLargeBudgetDominates() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 100,
			stepSigma: 0.3,
			maxRestarts: 6,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Initial run uses pop=100, so largeBudget=100.
		// Small restarts use pop 2-25, so several small runs needed to catch up.
		// Verify that after initial, all restarts are .small until budget balances.
		var runningLarge = 0
		var foundLargeAfterInitial = false

		for record in bipop.restartHistory {
			if record.regime == .initial || record.regime == .large {
				runningLarge += record.evaluationsUsed
			}
			if record.index > 0 && record.regime == .large {
				foundLargeAfterInitial = true
			}
		}

		// With pop=100 initial and small pops 2-25, it takes many small runs to catch up.
		// With only 6 restarts, we likely never reach a large restart.
		let smallRunsBeforeLarge = bipop.restartHistory
			.filter { $0.index > 0 }
			.prefix(while: { $0.regime == .small })
			.count

		XCTAssertGreaterThanOrEqual(smallRunsBeforeLarge, 3,
			"At least 3 consecutive small restarts expected before budget can balance")
	}

	// MARK: - State Machine Correctness

	/// Track exact state transitions through a full BIPOP run.
	func testExactStateTransitions_FullRun() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 2
		)

		// Initial state
		XCTAssertEqual(bipop.currentRestartIndex, 0)
		XCTAssertEqual(bipop.currentRegime, .initial)
		XCTAssertEqual(bipop.epochsInCurrentRun, 0)
		XCTAssertEqual(bipop.largeBudgetUsed, 0)
		XCTAssertEqual(bipop.smallBudgetUsed, 0)
		XCTAssertEqual(bipop.restartHistory.count, 0)
		XCTAssertFalse(bipop.isFinished)

		var epochCount = 0
		var prevRestartIndex = 0

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }

			// After startEpoch, detect if restart happened
			if bipop.currentRestartIndex != prevRestartIndex {
				// Restart just happened: epochsInCurrentRun should be 0
				XCTAssertEqual(bipop.epochsInCurrentRun, 0,
					"epochsInCurrentRun should be 0 after restart \(bipop.currentRestartIndex)")
				prevRestartIndex = bipop.currentRestartIndex
			}

			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
			epochCount += 1

			// After finishEpoch, epoch counter should match
			let expectedEpochInRun = ((epochCount - 1) % 2) + 1
			XCTAssertEqual(bipop.epochsInCurrentRun, expectedEpochInRun,
				"After epoch \(epochCount), epochsInCurrentRun should be \(expectedEpochInRun)")
		}

		XCTAssertTrue(bipop.isFinished)
		// 4 runs (initial + 3 restarts) × 2 epochs = 8 total epochs
		XCTAssertEqual(epochCount, 8)
		XCTAssertEqual(bipop.restartHistory.count, 4)
		XCTAssertEqual(bipop.totalEpochsCompleted, 8)
	}

	/// CMAES instance is replaced (different object identity) on restart.
	func testCMAESInstanceReplacedOnRestart() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 1,
			maxEpochsPerRestart: 1
		)

		let initialCmaes = bipop.cmaes

		// Run one epoch (initial run)
		let candidates = bipop.startEpoch()
		let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)

		// Trigger restart
		_ = bipop.startEpoch()

		XCTAssertTrue(bipop.cmaes !== initialCmaes,
			"CMAES instance should be a new object after restart")
	}

	/// epochsInCurrentRun resets to 0 at each restart boundary.
	func testEpochsInCurrentRunResetsOnRestart() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 3
		)

		var restartsSeen = 0
		var prevIndex = 0

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }

			if bipop.currentRestartIndex != prevIndex {
				XCTAssertEqual(bipop.epochsInCurrentRun, 0,
					"epochsInCurrentRun must be 0 at restart \(bipop.currentRestartIndex)")
				restartsSeen += 1
				prevIndex = bipop.currentRestartIndex
			}

			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertEqual(restartsSeen, 3, "Should have seen 3 restart transitions")
	}

	/// Budget accounting: evaluationsUsed = populationSize * epochsCompleted for each record.
	func testBudgetAccountingIsExact() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 6,
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 2
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		var expectedLarge = 0
		var expectedSmall = 0

		for record in bipop.restartHistory {
			// Each epoch evaluates populationSize candidates
			XCTAssertEqual(record.evaluationsUsed, record.populationSize * record.epochsCompleted,
				"Record \(record.index): evaluationsUsed should be popSize * epochs")

			switch record.regime {
			case .initial, .large:
				expectedLarge += record.evaluationsUsed
			case .small:
				expectedSmall += record.evaluationsUsed
			}
		}

		XCTAssertEqual(bipop.largeBudgetUsed, expectedLarge)
		XCTAssertEqual(bipop.smallBudgetUsed, expectedSmall)
		XCTAssertEqual(bipop.totalEvaluations, expectedLarge + expectedSmall)
	}

	/// Restart record indices are sequential 0, 1, 2, ...
	func testRestartIndicesAreSequential() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertEqual(bipop.restartHistory.count, 6, "initial + 5 restarts = 6 records")

		for (i, record) in bipop.restartHistory.enumerated() {
			XCTAssertEqual(record.index, i, "Record at position \(i) should have index \(i)")
		}
	}

	/// startEpoch returns candidate count matching the current CMAES population size.
	func testStartEpochReturnsCandidateCountMatchingPopSize() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 6,
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }

			XCTAssertEqual(candidates.count, bipop.cmaes.populationSize,
				"Candidate count must match CMAES population size at restart \(bipop.currentRestartIndex)")

			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}
	}

	/// Large restart uses defaultStepSigma, not a random small sigma.
	func testLargeRestartUsesDefaultStepSigma() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.5,
			maxRestarts: 10,
			maxEpochsPerRestart: 1
		)

		var foundLarge = false
		var lastIndex = 0

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }

			if bipop.currentRestartIndex != lastIndex {
				if bipop.currentRegime == .large {
					XCTAssertEqual(bipop.cmaes.stepSigma, 0.5,
						"Large restart should use defaultStepSigma (0.5)")
					foundLarge = true
				}
				lastIndex = bipop.currentRestartIndex
			}

			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		XCTAssertTrue(foundLarge, "Should have encountered at least one large restart")
	}

	// MARK: - Convergence / Optimization Correctness

	/// BIPOP on sphere function converges near the origin.
	func testSphereConvergence() {
		var evaluator = SphereObjectiveEvaluator()
		let bipop = BIPOPCMAES(
			startSolution: [5.0, 5.0, 5.0],
			stepSigma: 1.0,
			maxRestarts: 3,
			maxEpochsPerRestart: 100
		)
		bipop.run(evaluator: &evaluator)

		XCTAssertNotNil(bipop.bestSolution)
		XCTAssertLessThan(bipop.bestSolution!.value, 1.0,
			"Sphere function should converge near 0")
		for component in bipop.bestSolution!.solution {
			XCTAssertLessThan(abs(component), 1.0,
				"Each component should be near 0")
		}
	}

	/// Statistically verify BIPOP outperforms single-run CMA-ES on multimodal Rastrigin.
	func testBIPOPAdvantageOnMultimodal_Statistical() {
		var bipopWins = 0
		let trials = 20

		for _ in 0..<trials {
			let startSolution = [3.0, 3.0, 3.0]

			// Single-run CMA-ES
			var eval1 = RastriginObjectiveEvaluator()
			let single = CMAES(
				startSolution: startSolution,
				populationSize: CMAES.populationSize(forDimensions: 3),
				stepSigma: 1.0
			)
			for _ in 0..<100 {
				single.epoch(evaluator: &eval1) { _, _ in }
			}

			// BIPOP-CMA-ES with comparable total budget
			var eval2 = RastriginObjectiveEvaluator()
			let bipop = BIPOPCMAES(
				startSolution: startSolution,
				stepSigma: 1.0,
				maxRestarts: 5,
				maxEpochsPerRestart: 20
			)
			bipop.run(evaluator: &eval2)

			if bipop.bestSolution!.value < single.bestSolution!.value {
				bipopWins += 1
			}
		}

		XCTAssertGreaterThanOrEqual(bipopWins, 10,
			"BIPOP should win at least 50% of trials on Rastrigin, won \(bipopWins)/\(trials)")
	}

	/// run() API produces valid finished state with correct counts.
	func testRunAPIProducesValidResults() {
		var evaluator = SphereObjectiveEvaluator()
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0, 3.0],
			stepSigma: 0.3,
			maxRestarts: 2,
			maxEpochsPerRestart: 10
		)
		bipop.run(evaluator: &evaluator)

		XCTAssertTrue(bipop.isFinished)
		XCTAssertEqual(bipop.restartHistory.count, 3, "initial + 2 restarts = 3")
		XCTAssertNotNil(bipop.bestSolution)
		XCTAssertGreaterThan(bipop.totalEvaluations, 0)
		XCTAssertEqual(bipop.totalEpochsCompleted, 30, "3 runs × 10 epochs = 30")
	}

	/// Bounded optimization finds solution within bounds.
	func testBoundedOptimization_SolutionWithinBounds() {
		let config = CMAES.SearchSpaceConfiguration(
			bounds: [0.0...10.0, 0.0...10.0],
			scalingFactors: [1.0, 1.0],
			bchm: .darwinianReflection
		)
		var evaluator = SphereObjectiveEvaluator()
		let bipop = BIPOPCMAES(
			startSolution: [5.0, 5.0],
			stepSigma: 1.0,
			maxRestarts: 3,
			maxEpochsPerRestart: 50,
			searchSpaceConfiguration: config
		)
		bipop.run(evaluator: &evaluator)

		XCTAssertNotNil(bipop.bestSolution)
		for (i, component) in bipop.bestSolution!.solution.enumerated() {
			XCTAssertGreaterThanOrEqual(component, -0.5,
				"Component \(i) should be near lower bound, got \(component)")
			XCTAssertLessThanOrEqual(component, 10.5,
				"Component \(i) should be within upper bound, got \(component)")
		}
	}

	// MARK: - Algorithm Edge Cases

	/// When largeBudgetUsed == smallBudgetUsed exactly, large is chosen (the <= condition).
	func testBudgetTieBreaking_LargeChosenWhenEqual() {
		// With populationSize=2, small pop formula: max(2, floor(2 * (0.5*u)^2))
		// floor(2 * [0..0.25]) = floor([0..0.5]) = 0 for all u, so max(2, 0) = 2 always.
		// This guarantees deterministic budget matching.
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 2,
			stepSigma: 0.3,
			maxRestarts: 3,
			maxEpochsPerRestart: 1
		)

		// Epoch 1: initial run (1 epoch × pop=2 = 2 evals → largeBudget=2)
		var candidates = bipop.startEpoch()
		var fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)

		// Restart 1: largeBudget(2) > smallBudget(0) → small
		candidates = bipop.startEpoch()
		XCTAssertEqual(bipop.currentRegime, .small)
		fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)
		// Now: largeBudget=2, smallBudget=2 (tie)

		// Restart 2: largeBudget(2) <= smallBudget(2) → large (tie-breaking)
		candidates = bipop.startEpoch()
		XCTAssertEqual(bipop.currentRegime, .large,
			"When budgets are tied, large regime should be chosen (<=)")
	}

	/// nextLargePopulationSize tracks correctly regardless of intervening small restarts.
	func testNextLargePopSizeTracksIndependentlyOfSmallRestarts() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			populationSize: 4,
			stepSigma: 0.3,
			maxRestarts: 10,
			maxEpochsPerRestart: 1
		)

		while !bipop.isFinished {
			let candidates = bipop.startEpoch()
			guard !candidates.isEmpty else { break }
			let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
			bipop.finishEpoch(candidateFitnesses: fitnesses)
		}

		// Extract large-regime pop sizes in order
		let largePops = bipop.restartHistory
			.filter { $0.regime == .initial || $0.regime == .large }
			.sorted(by: { $0.index < $1.index })
			.map { $0.populationSize }

		// Verify geometric progression regardless of how many small restarts are between them
		XCTAssertEqual(largePops[0], 4)
		for i in 1..<largePops.count {
			XCTAssertEqual(largePops[i], largePops[i - 1] * 2,
				"Large pop at position \(i) should double, but small restarts should not interfere")
		}

		// Verify the total pattern includes some small restarts between large ones
		let smallCount = bipop.restartHistory.filter { $0.regime == .small }.count
		XCTAssertGreaterThan(smallCount, 0, "There should be small restarts interspersed")
	}

	/// bestSolution is nil before first epoch, cmaes.xmean matches start solution.
	func testBestSolutionNilBeforeFirstEpoch() {
		let start = [3.0, 4.0, 5.0]
		let bipop = BIPOPCMAES(
			startSolution: start,
			stepSigma: 0.3
		)

		XCTAssertNil(bipop.bestSolution)
		XCTAssertEqual(bipop.originalStartSolution, start)
		XCTAssertEqual(bipop.cmaes.xmean, start)
	}

	/// Calling stop() immediately after init records a zero-epoch run.
	func testZeroEpochRunViaStop() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 100
		)

		bipop.stop()

		XCTAssertTrue(bipop.isFinished)
		XCTAssertEqual(bipop.restartHistory.count, 1)
		XCTAssertEqual(bipop.restartHistory[0].epochsCompleted, 0)
		XCTAssertEqual(bipop.restartHistory[0].regime, .initial)
		XCTAssertEqual(bipop.restartHistory[0].evaluationsUsed, 0)
		XCTAssertEqual(bipop.totalEvaluations, 0)
		XCTAssertEqual(bipop.totalEpochsCompleted, 0)
		XCTAssertNil(bipop.bestSolution)
	}

	/// Calling stop() multiple times is idempotent (does not duplicate records).
	func testStopIsIdempotent() {
		let bipop = BIPOPCMAES(
			startSolution: [1.0, 2.0],
			stepSigma: 0.3,
			maxRestarts: 5,
			maxEpochsPerRestart: 100
		)

		// Run 1 epoch
		let candidates = bipop.startEpoch()
		let fitnesses = candidates.map { ($0, $0.map { $0 * $0 }.reduce(0, +)) }
		bipop.finishEpoch(candidateFitnesses: fitnesses)

		bipop.stop()
		let historyCountAfterFirstStop = bipop.restartHistory.count

		bipop.stop()  // second call should be no-op
		XCTAssertEqual(bipop.restartHistory.count, historyCountAfterFirstStop,
			"Second stop() should not add another record")
		XCTAssertEqual(bipop.restartHistory.count, 1)
		XCTAssertTrue(bipop.isFinished)
	}

	// MARK: - allTests (Linux support)

	static var allTests = [
		("testDefaultInit", testDefaultInit),
		("testCustomInit", testCustomInit),
		("testCustomPopulationSize", testCustomPopulationSize),
		("testSearchSpaceConfigPassthrough", testSearchSpaceConfigPassthrough),
		("testSingleEpoch", testSingleEpoch),
		("testRestartTriggeredAfterMaxEpochs", testRestartTriggeredAfterMaxEpochs),
		("testIsFinishedAfterAllRestarts", testIsFinishedAfterAllRestarts),
		("testMaxRestartsZero", testMaxRestartsZero),
		("testFirstRestartIsSmallRegime", testFirstRestartIsSmallRegime),
		("testLargeRestartDoublesPopulation", testLargeRestartDoublesPopulation),
		("testSmallRestartPopulationBounds", testSmallRestartPopulationBounds),
		("testSmallRestartStepSigma", testSmallRestartStepSigma),
		("testGlobalBestPreservedAcrossRestarts", testGlobalBestPreservedAcrossRestarts),
		("testRestartStartsFromBestSolution", testRestartStartsFromBestSolution),
		("testTotalEvaluationsAccuracy", testTotalEvaluationsAccuracy),
		("testTotalEpochsAccuracy", testTotalEpochsAccuracy),
		("testInitialRunCountsAsLargeBudget", testInitialRunCountsAsLargeBudget),
		("testRestartRecordAccuracy", testRestartRecordAccuracy),
		("testStopMidRun", testStopMidRun),
		("testFinishEpochAfterStopIsNoop", testFinishEpochAfterStopIsNoop),
		("testCheckpointRoundTrip", testCheckpointRoundTrip),
		("testCheckpointMidRestart", testCheckpointMidRestart),
		("testCorruptCheckpointThrows", testCorruptCheckpointThrows),
		("testOneDimensional", testOneDimensional),
		("testHighDimensional", testHighDimensional),
		("testLargeMaxRestarts", testLargeMaxRestarts),
		("testFlatFitnessLandscape", testFlatFitnessLandscape),
		("testVerySmallStepSigma", testVerySmallStepSigma),
		("testVeryLargeStepSigma", testVeryLargeStepSigma),
		("testMinimumPopulationSize", testMinimumPopulationSize),
		("testBoundsPreservedAcrossRestarts", testBoundsPreservedAcrossRestarts),
		("testBIPOPOnRastrigin", testBIPOPOnRastrigin),
		// Statistical Correctness
		("testSmallPopulationDistribution_MeanAndBounds", testSmallPopulationDistribution_MeanAndBounds),
		("testSmallPopulationDistribution_SkewedTowardMinimum", testSmallPopulationDistribution_SkewedTowardMinimum),
		("testSmallSigmaDistribution_UniformInRange", testSmallSigmaDistribution_UniformInRange),
		("testLargePopulationGeometricProgression_ExactDoubling", testLargePopulationGeometricProgression_ExactDoubling),
		("testRegimeAlternation_FollowsBudgetRule", testRegimeAlternation_FollowsBudgetRule),
		("testRegimeAlternation_ContinuousSmallWhenLargeBudgetDominates", testRegimeAlternation_ContinuousSmallWhenLargeBudgetDominates),
		// State Machine Correctness
		("testExactStateTransitions_FullRun", testExactStateTransitions_FullRun),
		("testCMAESInstanceReplacedOnRestart", testCMAESInstanceReplacedOnRestart),
		("testEpochsInCurrentRunResetsOnRestart", testEpochsInCurrentRunResetsOnRestart),
		("testBudgetAccountingIsExact", testBudgetAccountingIsExact),
		("testRestartIndicesAreSequential", testRestartIndicesAreSequential),
		("testStartEpochReturnsCandidateCountMatchingPopSize", testStartEpochReturnsCandidateCountMatchingPopSize),
		("testLargeRestartUsesDefaultStepSigma", testLargeRestartUsesDefaultStepSigma),
		// Convergence / Optimization
		("testSphereConvergence", testSphereConvergence),
		("testBIPOPAdvantageOnMultimodal_Statistical", testBIPOPAdvantageOnMultimodal_Statistical),
		("testRunAPIProducesValidResults", testRunAPIProducesValidResults),
		("testBoundedOptimization_SolutionWithinBounds", testBoundedOptimization_SolutionWithinBounds),
		// Algorithm Edge Cases
		("testBudgetTieBreaking_LargeChosenWhenEqual", testBudgetTieBreaking_LargeChosenWhenEqual),
		("testNextLargePopSizeTracksIndependentlyOfSmallRestarts", testNextLargePopSizeTracksIndependentlyOfSmallRestarts),
		("testBestSolutionNilBeforeFirstEpoch", testBestSolutionNilBeforeFirstEpoch),
		("testZeroEpochRunViaStop", testZeroEpochRunViaStop),
		("testStopIsIdempotent", testStopIsIdempotent),
	]
}
