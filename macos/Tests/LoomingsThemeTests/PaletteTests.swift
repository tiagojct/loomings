import AppKit
import Foundation
import Testing
@testable import LoomingsTheme

@Suite("Exported palettes")
struct PaletteTests {
    private func library() throws -> PaletteLibrary {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/palettes.json")
        let data = try Data(contentsOf: url)
        guard let library = PaletteLibrary(data: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return library
    }

    @Test("All ten families and both modes are exported")
    func families() throws {
        let library = try library()
        #expect(library.familyOrder.count == 10)
        #expect(Set(library.familyOrder) == Set(library.families.keys))
        #expect(library.defaultFamily == "pequod")
        for family in library.familyOrder {
            let entry = try #require(library.families[family])
            #expect(!entry.label.isEmpty)
            #expect(entry.modes["dark"] != nil)
            #expect(entry.modes["light"] != nil)
        }
    }

    @Test("Contrast floors survive the export")
    func contrast() throws {
        let library = try library()
        for family in library.familyOrder {
            guard let entry = library.families[family] else { continue }
            for (mode, colors) in [("dark", entry.dark), ("light", entry.light)] {
                #expect(PaletteContrast.ratio(colors.fg, colors.bg) >= 7, "\(family) \(mode) fg/bg")
                #expect(PaletteContrast.ratio(colors.fgDim, colors.bg) >= 4.5, "\(family) \(mode) fgDim/bg")
                #expect(PaletteContrast.ratio(colors.onAccent, colors.accent) >= 4.5, "\(family) \(mode) onAccent/accent")
                #expect(PaletteContrast.ratio(colors.heading, colors.bg) >= 3, "\(family) \(mode) heading/bg")
                #expect(PaletteContrast.ratio(colors.accent, colors.bg) >= 3, "\(family) \(mode) accent/bg")
                #expect(PaletteContrast.ratio(colors.fg, colors.bgDeep) >= 4.5, "\(family) \(mode) fg/bgDeep")
                #expect(colors.selection != colors.bg, "\(family) \(mode) selection")
                #expect(PaletteContrast.ratio(colors.selection, colors.bg) >= 1.2, "\(family) \(mode) selection/bg")
            }
        }
    }

    @Test("System mode resolves to the actual light or dark palette")
    func systemResolution() throws {
        let library = try library()
        let dark = try #require(library.resolve(family: "pequod", mode: .system, systemIsDark: true))
        #expect(dark.isDark)
        #expect(dark.colors.bg == "0b1720" || dark.colors.bg == "#0b1720")

        let light = try #require(library.resolve(family: "pequod", mode: .system, systemIsDark: false))
        #expect(!light.isDark)
        #expect(light.colors.bg == "eae1d7" || light.colors.bg == "#eae1d7")
    }

    @Test("Hex colours parse and malformed values fail safely")
    func colors() {
        #expect(NSColor(hex: "#0b1720") != nil)
        #expect(NSColor(hex: "0b1720") != nil)
        #expect(NSColor(hex: "#xyzxyz") == nil)
        #expect(NSColor(hex: "#12345") == nil)
    }
}
