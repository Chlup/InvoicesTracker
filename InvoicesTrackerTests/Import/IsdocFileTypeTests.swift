import Foundation
import Testing
import UniformTypeIdentifiers
@testable import InvoicesTracker

/// The kinds of file the Import screen takes. An ISDOC invoice is a file the system does not know, so the app declares
/// it in its Info.plist: an XML file with the extension `.isdoc`. The tests are hosted in the app, so they read the
/// real app's bundle.
@MainActor
struct IsdocFileTypeTests {
    /// The app declares the ISDOC type as an imported type that is XML, under its own identifier and the extension
    /// `isdoc`, and the app's `UTType.isdoc` is that type.
    @Test func theAppDeclaresTheIsdocTypeAsXmlWithItsExtension() throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let declarations = try #require(info["UTImportedTypeDeclarations"] as? [[String: Any]])
        let declaration = try #require(
            declarations.first { $0["UTTypeIdentifier"] as? String == "info.chlup.InvoicesTracker.isdoc" })
        let conformances = declaration["UTTypeConformsTo"] as? [String] ?? []
        #expect(conformances.contains("public.xml"))
        let tags = declaration["UTTypeTagSpecification"] as? [String: Any] ?? [:]
        #expect(tags["public.filename-extension"] as? [String] == ["isdoc"])

        // The system keeps the identifiers of types in lowercase.
        #expect(UTType.isdoc.identifier == "info.chlup.invoicestracker.isdoc")
        #expect(UTType.isdoc.conforms(to: .xml))
    }

    /// The system knows a file that ends in `.isdoc` as the declared type, so the panel offers it among the XML files.
    @Test func aFileThatEndsInIsdocIsOfTheDeclaredType() throws {
        let type = try #require(UTType(filenameExtension: "isdoc"))
        #expect(type.conforms(to: .xml), "\(type.identifier) is no XML")
    }

    /// The panel of the Import screen offers the CSV exports, the ISDOC and XML invoices, and folders of them.
    @Test func thePanelOffersCsvIsdocXmlAndFolders() {
        #expect(ImportScreen.acceptedTypes == [.commaSeparatedText, .isdoc, .xml, .folder])
    }
}
