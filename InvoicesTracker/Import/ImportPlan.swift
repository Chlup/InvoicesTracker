import Foundation

/// What an import is made of: the rows of its CSV files and the invoices of its ISDOC files, each in the order of
/// their files.
nonisolated struct ImportSources: Sendable, Hashable {
    var rows: [FakturoidRow]
    var isdocs: [IsdocInvoice]
}

/// An invoice of an import that cannot be added, and why: "číslo už používá faktura v jiné měně".
nonisolated struct ImportNotAddedItem: Sendable, Hashable {
    /// The number of the invoice as its file has it, or "(bez čísla)".
    let number: String
    let reason: String
}

/// What an import is going to do, worked out from its rows and ISDOC invoices and from the invoices and clients that
/// are there. Applying it is a matter of saving what it holds.
nonisolated struct ImportPlan: Sendable, Hashable {
    /// Clients the files have and the app has not, as they are going to be stored: with id 0.
    var newClients: [Client] = []

    /// Clients that are there, with the fields that were empty filled.
    var clientUpdates: [Client] = []

    /// Invoices to add, in the order of the files. Their `clientID` is that of the client that is there already; for
    /// an invoice of a new client it is nil, and `newClientIndexByDigits` says which one.
    var inserts: [Invoice] = []

    /// Invoices to replace, imported earlier or made in the app, each with the `id` of the invoice it replaces. An
    /// invoice that is only held for review because the files of the import for it differ is one of them, with all it
    /// holds as it was.
    var updates: [Invoice] = []

    /// A line for each invoice that cannot be added: the number is taken by an invoice in another currency or by
    /// another invoice of the import, the invoice came under another number, another invoice already has a number
    /// without a digit, or the file has no day of issue, no currency code, no rate or a VAT the app has no mode for:
    /// "20261005 — číslo už používá faktura v jiné měně — nepřidáno". `notAdded` has the same, as number and reason.
    var conflicts: [String] = []

    /// Invoices that are there and are cancelled in Fakturoid now: the invoices as they are, held for review.
    var flaggedCancelled: [Invoice] = []

    /// A line for each invoice that is added or updated in review and for each invoice flagged as cancelled ("20261003
    /// — záporná částka"): the invoices that do not count until the person resolves them.
    var reviewItems: [String] = []

    /// A line for each proforma invoice, for each ISDOC document that is no invoice and for each cancelled invoice
    /// that is not in the app: "Z20261001 — zálohová faktura". A document, by the digits of its number, its currency
    /// and whether it is a proforma invoice, has one line however many of its files are skipped, and none when another
    /// outcome counts it.
    var skipped: [String] = []

    /// For the invoices of `inserts` and `updates` whose client is new, by the digits of their number: the index of
    /// that client in `newClients`.
    var newClientIndexByDigits: [String: Int] = [:]

    /// The numbers of the invoices to add ("Nové"), in the order of the files.
    var newNumbers: [String] = []

    /// The numbers of the invoices that are there and that the import overwrites ("Přepíší se"): those of `updates`
    /// and of `flaggedCancelled`, in the order of the files.
    var overwrittenNumbers: [String] = []

    /// The numbers of the invoices that are there as the files have them ("Beze změny").
    var unchangedNumbers: [String] = []

    /// The numbers of the lines of `skipped` ("Přeskočí se").
    var skippedNumbers: [String] = []

    /// The invoices that cannot be added ("Nepřidají se"), with why: the lines of `conflicts` as number and reason.
    var notAdded: [ImportNotAddedItem] = []

    /// A line for each note that does not stop an invoice from counting ("Upozornění"), such as a CSV row whose amount
    /// disagrees with the lines of the ISDOC file ("20260902 — částka v CSV nesouhlasí s položkami z ISDOC —
    /// ponechány položky") or a country that is neither a code nor a name the import knows ("země „Švýcarsko“ — není
    /// kód země, ponecháno jak je").
    var notes: [String] = []

    /// How many invoices the import saves: those it adds, those it updates and those it flags as cancelled.
    var invoiceCount: Int {
        inserts.count + updates.count + flaggedCancelled.count
    }
}
