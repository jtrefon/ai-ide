import XCTest
@testable import osx_ide

final class ArgumentCollectorTests: XCTestCase {
    func testCollectValidJSON() async {
        let collector = ArgumentCollector()
        await collector.append(#"{"path": "/tmp/test.txt", "content": "hello"}"#)
        let result = await collector.collect()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["path"]?.stringValue, "/tmp/test.txt")
        XCTAssertEqual(result?["content"]?.stringValue, "hello")
    }

    func testCollectPartialJSONThenComplete() async {
        let collector = ArgumentCollector()
        await collector.append(#"{"path": "/tmp/test.txt""#)
        var result = await collector.collect()
        XCTAssertNil(result)
        await collector.append(#","content": "hello"}"#)
        result = await collector.collect()
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["path"]?.stringValue, "/tmp/test.txt")
        XCTAssertEqual(result?["content"]?.stringValue, "hello")
    }

    func testCollectEmptyBuffer() async {
        let collector = ArgumentCollector()
        let result = await collector.collect()
        XCTAssertNil(result)
    }

    func testResetClearsBuffer() async {
        let collector = ArgumentCollector()
        await collector.append(#"{"path": "/tmp/test.txt"}"#)
        await collector.reset()
        let result = await collector.collect()
        XCTAssertNil(result)
    }

    func testCollectNestedJSON() async {
        let collector = ArgumentCollector()
        await collector.append(#"{"files": [{"path": "a.txt", "content": "hello"}]}"#)
        let result = await collector.collect()
        XCTAssertNotNil(result)
    }

    func testArgumentParserValidJSON() {
        let result = ArgumentParser.parse(#"{"path": "/tmp/test.txt", "content": "hello"}"#)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?["path"]?.stringValue, "/tmp/test.txt")
    }

    func testArgumentParserMalformedJSON() {
        let result = ArgumentParser.parse("not json at all")
        XCTAssertNil(result)
    }

    func testArgumentParserEmptyString() {
        let result = ArgumentParser.parse("")
        XCTAssertNil(result)
    }
}
