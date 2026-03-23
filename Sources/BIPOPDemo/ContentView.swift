import SwiftUI
import Charts

struct ContentView: View {
	@State private var runner = BIPOPRunner()

	private let regimeColors: KeyValuePairs<String, Color> = [
		"Initial": .blue,
		"Large": .green,
		"Small": .red
	]

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 24) {
				headerSection
				if runner.isComplete {
					trajectoryChart
					fitnessChart
					sigmaChart
					populationChart
					budgetChart
					parallelCoordinatesSection
				} else if runner.isRunning {
					ProgressView("Running BIPOP-CMA-ES...")
						.frame(maxWidth: .infinity, minHeight: 200)
				} else {
					Button("Run BIPOP-CMA-ES") {
						runner.run()
					}
					.buttonStyle(.borderedProminent)
					.frame(maxWidth: .infinity, minHeight: 200)
				}
			}
			.padding(24)
		}
		.frame(minWidth: 700, minHeight: 600)
		.onAppear {
			runner.run()
		}
	}

	// MARK: - Header

	private var headerSection: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("BIPOP-CMA-ES Algorithm Visualization")
				.font(.title.bold())
			Text("BI-Population CMA-ES alternates between large-population restarts (exploration) and small-population restarts (local refinement), choosing the regime with fewer total evaluations. Running on the 2D Rastrigin function (multimodal, global optimum at origin).")
				.font(.body)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Chart 1: Search Trajectory

	private var trajectoryChart: some View {
		GroupBox("1. Search Trajectory (xmean position in 2D space)") {
			Chart(runner.snapshots) { s in
				PointMark(
					x: .value("x₁", s.x),
					y: .value("x₂", s.y)
				)
				.foregroundStyle(by: .value("Regime", s.regime))
				.symbolSize(30)
				.opacity(0.7)
			}
			.chartForegroundStyleScale(regimeColors)
			.chartXAxisLabel("x₁")
			.chartYAxisLabel("x₂")
			.frame(height: 350)

			Text("Each point is the distribution mean (xmean) after one epoch. Colors show which restart regime generated it.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Chart 2: Best Fitness

	private var fitnessChart: some View {
		GroupBox("2. Best Fitness Over Time") {
			Chart {
				ForEach(runner.snapshots) { s in
					LineMark(
						x: .value("Epoch", s.id),
						y: .value("Best Fitness", s.bestFitness)
					)
					.foregroundStyle(.blue)
					.lineStyle(StrokeStyle(lineWidth: 2))
				}

				// Restart boundaries
				ForEach(runner.restartBoundaries, id: \.self) { epoch in
					RuleMark(x: .value("Restart", epoch))
						.foregroundStyle(.gray.opacity(0.5))
						.lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
				}
			}
			.chartXAxisLabel("Epoch")
			.chartYAxisLabel("Best Fitness")
			.frame(height: 300)

			Text("Global best fitness (lower is better). Dashed vertical lines mark restart boundaries.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Chart 3: Step Sigma

	private var sigmaChart: some View {
		GroupBox("3. Step Size (σ) Over Time") {
			Chart(runner.snapshots) { s in
				PointMark(
					x: .value("Epoch", s.id),
					y: .value("σ", s.stepSigma)
				)
				.foregroundStyle(by: .value("Regime", s.regime))
				.symbolSize(20)

				LineMark(
					x: .value("Epoch", s.id),
					y: .value("σ", s.stepSigma)
				)
				.foregroundStyle(by: .value("Regime", s.regime))
				.lineStyle(StrokeStyle(lineWidth: 1))
			}
			.chartForegroundStyleScale(regimeColors)
			.chartXAxisLabel("Epoch")
			.chartYAxisLabel("Step Size σ")
			.frame(height: 300)

			Text("Step size controls the search radius. Large restarts use the default σ; small restarts use tiny random σ ∈ (0, 0.02]. σ adapts within each run via CMA-ES.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Chart 4: Population Size

	private var populationChart: some View {
		GroupBox("4. Population Size per Restart Run") {
			Chart(runner.restarts) { r in
				BarMark(
					x: .value("Run", "Run \(r.id)"),
					y: .value("Population Size", r.populationSize),
					width: .ratio(0.7)
				)
				.foregroundStyle(by: .value("Regime", r.regime))
			}
			.chartForegroundStyleScale(regimeColors)
			.chartXAxisLabel("Run Index")
			.chartYAxisLabel("Population Size (λ)")
			.frame(height: 300)

			Text("Large restarts double the population each time (exploration). Small restarts use random small populations (local refinement).")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Chart 5: Budget Allocation

	private var budgetChart: some View {
		GroupBox("5. Cumulative Budget Allocation (Large vs Small)") {
			Chart(runner.budgetEntries) { b in
				BarMark(
					x: .value("Run", "Run \(b.runIndex)"),
					y: .value("Cumulative Evals", b.cumulativeEvals),
					width: .ratio(0.7)
				)
				.foregroundStyle(by: .value("Budget", b.type))
				.position(by: .value("Budget", b.type))
			}
			.chartForegroundStyleScale([
				"Large": Color.green,
				"Small": Color.red
			])
			.chartXAxisLabel("Run Index")
			.chartYAxisLabel("Cumulative Evaluations")
			.frame(height: 300)

			Text("BIPOP selects the regime with fewer cumulative evaluations, keeping the budgets roughly balanced.")
				.font(.caption)
				.foregroundStyle(.secondary)
		}
	}

	// MARK: - Chart 6: Per-Epoch Parallel Coordinates

	private var parallelCoordinatesSection: some View {
		VStack(alignment: .leading, spacing: 16) {
			Text("6. Per-Epoch Candidate Parameters (Parallel Coordinates)")
				.font(.title2.bold())

			Text("Each chart shows all candidates for one epoch. Vertical axes represent parameters x₁ and x₂, bounded by [-5, 5]. Lines connect each candidate's parameter values. Color indicates fitness (green = best, red = worst).")
				.font(.body)
				.foregroundStyle(.secondary)

			ForEach(runner.epochCandidates) { epoch in
				parallelCoordinatesChart(for: epoch)
			}
		}
	}

	private func parallelCoordinatesChart(for epoch: EpochCandidates) -> some View {
		let fitnessRange = fitnessMinMax(for: epoch)

		return GroupBox {
			Chart {
				ForEach(epoch.points) { point in
					LineMark(
						x: .value("Parameter", point.parameterName),
						y: .value("Value", point.value),
						series: .value("Candidate", point.candidateIndex)
					)
					.foregroundStyle(fitnessColor(
						fitness: point.fitness,
						minFitness: fitnessRange.min,
						maxFitness: fitnessRange.max
					))
					.lineStyle(StrokeStyle(lineWidth: 1.5))
					.opacity(0.6)
				}
			}
			.chartYScale(domain: -5.0...5.0)
			.chartYAxisLabel("Value")
			.chartLegend(.hidden)
			.frame(height: 200)
		} label: {
			HStack {
				Text("Epoch \(epoch.id)")
					.font(.headline)
				regimeBadge(epoch.regime)
				Text("Run \(epoch.restartIndex)")
					.font(.caption)
					.foregroundStyle(.secondary)
				Spacer()
				Text("Best: \(epoch.bestFitness, specifier: "%.2f")")
					.font(.caption.monospacedDigit())
					.foregroundStyle(.secondary)
			}
		}
	}

	private func regimeBadge(_ regime: String) -> some View {
		let color: Color = switch regime {
		case "Initial": .blue
		case "Large": .green
		case "Small": .red
		default: .gray
		}
		return Text(regime)
			.font(.caption.bold())
			.padding(.horizontal, 6)
			.padding(.vertical, 2)
			.background(color.opacity(0.2), in: RoundedRectangle(cornerRadius: 4))
			.foregroundStyle(color)
	}

	private struct FitnessRange {
		let min: Double
		let max: Double
	}

	private func fitnessMinMax(for epoch: EpochCandidates) -> FitnessRange {
		let fitnesses = Set(epoch.points.map(\.fitness))
		return FitnessRange(
			min: fitnesses.min() ?? 0,
			max: fitnesses.max() ?? 1
		)
	}

	private func fitnessColor(fitness: Double, minFitness: Double, maxFitness: Double) -> Color {
		let range = maxFitness - minFitness
		guard range > 0 else { return .green }
		let t = (fitness - minFitness) / range  // 0 = best, 1 = worst
		// Green → Yellow → Red
		if t < 0.5 {
			let p = t * 2.0
			return Color(red: p, green: 1.0, blue: 0.0)
		} else {
			let p = (t - 0.5) * 2.0
			return Color(red: 1.0, green: 1.0 - p, blue: 0.0)
		}
	}
}
