import XCTest
@testable import osx_ide

final class RAGPreventionHarnessTests: XCTestCase {
    var tempProjectRoot: URL!
    var fileSystemService: FileSystemService!
    var preventionEngine: PreWritePreventionEngine!
    
    override func setUp() {
        super.setUp()
        tempProjectRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("RAGPreventionHarness_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempProjectRoot, withIntermediateDirectories: true)
        fileSystemService = FileSystemService()
        preventionEngine = PreWritePreventionEngine(
            fileSystemService: fileSystemService,
            projectRoot: tempProjectRoot
        )
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempProjectRoot)
        preventionEngine = nil
        fileSystemService = nil
        tempProjectRoot = nil
        super.tearDown()
    }
    
    // MARK: - End-to-End Duplicate Prevention Scenarios
    
    func testPreventsDuplicateServiceImplementation() throws {
        let existingServicePath = tempProjectRoot.appendingPathComponent("Services/AuthService.swift")
        try FileManager.default.createDirectory(
            at: existingServicePath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let existingContent = """
        class AuthService {
            func authenticate(username: String, password: String) -> Bool {
                return username == "admin" && password == "secret"
            }
        }
        """
        try fileSystemService.writeFile(content: existingContent, to: existingServicePath)
        
        let duplicateAttempt = """
        class AuthService {
            func authenticate(username: String, password: String) -> Bool {
                return username == "admin" && password == "secret"
            }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Services/AuthServiceDuplicate.swift",
                "content": duplicateAttempt
            ],
            allowOverride: false
        )
        
        XCTAssertEqual(result.outcome, .block, "Should block exact duplicate service implementation")
        XCTAssertGreaterThan(result.duplicateRiskCount, 0)
        
        let finding = result.findings.first(where: { $0.findingType == .duplicateImpl })
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.blockRecommended ?? false)
        XCTAssertEqual(finding?.severity, .critical)
    }
    
    func testPreventsDuplicateUtilityFunction() throws {
        let existingUtilPath = tempProjectRoot.appendingPathComponent("Utils/StringHelper.swift")
        try FileManager.default.createDirectory(
            at: existingUtilPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let existingContent = """
        func trimWhitespace(_ input: String) -> String {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        """
        try fileSystemService.writeFile(content: existingContent, to: existingUtilPath)
        
        let duplicateContent = """
        func trimWhitespace(_ input: String) -> String {
            return input.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        """
        
        let result = preventionEngine.check(
            toolName: "write_file",
            arguments: [
                "path": "Helpers/StringUtils.swift",
                "content": duplicateContent
            ],
            allowOverride: false
        )
        
        XCTAssertEqual(result.outcome, .block, "Should block duplicate utility function")
        XCTAssertGreaterThan(result.duplicateRiskCount, 0)
    }
    
    func testDetectsSymbolCollisionAcrossFiles() throws {
        let service1Path = tempProjectRoot.appendingPathComponent("PaymentService.swift")
        try fileSystemService.writeFile(content: "class PaymentProcessor { }", to: service1Path)
        
        let service2Content = "class PaymentProcessor { }"
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Billing/PaymentService.swift",
                "content": service2Content
            ],
            allowOverride: false
        )
        
        XCTAssertNotEqual(result.outcome, .pass, "Should detect symbol collision")
        XCTAssertGreaterThan(result.duplicateRiskCount, 0)
        
        let finding = result.findings.first(where: { $0.findingType == .duplicateImpl })
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.explanation.contains("duplicate") ?? false)
    }
    
    func testAllowsOverrideForJustifiedDuplication() throws {
        let existingPath = tempProjectRoot.appendingPathComponent("Original.swift")
        try fileSystemService.writeFile(content: "class Service { }", to: existingPath)
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Duplicate.swift",
                "content": "class Service { }"
            ],
            allowOverride: true
        )
        
        XCTAssertNotEqual(result.outcome, .block, "Override should prevent blocking")
        XCTAssertGreaterThan(result.findings.count, 0, "Should still report findings")
    }
    
    // MARK: - End-to-End Dead Code Prevention Scenarios
    
    func testDetectsOrphanedServiceCreation() throws {
        let mainPath = tempProjectRoot.appendingPathComponent("main.swift")
        try fileSystemService.writeFile(content: """
        func main() {
            print("Application started")
        }
        """, to: mainPath)
        
        let orphanServiceContent = """
        class OrphanService {
            func processData() {
                print("Processing")
            }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Services/OrphanService.swift",
                "content": orphanServiceContent
            ],
            allowOverride: false
        )
        
        XCTAssertNotEqual(result.outcome, .pass, "Should detect orphaned service")
        XCTAssertGreaterThan(result.deadCodeRiskCount, 0)
        
        let finding = result.findings.first(where: { $0.findingType == .deadCodeRisk })
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.explanation.contains("unreferenced") ?? false)
    }
    
    func testDetectsTempFileCreation() throws {
        let tempContent = """
        class TempProcessor {
            func process() { }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "tmp/TempProcessor.swift",
                "content": tempContent
            ],
            allowOverride: false
        )
        
        XCTAssertNotEqual(result.outcome, .pass, "Should detect temp file creation")
        XCTAssertGreaterThan(result.deadCodeRiskCount, 0)
        
        let finding = result.findings.first(where: { $0.findingType == .deadCodeRisk })
        XCTAssertNotNil(finding)
        XCTAssertTrue(finding?.explanation.contains("temporary") ?? false)
    }
    
    func testDetectsDraftImplementation() throws {
        let draftContent = """
        class DraftFeature {
            func draftMethod() { }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Features/DraftFeature.swift",
                "content": draftContent
            ],
            allowOverride: false
        )
        
        XCTAssertNotEqual(result.outcome, .pass, "Should detect draft implementation")
        XCTAssertGreaterThan(result.deadCodeRiskCount, 0)
    }
    
