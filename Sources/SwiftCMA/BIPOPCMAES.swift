//
//  BIPOPCMAES.swift
//  SwiftCMAES
//
//  BIPOP-CMA-ES restart strategy wrapper around CMAES.
//

import Foundation

/// BIPOP-CMA-ES: a multi-restart strategy that alternates between large-population
/// (exploration) and small-population (local refinement) restarts.
///
/// Wraps the core `CMAES` class. After each run completes its epoch budget,
/// a new `CMAES` instance is created with a population size chosen by the
/// BIPOP regime selection rule.
///
/// Usage with `startEpoch`/`finishEpoch` API:
/// ```swift
/// let bipop = BIPOPCMAES(startSolution: [...], stepSigma: 0.3, maxRestarts: 5)
/// while !bipop.isFinished {
///     let candidates = bipop.startEpoch()
///     let fitnesses: [([Double], Double)] = evaluate(candidates)
///     bipop.finishEpoch(candidateFitnesses: fitnesses)
/// }
/// print(bipop.bestSolution)
/// ```
///
/// Usage with `ObjectiveEvaluator` convenience API:
/// ```swift
/// let bipop = BIPOPCMAES(startSolution: [...], stepSigma: 0.3, maxRestarts: 5)
/// bipop.run(evaluator: &myEvaluator, maxEpochsPerRestart: 100)
/// print(bipop.bestSolution)
/// ```
public class BIPOPCMAES: Codable {

	/// The restart regime used for a given run.
	public enum Regime: String, Codable {
		/// Initial run with default population size.
		case initial
		/// Large-population restart (exploration). Population doubles each time.
		case large
		/// Small-population restart (local refinement). Small random population and step size.
		case small
	}

	/// Summary of a completed restart run.
	public struct RestartRecord: Codable {
		/// 0-based restart index (0 = initial run).
		public let index: Int
		/// Which BIPOP regime was used.
		public let regime: Regime
		/// Population size used for this run.
		public let populationSize: Int
		/// Step sigma at the start of this run.
		public let initialStepSigma: Double
		/// Number of epochs completed in this run.
		public let epochsCompleted: Int
		/// Total function evaluations consumed (countEval delta).
		public let evaluationsUsed: Int
		/// Best fitness found during this run.
		public let bestFitness: Double?
	}

	// MARK: - Configuration (set at init, immutable)

	/// Dimensionality of the search space.
	public let n: Int
	/// Maximum number of restarts after the initial run.
	public let maxRestarts: Int
	/// Maximum epochs (generations) per restart run.
	public let maxEpochsPerRestart: Int
	/// Default population size for dimensionality n.
	public let defaultPopulationSize: Int
	/// Default step sigma (used for initial and large restarts).
	public let defaultStepSigma: Double
	/// Original start solution (used when no best solution exists yet).
	public let originalStartSolution: Vector
	/// Search space configuration (bounds, scaling, BCHM). Passed to each CMAES instance.
	public let searchSpaceConfiguration: CMAES.SearchSpaceConfiguration?

	// MARK: - State (mutated during optimization)

	/// The current underlying CMA-ES instance. Replaced on each restart.
	public private(set) var cmaes: CMAES
	/// Index of the current restart (0 = initial run).
	public private(set) var currentRestartIndex: Int = 0
	/// The regime of the current run.
	public private(set) var currentRegime: Regime = .initial
	/// Number of epochs completed in the current run.
	public private(set) var epochsInCurrentRun: Int = 0
	/// Population size used for the next large restart (doubles each time).
	public private(set) var nextLargePopulationSize: Int
	/// Total function evaluations consumed by all large-regime runs (including initial).
	public private(set) var largeBudgetUsed: Int = 0
	/// Total function evaluations consumed by all small-regime runs.
	public private(set) var smallBudgetUsed: Int = 0
	/// Global best solution across all restarts. `nil` until first epoch finishes.
	public private(set) var bestSolution: CMAES.EvaluatedSolution?
	/// History of all completed restart runs.
	public private(set) var restartHistory: [RestartRecord] = []
	/// `true` when all restarts have been exhausted or `stop()` was called.
	public private(set) var isFinished: Bool = false
	/// The actual initial step sigma used for the current run (tracks small restart sigmas).
	private var currentRunInitialSigma: Double = 0.0

