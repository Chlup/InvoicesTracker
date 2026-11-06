import Foundation

/// What a file of an import is, going by its name.
nonisolated enum ImportFileKind: Sendable, Hashable {
    /// An export of invoices from Fakturoid, in a `.csv` file.
    case csv

    /// An ISDOC invoice, in an `.isdoc` or `.xml` file.
    case isdoc

    /// The kind of the file called `fileName`, whatever the case of its extension, or nil for another file.
    static func of(fileName: String) -> ImportFileKind? {
        switch (fileName as NSString).pathExtension.lowercased() {
        case "csv": .csv
        case "isdoc", "xml": .isdoc
        default: nil
        }
    }
}

/// A file the person chose for an import, read: its rows, its invoice, or why it cannot be used.
nonisolated struct ImportFile: Sendable, Hashable, Identifiable {
    /// What reading the file gave.
    enum Content: Sendable, Hashable {
        /// The rows of a CSV export.
        case rows([FakturoidRow])

        /// The invoice of an ISDOC file.
        case invoice(IsdocInvoice)

        /// The file cannot be used, and why.
        case failed(ImportError)
    }

    /// The name of the file, which tells it from the others of an import.
    var id: String { name }

    /// The name of the file, with its extension.
    let name: String

    /// The size of the file in bytes, or nil when it cannot be read.
    let size: Int?

    /// What the file is by its name, or nil for a file that is neither CSV nor ISDOC.
    let kind: ImportFileKind?

    /// What reading the file gave.
    let content: Content

    /// Reads the files and folders in `urls` one by one, away from the main actor.
    ///
    /// A folder stands for its `.csv`, `.isdoc` and `.xml` files, sorted by name; its subfolders and other files are
    /// left out. Another file chosen on its own is a failed file (`ImportError.unsupportedFile`). A file that cannot
    /// be read fails alone and the others are read. The security-scoped access of a chosen URL covers the files of a
    /// folder.
    @concurrent
    static func read(_ urls: [URL]) async -> [ImportFile] {
        var files: [ImportFile] = []
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if isFolder(url) {
                for child in filesOfFolder(url) {
                    files.append(readFile(child))
                }
            } else {
                files.append(readFile(url))
            }
        }
        return files
    }

    /// Whether `url` is a folder.
    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// The CSV, ISDOC and XML files directly in `folder`, sorted by name.
    private static func filesOfFolder(_ folder: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return children
            .filter { ImportFileKind.of(fileName: $0.lastPathComponent) != nil && !isFolder($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// The file at `url` read as what its name says it is.
    private static func readFile(_ url: URL) -> ImportFile {
        let name = url.lastPathComponent
        let kind = ImportFileKind.of(fileName: name)
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let content: Content
        switch kind {
        case nil:
            content = .failed(.unsupportedFile)
        case .csv?:
            content = readCSV(url)
        case .isdoc?:
            content = readIsdoc(url)
        }
        return ImportFile(name: name, size: size, kind: kind, content: content)
    }

    /// The rows of the CSV export at `url`, or why it cannot be read.
    private static func readCSV(_ url: URL) -> Content {
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else {
            return .failed(.unreadableFile)
        }
        do {
            return .rows(try FakturoidRow.rows(from: CSVTable.parse(text)))
        } catch let error as ImportError {
            return .failed(error)
        } catch {
            return .failed(.unreadableFile)
        }
    }

    /// The invoice of the ISDOC file at `url`, or why it cannot be read.
    private static func readIsdoc(_ url: URL) -> Content {
        guard let data = try? Data(contentsOf: url) else { return .failed(.unreadableFile) }
        do {
            return .invoice(try IsdocReader.read(data))
        } catch {
            return .failed(error)
        }
    }
}

nonisolated extension [ImportFile] {
    /// The rows and invoices of the files that did not fail, in the order of the files.
    var sources: ImportSources {
        var rows: [FakturoidRow] = []
        var isdocs: [IsdocInvoice] = []
        for file in self {
            switch file.content {
            case .rows(let fileRows): rows += fileRows
            case .invoice(let invoice): isdocs.append(invoice)
            case .failed: break
            }
        }
        return ImportSources(rows: rows, isdocs: isdocs)
    }
}
