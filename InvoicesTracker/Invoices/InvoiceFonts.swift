import CoreText
import Foundation

/// The three faces of IBM Plex Sans (SIL Open Font License 1.1) that an invoice is set in, and their registration for
/// the app. Only the invoice, in its preview and in its PDF, uses them: the rest of the app stays in the system font.
///
/// The font files are IBM's own web fonts, as the official package ships them, bundled unchanged: CoreText reads them
/// as they are. A PDF embeds the glyphs it uses, so the page looks the same on a Mac that does not have the font.
nonisolated enum InvoiceFonts {
    /// The PostScript names of the faces, as the font files carry them (Plex abbreviates the weight of Medium).
    static let regular = "IBMPlexSans"
    static let medium = "IBMPlexSans-Medm"
    static let bold = "IBMPlexSans-Bold"

    private static let fileNames = ["IBMPlexSans-Regular", "IBMPlexSans-Medium", "IBMPlexSans-Bold"]
    private static let fileExtension = "woff"

    /// Makes the three faces available to the app, for the process only: nothing is installed on the Mac. The faces are
    /// registered once, whatever the number of calls and the thread they come from, so calling it twice is harmless.
    /// A face that cannot be registered is logged, and text set in it falls back to the system font.
    static func register() {
        _ = registration
    }

    private static let registration: Void = registerFaces()

    private static func registerFaces() {
        let urls = fileNames.compactMap { Bundle.main.url(forResource: $0, withExtension: fileExtension) }
        if urls.count != fileNames.count {
            AppModel.log("Finding the invoice fonts", failedWith: FontError.missingFile)
        }
        for url in urls {
            var error: Unmanaged<CFError>?
            guard !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else { continue }
            if let failure = error?.takeRetainedValue(),
                CFErrorGetCode(failure) != CTFontManagerError.alreadyRegistered.rawValue
            {
                AppModel.log("Registering the invoice fonts", failedWith: failure)
            }
        }
    }

    private nonisolated enum FontError: Error {
        case missingFile
    }
}