    func testAllowsReferencedNewService() throws {
        let mainPath = tempProjectRoot.appendingPathComponent("main.swift")
        try fileSystemService.writeFile(content: """
        func main() {
            let service = NewDataService()
            service.fetchData()
        }
        """, to: mainPath)
        
        let newServiceContent = """
        class NewDataService {
            func fetchData() {
                print("Fetching data")
            }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Services/NewDataService.swift",
                "content": newServiceContent
            ],
            allowOverride: false
        )
        
        XCTAssertEqual(result.outcome, .pass, "Should allow referenced new service")
        XCTAssertEqual(result.deadCodeRiskCount, 0)
    }
    
    // MARK: - Multi-File Write Scenarios
    
    func testDetectsIssuesInBatchWrite() throws {
        let existingPath = tempProjectRoot.appendingPathComponent("Existing.swift")
        try fileSystemService.writeFile(content: "class Existing { }", to: existingPath)
        
        let result = preventionEngine.check(
            toolName: "write_files",
            arguments: [
                "files": [
                    ["path": "Existing.swift", "content": "class Existing { }"],
                    ["path": "New.swift", "content": "class New { }"],
                    ["path": "tmp/Temp.swift", "content": "class Temp { }"]
                ]
            ],
            allowOverride: false
        )
        
        XCTAssertEqual(result.outcome, .block, "Should block batch write with critical issues")
        XCTAssertGreaterThan(result.duplicateRiskCount, 0, "Should detect duplicate")
        XCTAssertGreaterThan(result.deadCodeRiskCount, 0, "Should detect dead code risk")
    }
    
    // MARK: - Complex Real-World Scenarios
    
    func testPreventsDuplicateAuthenticationLogic() throws {
        let existingAuthPath = tempProjectRoot.appendingPathComponent("Auth/LoginService.swift")
        try FileManager.default.createDirectory(
            at: existingAuthPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        let existingAuth = """
        class LoginService {
            func login(email: String, password: String) -> Bool {
                guard !email.isEmpty, !password.isEmpty else { return false }
                let hashedPassword = hash(password)
                return validateCredentials(email: email, hash: hashedPassword)
            }
            
            private func hash(_ password: String) -> String {
                return password.sha256()
            }
            
            private func validateCredentials(email: String, hash: String) -> Bool {
                return database.verify(email: email, passwordHash: hash)
            }
        }
        """
        try fileSystemService.writeFile(content: existingAuth, to: existingAuthPath)
        
        let duplicateAuth = """
        class AuthenticationService {
            func login(email: String, password: String) -> Bool {
                guard !email.isEmpty, !password.isEmpty else { return false }
                let hashedPassword = hash(password)
                return validateCredentials(email: email, hash: hashedPassword)
            }
            
            private func hash(_ password: String) -> String {
                return password.sha256()
            }
            
            private func validateCredentials(email: String, hash: String) -> Bool {
                return database.verify(email: email, passwordHash: hash)
            }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Services/AuthenticationService.swift",
                "content": duplicateAuth
            ],
            allowOverride: false
        )
        
