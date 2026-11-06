import Foundation
@testable import InvoicesTracker

extension ImportModel {
    /// Collects `urls` and imports them at once, as a person does who adds the files and presses "Importovat" when the
    /// preview is shown. For the tests that are about what an import leaves behind and not about the two steps.
    func importAll(_ urls: [URL]) async {
        await addFiles(urls)
        await importCollected()
    }
}
