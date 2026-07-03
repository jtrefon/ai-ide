import Testing
import Foundation
@testable import osx_ide

struct SymbolExtractorTests {

    @Test
    func testSwiftClass() {
        let code = """
        public final class AuthService {
            private let apiKey: String
            func validateUser(token: String) -> Bool {
                return true
            }
        }
        """
        let url = URL(fileURLWithPath: "/project/Sources/Auth/AuthService.swift")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 2)
        #expect(symbols[0].name == "AuthService")
        #expect(symbols[0].kind == "class")
        #expect(symbols[0].scope == "public")
        #expect(symbols[0].parentName == "")
        #expect(symbols[1].name == "validateUser")
        #expect(symbols[1].kind == "method")
        #expect(symbols[1].scope == "private")
        #expect(symbols[1].parentName == "AuthService")
    }

    @Test
    func testSwiftStruct() {
        let code = """
        struct Config {
            let timeout: Int
        }
        """
        let url = URL(fileURLWithPath: "/project/Sources/Config.swift")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 2)
        #expect(symbols[0].name == "Config")
        #expect(symbols[0].kind == "struct")
        #expect(symbols[1].name == "timeout")
        #expect(symbols[1].kind == "property")
    }

    @Test
    func testSwiftEnum() {
        let code = "enum HTTPMethod { case get, post }"
        let url = URL(fileURLWithPath: "/project/Sources/HTTP.swift")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 1)
        #expect(symbols[0].name == "HTTPMethod")
        #expect(symbols[0].kind == "enum")
    }

    @Test
    func testSwiftExtension() {
        let code = "extension String { var trimmed: String { self } }"
        let url = URL(fileURLWithPath: "/project/Sources/Extensions.swift")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count >= 1)
        #expect(symbols[0].kind == "extension")
    }

    @Test
    func testSwiftSignature() {
        let code = "func fetchUser(id: Int) async throws -> User?"
        let url = URL(fileURLWithPath: "/project/Sources/UserService.swift")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 1)
        #expect(symbols[0].name == "fetchUser")
        #expect(symbols[0].kind == "method")
        #expect(symbols[0].signature.contains("->"))
    }

    @Test
    func testSwiftTypealias() {
        let code = "typealias CompletionHandler = (Result<User, Error>) -> Void"
        let url = URL(fileURLWithPath: "/project/Sources/Types.swift")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 1)
        #expect(symbols[0].kind == "typealias")
        #expect(symbols[0].name == "CompletionHandler")
    }

    @Test
    func testJavaScriptClass() {
        let code = """
        export class UserService {
            constructor() {}
            async getUser(id) {}
        }
        """
        let url = URL(fileURLWithPath: "/project/src/UserService.js")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count >= 1)
        #expect(symbols[0].kind == "class")
        #expect(symbols[0].name == "UserService")
    }

    @Test
    func testJavaScriptFunction() {
        let code = "export function formatDate(date) { return '' }"
        let url = URL(fileURLWithPath: "/project/src/dateUtils.js")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 1)
        #expect(symbols[0].kind == "function")
        #expect(symbols[0].name == "formatDate")
        #expect(symbols[0].scope == "export")
    }

    @Test
    func testPythonClass() {
        let code = """
        class UserService:
            def get_user(self, id):
                pass
        """
        let url = URL(fileURLWithPath: "/project/src/user_service.py")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 2)
        #expect(symbols[0].name == "UserService")
        #expect(symbols[0].kind == "class")
        #expect(symbols[1].name == "get_user")
        #expect(symbols[1].kind == "method")
        #expect(symbols[1].parentName == "UserService")
    }

    @Test
    func testPythonFunction() {
        let code = "def validate_email(email): pass"
        let url = URL(fileURLWithPath: "/project/src/validation.py")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.count == 1)
        #expect(symbols[0].kind == "function")
        #expect(symbols[0].name == "validate_email")
    }

    @Test
    func testUnsupportedLanguage() {
        let code = "<?php echo 'hello'; ?>"
        let url = URL(fileURLWithPath: "/project/index.php")
        let symbols = SymbolExtractor.extract(from: url, content: code)
        #expect(symbols.isEmpty)
    }
}