        XCTAssertEqual(result.outcome, .block, "Should block duplicate authentication logic")
        XCTAssertGreaterThan(result.duplicateRiskCount, 0)
    }
    
    func testAllowsSimilarButNotDuplicateImplementations() throws {
        let existingPath = tempProjectRoot.appendingPathComponent("UserService.swift")
        try fileSystemService.writeFile(content: """
        class UserService {
            func getUser(id: String) -> User? {
                return database.fetchUser(id: id)
            }
        }
        """, to: existingPath)
        
        let similarContent = """
        class ProductService {
            func getProduct(id: String) -> Product? {
                return database.fetchProduct(id: id)
            }
        }
        """
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "ProductService.swift",
                "content": similarContent
            ],
            allowOverride: false
        )
        
        XCTAssertEqual(result.outcome, .pass, "Should allow similar but distinct implementations")
    }
    
    // MARK: - Policy Outcome Verification
    
    func testGeneratesDetailedFindingsReport() throws {
        let existingPath = tempProjectRoot.appendingPathComponent("Service.swift")
        try fileSystemService.writeFile(content: "class Service { }", to: existingPath)
        
        let result = preventionEngine.check(
            toolName: "create_file",
            arguments: [
                "path": "Service.swift",
                "content": "class Service { }"
            ],
            allowOverride: false
        )
        
        XCTAssertFalse(result.findings.isEmpty, "Should generate findings")
        
        for finding in result.findings {
            XCTAssertFalse(finding.candidateFileSpan.isEmpty, "Should have candidate file span")
            XCTAssertFalse(finding.explanation.isEmpty, "Should have explanation")
            XCTAssertNotNil(finding.severity, "Should have severity")
        }
        
        let summary = result.summary
        XCTAssertFalse(summary.isEmpty, "Should generate summary")
        XCTAssertTrue(summary.contains("duplicate") || summary.contains("dead"), "Summary should describe issues")
    }
    
    func testTracksDebtMetrics() throws {
        let existingPath = tempProjectRoot.appendingPathComponent("Existing.swift")
        try fileSystemService.writeFile(content: "class Existing { }", to: existingPath)
        
        let result = preventionEngine.check(
            toolName: "write_files",
            arguments: [
                "files": [
                    ["path": "Existing.swift", "content": "class Existing { }"],
                    ["path": "tmp/Draft.swift", "content": "class Draft { }"]
                ]
            ],
            allowOverride: false
        )
        
        XCTAssertGreaterThan(result.duplicateRiskCount, 0, "Should track duplicate risk count")
        XCTAssertGreaterThan(result.deadCodeRiskCount, 0, "Should track dead code risk count")
        
        let totalRisks = result.duplicateRiskCount + result.deadCodeRiskCount
        XCTAssertEqual(totalRisks, result.findings.count, "Risk counts should match findings")
    }
}
