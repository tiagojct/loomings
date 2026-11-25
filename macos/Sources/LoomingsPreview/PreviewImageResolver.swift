import AppKit
import Foundation

public enum PreviewImageResolver {
    public static func resolve(
        _ attributed: NSAttributedString,
        documentURL: URL?,
        allowImagePaths: Bool = true
    ) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: attributed)
        let full = NSRange(location: 0, length: copy.length)
        let baseURL = documentURL?.deletingLastPathComponent()

        copy.enumerateAttribute(.loomingsImageURL, in: full) { value, range, _ in
            guard let raw = value as? String,
                  !raw.isEmpty,
                  let existing = copy.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment,
                  case .image(let image) = PreviewImageLoader.load(raw, baseURL: baseURL, allowImagePaths: allowImagePaths) else {
                return
            }
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = existing.bounds
            copy.addAttribute(.attachment, value: attachment, range: range)
        }

        return copy
    }
}