	// MARK: - Initialization

	/// Creates a new BIPOP-CMA-ES optimizer.
	///
	/// - Parameters:
	///   - startSolution: Initial point in the search space.
	///   - populationSize: Override for population size of the initial run.
	///     Defaults to `CMAES.populationSize(forDimensions: n)`.
	///   - mu: Override for mu (recombination points). Defaults to `populationSize / 2`.
	///   - stepSigma: Initial step size (standard deviation).
	///   - maxRestarts: Maximum number of restarts after the initial run. Default: 5.
	///   - maxEpochsPerRestart: Maximum epochs per restart run. Default: 100.
	///   - searchSpaceConfiguration: Optional search space bounds and scaling.
	public init(
		startSolution: Vector,
		populationSize: Int? = nil,
		mu: Int? = nil,
		stepSigma: Double,
		maxRestarts: Int = 5,
		maxEpochsPerRestart: Int = 100,
		searchSpaceConfiguration: CMAES.SearchSpaceConfiguration? = nil
	) {
		precondition(maxRestarts >= 0, "maxRestarts must be non-negative")
		precondition(maxEpochsPerRestart > 0, "maxEpochsPerRestart must be positive")

		self.n = startSolution.count
		self.maxRestarts = maxRestarts
		self.maxEpochsPerRestart = maxEpochsPerRestart
		self.originalStartSolution = startSolution
		self.searchSpaceConfiguration = searchSpaceConfiguration

		let defaultPop = populationSize ?? CMAES.populationSize(forDimensions: startSolution.count)
		self.defaultPopulationSize = defaultPop
		self.defaultStepSigma = stepSigma
		self.nextLargePopulationSize = defaultPop  // first large restart will double this

		self.currentRunInitialSigma = stepSigma

		self.cmaes = CMAES(
			startSolution: startSolution,
			populationSize: defaultPop,
			mu: mu,
			stepSigma: stepSigma,
			searchSpaceConfiguration: searchSpaceConfiguration
		)
	}

	// MARK: - Epoch API (manual start/finish)

	/// Starts a new epoch in the current CMA-ES run.
	///
	/// Returns decoded candidate solutions. If the current run has exhausted its
	/// epoch budget, automatically triggers a restart before generating candidates.
	/// Returns an empty array if all restarts are exhausted (`isFinished == true`).
	public func startEpoch() -> [Vector] {
		if isFinished {
			return []
		}

		// Check if current run needs a restart
		if epochsInCurrentRun >= maxEpochsPerRestart {
			advanceToNextRestart()
			if isFinished {
				return []
			}
		}

		return cmaes.startEpoch()
	}

	/// Finishes the current epoch with evaluated fitnesses.
	///
	/// Updates the global best solution if a better one was found.
	/// Call this after evaluating all candidates from `startEpoch()`.
	public func finishEpoch(candidateFitnesses: [(Vector, Double)]) {
		guard !isFinished else { return }

		cmaes.finishEpoch(candidateFitnesses: candidateFitnesses)
		epochsInCurrentRun += 1

		// Update global best
		if let runBest = cmaes.bestSolution {
			if bestSolution == nil || runBest.value < bestSolution!.value {
				bestSolution = runBest
			}
		}
	}

	/// Convenience wrapper that runs the full BIPOP optimization using an ObjectiveEvaluator.
	///
	/// Runs the initial CMA-ES plus up to `maxRestarts` restarts, each for up to
	/// `maxEpochsPerRestart` epochs.
	public func run<E: ObjectiveEvaluator>(
		evaluator: inout E,
		solutionCallback: @escaping CMAES.SolutionCallback = { _, _ in }
	) where E.Genome == Vector {
		while !isFinished {
			let candidates = startEpoch()
			guard !candidates.isEmpty else { break }

			// Apply boundary handling for evaluation
			let candidatesForEval = appliedBoundaryHandling(candidates: candidates)
			let fitnesses = candidatesForEval.map { candidate in
				evaluator.objective(genome: candidate, solutionCallback: solutionCallback)
			}

			finishEpoch(candidateFitnesses: Array(zip(candidates, fitnesses)))
		}
	}

