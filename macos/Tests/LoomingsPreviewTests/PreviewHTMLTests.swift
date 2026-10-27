import Foundation
import Testing
@testable import LoomingsPreview

@Suite("Preview HTML parity")
struct PreviewHTMLTests {
    private static let fixtures = [
        "basic", "lists", "blocks", "table",
        "typography", "frontmatter", "unicode", "unsafe", "hardbreaks",
    ]

    @Test("Native HTML matches the web renderer", arguments: fixtures)
    func matchesWebRenderer(name: String) throws {
        let source = try fixture(name, extension: "md")
        let expected = try fixture(name, extension: "html")
        let rendered = PreviewRenderer().render(source: source, documentURL: nil)
        if rendered.html != expected {
            print("=== \(name) rendered ===\n\(rendered.html)\n=== expected ===")
            print(expected)
        }
        #expect(rendered.html == expected)
    }

    private func fixture(_ name: String, extension: String) throws -> String {
        guard let url = Bundle.module.url(
            forResource: name,
            withExtension: `extension`,
            subdirectory: "Fixtures"
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
