import Foundation
import LoomingsTheme

/// Standalone HTML for the Export menu. Stage 5 will replace the neutral
/// palette with the selected Ensigns family.
public enum PreviewHTMLExport {
    public static func document(title: String, bodyHTML: String) -> String {
        document(title: title, bodyHTML: bodyHTML, palette: nil)
    }

    public static func document(
        title: String,
        bodyHTML: String,
        palette: ResolvedPalette?
    ) -> String {
        let safeTitle = escape(title)
        let colors = palette?.colors
        let background = colors?.bg ?? "#faf9f5"
        let foreground = colors?.fg ?? "#1c1c1c"
        let heading = colors?.heading ?? foreground
        let emphasis = colors?.emphasis ?? foreground
        let accent = colors?.accentLight ?? "#8a4b12"
        let accentSolid = colors?.accent ?? accent
        let codeColor = colors?.code ?? "#3b3b3b"
        let codeBackground = colors?.bgDeep ?? "#efede6"
        let border = colors?.border ?? "#d8d3c6"
        let dim = colors?.fgDim ?? "#565656"
        let scheme = palette?.isDark == true ? "dark" : "light"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>\(safeTitle)</title>
        <style>
          :root { color-scheme: \(scheme); }
          body { max-width: 680px; margin: 0 auto; padding: 48px 24px;
                 font-family: "Source Serif 4", Georgia, 'Times New Roman', serif; font-size: 17px; line-height: 1.8;
                 background: \(background); color: \(foreground); }
          h1, h2, h3, h4, h5, h6 { line-height: 1.3; color: \(heading); }
          a { color: \(accent); }
          em { color: \(emphasis); }
          code { font-family: "JetBrains Mono", ui-monospace, 'SF Mono', Menlo, monospace; font-size: 0.9em;
                 background: \(codeBackground); color: \(codeColor); padding: 2px 6px; border-radius: 3px; }
          pre { background: \(codeBackground); border: 1px solid \(border); padding: 16px;
                border-radius: 4px; overflow-x: auto; }
          pre code { background: none; padding: 0; color: \(codeColor); }
          blockquote { border-left: 3px solid \(accentSolid); padding-left: 16px;
                       color: \(dim); margin-left: 0; font-style: italic; }
          hr { border: none; border-top: 1px solid \(border); margin: 2em 0; }
          img { max-width: 100%; }
          table { border-collapse: collapse; margin: 1em 0; }
          th, td { border: 1px solid \(border); padding: 4px 10px; }
          th { background: \(codeBackground); }
          @media print {
            body { background: #fff; color: #000; max-width: none; padding: 0; }
            h1, h2, h3, h4, h5, h6, a, em, code { color: #000; }
            @page { margin: 20mm; }
          }
        </style>
        </head>
        <body>
        \(bodyHTML)
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