	/// Immediately stops the optimizer. Sets `isFinished = true` and records the current run.
	public func stop() {
		guard !isFinished else { return }
		recordCurrentRun()
		isFinished = true
	}

	// MARK: - Computed Properties

	/// Total number of function evaluations across all restarts.
	public var totalEvaluations: Int {
		// When finished, all evals are already in the budget counters.
		// When in progress, add the current run's evals (not yet recorded).
		if isFinished {
			return largeBudgetUsed + smallBudgetUsed
		}
		return largeBudgetUsed + smallBudgetUsed + Int(cmaes.countEval)
	}

	/// Total number of completed epochs across all restarts plus the current run.
	public var totalEpochsCompleted: Int {
		// When finished, all epochs are already in restartHistory.
		// When in progress, add the current run's epochs (not yet recorded).
		if isFinished {
			return restartHistory.reduce(0) { $0 + $1.epochsCompleted }
		}
		return restartHistory.reduce(0) { $0 + $1.epochsCompleted } + epochsInCurrentRun
	}

	// MARK: - Checkpointing

	/// Initializes a BIPOP-CMA-ES object from the checkpoint at the given file URL.
	public static func from(checkpoint: URL) throws -> BIPOPCMAES {
		let jsonData = try Data(contentsOf: checkpoint)
		return try JSONDecoder().decode(BIPOPCMAES.self, from: jsonData)
	}

	/// Saves the full BIPOP state (including the current CMAES) to a checkpoint file.
	public func save(checkpoint: URL) throws {
		let jsonData = try JSONEncoder().encode(self)
		try jsonData.write(to: checkpoint)
	}

	// MARK: - Private

	/// Records the current run into history and updates budget counters.
	private func recordCurrentRun() {
		let evalsUsed = Int(cmaes.countEval)
		let record = RestartRecord(
			index: currentRestartIndex,
			regime: currentRegime,
			populationSize: cmaes.populationSize,
			initialStepSigma: currentRunInitialSigma,
			epochsCompleted: epochsInCurrentRun,
			evaluationsUsed: evalsUsed,
			bestFitness: cmaes.bestSolution?.value
		)
		restartHistory.append(record)

		switch currentRegime {
		case .initial, .large:
			largeBudgetUsed += evalsUsed
		case .small:
			smallBudgetUsed += evalsUsed
		}
	}

	/// Finishes the current run and creates a new CMAES for the next restart.
	private func advanceToNextRestart() {
		recordCurrentRun()

		guard currentRestartIndex < maxRestarts else {
			isFinished = true
			return
		}

		currentRestartIndex += 1
		epochsInCurrentRun = 0

		// BIPOP regime selection: choose regime with fewer total evaluations
		let popSize: Int
		let sigma: Double

		if largeBudgetUsed <= smallBudgetUsed {
			// Large restart
			nextLargePopulationSize *= 2
			popSize = nextLargePopulationSize
			sigma = defaultStepSigma
			currentRegime = .large
		} else {
			// Small restart
			let u = Double.random(in: 0.0...1.0)
			popSize = max(2, Int(floor(Double(defaultPopulationSize) * pow(0.5 * u, 2.0))))
			sigma = 0.01 * 2.0 * Double.random(in: 0.0...1.0)
			currentRegime = .small
		}

		currentRunInitialSigma = sigma

		// Start solution: global best if available, otherwise original
		let startSolution = bestSolution?.solution ?? originalStartSolution

		cmaes = CMAES(
			startSolution: startSolution,
			populationSize: popSize,
			stepSigma: sigma,
			searchSpaceConfiguration: searchSpaceConfiguration
		)
	}

	/// Applies boundary handling to candidates for fitness evaluation.
	private func appliedBoundaryHandling(candidates: [Vector]) -> [Vector] {
		guard let config = searchSpaceConfiguration else {
			return candidates
		}
		switch config.bchm {
		case .darwinianReflection:
			return candidates.map { candidate in
				zip(candidate, config.bounds).map { element, bounds in
					bounds.flatMap { range in
						if element < range.lowerBound {
							return 2 * range.lowerBound - element
						} else if element > range.upperBound {
							return 2 * range.upperBound - element
						}
						return element
					} ?? element
				}
			}
		}
	}
}
