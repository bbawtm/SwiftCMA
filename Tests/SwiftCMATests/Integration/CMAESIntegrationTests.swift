//
//  CMAESIntegrationTests.swift
//  SwiftCMAESTests
//
//  Created by Santiago Gonzalez on 4/13/19.
//  Copyright © 2019 Santiago Gonzalez. All rights reserved.
//

import XCTest
import SwiftCMA

final class CMAESIntegrationTests: XCTestCase {

	func testCMAES() {
		
		// Solution variables.
		let startRangeBound: Double = 5.0
		let startSolution = [
			Double.random(in: -startRangeBound...startRangeBound),
			Double.random(in: -startRangeBound...startRangeBound),
			Double.random(in: -startRangeBound...startRangeBound)
		]
		var fitness = AckleyObjectiveEvaluator()
		
		// Hyperparameters.
		let populationSize = CMAES.populationSize(forDimensions: startSolution.count)
		let varSpan = startRangeBound * 2 // (max - min) of all inputs.
		let stepSigma = 0.3 * varSpan // from Kaitlin Maile.
		
		// Perform CMA-ES.
		let cmaes = CMAES(startSolution: startSolution, populationSize: populationSize, stepSigma: stepSigma)
		var solution: Vector?
		var solutionFitness: Double?
		var bestSolution: CMAES.EvaluatedSolution?
		for i in 0..<1000 {
			guard solution == nil else { break }
			cmaes.epoch(evaluator: &fitness) { newSolution, newFitness in
				solution = newSolution
				solutionFitness = newFitness
			}
			
			if bestSolution == nil || bestSolution!.value > cmaes.bestSolution!.value {
				bestSolution = cmaes.bestSolution
			}
			print("\(i):   \(cmaes.bestSolution!.value)")
		}

		// Print solution.
		if let solution = solution, let fitness = solutionFitness {
			print("Found solution with fitness \(fitness): \(solution)")
		} else {
			print("Failed to perfect solution.")
			print("Best: \(bestSolution!.value): \(bestSolution!.solution)")
			XCTFail()
		}
	}
	
	func testConstrainedCMAES() {
		
		// Solution variables.
		let startRangeBound: Double = 5.0
		let startSolution = [
			Double.random(in: 1...startRangeBound),
			Double.random(in: 1...startRangeBound),
			Double.random(in: 1...startRangeBound)
		]
		print("START: \(startSolution)")
		let config = CMAES.SearchSpaceConfiguration(bounds: [1...50, nil, 1...50], scalingFactors: [1.0, 1.0, 1.0], bchm: .darwinianReflection)
		var fitness = SphereObjectiveEvaluator()
		
		// Hyperparameters.
		let populationSize = CMAES.populationSize(forDimensions: startSolution.count)
		let varSpan = startRangeBound - 1 // (max - min) of all inputs.
		let stepSigma = 0.3 * varSpan // from Kaitlin Maile.
		
		// Perform CMA-ES.
		let cmaes = CMAES(startSolution: startSolution, populationSize: populationSize, stepSigma: stepSigma, searchSpaceConfiguration: config)
		var solution: Vector?
		var solutionFitness: Double?
		var bestSolution: CMAES.EvaluatedSolution?
		for i in 0..<100 {
			guard solution == nil else { break }
			cmaes.epoch(evaluator: &fitness) { newSolution, newFitness in
				solution = newSolution
				solutionFitness = newFitness
			}
			
			if bestSolution == nil || bestSolution!.value > cmaes.bestSolution!.value {
				bestSolution = cmaes.bestSolution
			}
			print("\(i):   \(cmaes.bestSolution!.value)")
		}
//		print(RastriginObjectiveEvaluator().objective(genome: [1.0,0.0,1.0], solutionCallback: { _, _ in 1+1 }))

		// Print solution.
		if let solution = solution, let fitness = solutionFitness {
			print("Found solution with fitness \(fitness): \(solution)")
		} else {
			print("Failed to perfect solution.")
			print("Best: \(bestSolution!.value): \(bestSolution!.solution)")
			XCTFail()
		}
	}

	func testCustomMu() {
		let dimensions = 3
		let populationSize = 7
		let startSolution = Array(repeating: 1.0, count: dimensions)
		let cmaes = CMAES(startSolution: startSolution, populationSize: populationSize, mu: 5, stepSigma: 0.3)
		XCTAssertEqual(cmaes.mu, 5)

		let candidates = cmaes.startEpoch()
		XCTAssertEqual(candidates.count, populationSize)

		let fitnesses = candidates.map { candidate -> (Vector, Double) in
			let value = candidate.map { $0 * $0 }.reduce(0, +)
			return (candidate, value)
		}
		cmaes.finishEpoch(candidateFitnesses: fitnesses)
	}

	func testDefaultMu() {
		let dimensions = 3
		let populationSize = 8
		let startSolution = Array(repeating: 1.0, count: dimensions)
		let cmaes = CMAES(startSolution: startSolution, populationSize: populationSize, stepSigma: 0.3)
		XCTAssertEqual(cmaes.mu, populationSize / 2)
	}

	static var allTests = [
        ("testCMAES", testCMAES),
		("testConstrainedCMAES", testConstrainedCMAES),
		("testCustomMu", testCustomMu),
		("testDefaultMu", testDefaultMu),
    ]
	
}

