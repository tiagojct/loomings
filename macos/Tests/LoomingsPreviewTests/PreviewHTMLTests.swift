import Foundation
import Testing
@testable import LoomingsPreview

@Suite("Preview HTML parity")
struct PreviewHTMLTests {
    private static let fixtures = [
        "basic", "lists", "blocks", "table",
        "typography", "frontmatter", "frontmatter-fence", "unicode", "unsafe", "hardbreaks",
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

    @Test("A reference definition in frontmatter does not resolve a body link")
    func frontmatterReferenceDoesNotResolveBodyLink() {
        let source = "---\n[secret]: https://frontmatter.example\n---\n\n[body][secret]\n"
        let rendered = PreviewRenderer().render(source: source, documentURL: nil)
        #expect(rendered.html == "<p data-line=\"4\">[body][secret]</p>\n")
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
