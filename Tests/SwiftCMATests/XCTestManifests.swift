import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
		testCase(BIPOPTests.allTests),
		testCase(CMAESIntegrationTests.allTests),
		testCase(CheckpointingTests.allTests),
		testCase(EigenDecompositionTests.allTests),
		testCase(LinearAlgebraTests.allTests)
    ]
}
#endif
