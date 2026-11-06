import Foundation

/// One row of the file sidebar: a folder or a writing file.
public struct FolderEntry: Equatable, Sendable {
    public let url: URL
    public let isFolder: Bool
    public var name: String { url.lastPathComponent }

    public init(url: URL, isFolder: Bool) {
        self.url = url
        self.isFolder = isFolder
    }
}

/// What the file sidebar shows for one folder: its sub-folders and the files a
/// writer opens as text. Hidden names, packages (an `.app`)
/// and `node_modules` are left out. Folders come first, then files, each in
/// Finder order (`2.md` before `10.md`).
public enum FolderListing {
    public static let fileExtensions: Set<String> = ["md", "markdown", "mdown", "txt"]
    private static let skippedFolders: Set<String> = ["node_modules"]

    public static func entries(in folder: URL, fileManager: FileManager = .default) -> [FolderEntry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var folders: [FolderEntry] = []
        var files: [FolderEntry] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let isFolder = values?.isDirectory ?? false
            if isFolder {
                if values?.isPackage == true || skippedFolders.contains(url.lastPathComponent) { continue }
                folders.append(FolderEntry(url: url, isFolder: true))
            } else if fileExtensions.contains(url.pathExtension.lowercased()) {
                files.append(FolderEntry(url: url, isFolder: false))
            }
        }
        let byName: (FolderEntry, FolderEntry) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return folders.sorted(by: byName) + files.sorted(by: byName)
    }
}
