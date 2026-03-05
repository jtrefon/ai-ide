import XCTest
@testable import osx_ide

final class RetrievalIntentClassifierTests: XCTestCase {
    var classifier: RetrievalIntentClassifier!
    
    override func setUp() {
        super.setUp()
        classifier = RetrievalIntentClassifier()
    }
    
    override func tearDown() {
        classifier = nil
        super.tearDown()
    }
    
    // MARK: - Bugfix Intent Tests
    
    func testClassifiesBugfixIntent() {
        let bugfixInputs = [
            "fix the authentication bug",
            "resolve crash in payment flow",
            "debug memory leak",
            "patch security vulnerability",
            "repair broken validation"
        ]
        
        for input in bugfixInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .bugfix, "Should classify '\(input)' as bugfix")
        }
    }
    
    // MARK: - Feature Intent Tests
    
    func testClassifiesFeatureIntent() {
        let featureInputs = [
            "add payment processing",
            "implement new dashboard",
            "create user profile page",
            "build notification system",
            "develop API integration"
        ]
        
        for input in featureInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .feature, "Should classify '\(input)' as feature")
        }
    }
    
    // MARK: - Refactor Intent Tests
    
    func testClassifiesRefactorIntent() {
        let refactorInputs = [
            "refactor authentication service",
            "restructure database layer",
            "reorganize file structure",
            "improve code organization",
            "extract common logic"
        ]
        
        for input in refactorInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .refactor, "Should classify '\(input)' as refactor")
        }
    }
    
    // MARK: - Explanation Intent Tests
    
    func testClassifiesExplanationIntent() {
        let explanationInputs = [
            "explain how authentication works",
            "describe the payment flow",
            "what does this function do",
            "how is data stored",
            "show me the architecture"
        ]
        
        for input in explanationInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .explanation, "Should classify '\(input)' as explanation")
        }
    }
    
    // MARK: - Tests Intent Tests
    
    func testClassifiesTestsIntent() {
        let testsInputs = [
            "add unit tests for auth service",
            "write test cases for validation",
            "create integration tests",
            "add test coverage for payment",
            "implement test suite"
        ]
        
        for input in testsInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .tests, "Should classify '\(input)' as tests")
        }
    }
    
    // MARK: - Cleanup Intent Tests
    
    func testClassifiesCleanupIntent() {
        let cleanupInputs = [
            "remove unused code",
            "delete deprecated functions",
            "clean up imports",
            "remove dead code",
            "eliminate duplicate implementations"
        ]
        
        for input in cleanupInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .cleanup, "Should classify '\(input)' as cleanup")
        }
    }
    
    // MARK: - Other Intent Tests
    
    func testClassifiesOtherIntent() {
        let otherInputs = [
            "update documentation",
            "change color scheme",
            "adjust spacing",
            "modify configuration",
            "hello world"
        ]
        
        for input in otherInputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, .other, "Should classify '\(input)' as other")
        }
    }
    
    // MARK: - Case Insensitivity Tests
    
    func testClassificationIsCaseInsensitive() {
        let inputs = [
            ("FIX BUG", RetrievalIntent.bugfix),
            ("Add Feature", RetrievalIntent.feature),
            ("REFACTOR CODE", RetrievalIntent.refactor),
            ("explain logic", RetrievalIntent.explanation)
        ]
        
        for (input, expectedIntent) in inputs {
            let intent = classifier.classify(userInput: input)
            XCTAssertEqual(intent, expectedIntent, "Classification should be case insensitive for '\(input)'")
        }
    }
    
    // MARK: - Priority Tests
    
    func testBugfixTakesPriorityOverFeature() {
        let input = "add feature to fix authentication bug"
        let intent = classifier.classify(userInput: input)
        XCTAssertEqual(intent, .bugfix, "Bugfix should take priority when multiple intents present")
    }
    
    func testRefactorTakesPriorityOverOther() {
        let input = "update and refactor the service"
        let intent = classifier.classify(userInput: input)
        XCTAssertEqual(intent, .refactor, "Refactor should take priority over generic update")
    }
    
    // MARK: - Edge Cases
    
    func testEmptyInputReturnsOther() {
        let intent = classifier.classify(userInput: "")
        XCTAssertEqual(intent, .other, "Empty input should return other")
    }
    
    func testWhitespaceOnlyReturnsOther() {
        let intent = classifier.classify(userInput: "   ")
        XCTAssertEqual(intent, .other, "Whitespace-only input should return other")
    }
    
    func testAmbiguousInputReturnsFirstMatch() {
        let input = "fix and add and refactor"
        let intent = classifier.classify(userInput: input)
        XCTAssertNotEqual(intent, .other, "Should match one of the intents")
    }
    
    // MARK: - Consistency Tests
    
    func testClassificationIsConsistent() {
        let input = "fix authentication bug"
        let intent1 = classifier.classify(userInput: input)
        let intent2 = classifier.classify(userInput: input)
        let intent3 = classifier.classify(userInput: input)
        
        XCTAssertEqual(intent1, intent2, "Classification should be consistent")
        XCTAssertEqual(intent2, intent3, "Classification should be consistent")
    }
    
    // MARK: - Real-World Examples
    
    func testRealWorldBugfixExamples() {
        let examples = [
            "The login button doesn't work, please fix it",
            "There's a crash when submitting the form, need to debug",
            "Memory leak in the image loader needs to be resolved"
        ]
        
        for example in examples {
            let intent = classifier.classify(userInput: example)
            XCTAssertEqual(intent, .bugfix, "Should classify real-world bugfix: '\(example)'")
        }
    }
    
    func testRealWorldFeatureExamples() {
        let examples = [
            "I need to add a new payment method option",
            "Can you implement dark mode support",
            "Let's create a user profile editing screen"
        ]
        
        for example in examples {
            let intent = classifier.classify(userInput: example)
            XCTAssertEqual(intent, .feature, "Should classify real-world feature: '\(example)'")
        }
    }
    
    func testRealWorldExplanationExamples() {
        let examples = [
            "Can you explain how the caching system works?",
            "What's the purpose of this middleware?",
            "Help me understand the data flow"
        ]
        
        for example in examples {
            let intent = classifier.classify(userInput: example)
            XCTAssertEqual(intent, .explanation, "Should classify real-world explanation: '\(example)'")
        }
    }
}
