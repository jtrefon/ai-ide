import Foundation

final class FileSystemService {
    func readFile(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }

        // Lossy fallback to ensure the editor shows something instead of appearing broken.
        return String(decoding: data, as: UTF8.self)
    }

    func writeFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeFile(content: String, toPath path: String) throws {
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
