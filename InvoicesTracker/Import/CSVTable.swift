import Foundation

/// A CSV file read as RFC 4180 has it: the first record is the header, and every other record is a row.
///
/// - A field may be in double quotes. Inside quotes a comma and a line break are part of the field and two quotes are
///   one quote.
/// - A record ends with CRLF, LF or a lone CR (a line break inside quotes is part of the field, whichever it is).
/// - A byte order mark in front of the text is dropped.
/// - Lines with nothing on them are skipped. Every other record is kept as it is, with the number of fields it has:
///   whether that fits the header is for whoever reads the rows to judge. Spaces are not trimmed.
///
/// The text is read byte by byte, since a file of years of invoices has tens of thousands of fields.
nonisolated struct CSVTable: Sendable, Hashable {
    let header: [String]
    let rows: [[String]]

    /// The table in `text`.
    /// - Throws: `ImportError.emptyFile` when the text has no header, and `ImportError.damagedFile` when a quote is
    ///   never closed, when anything but a comma or a line end follows a closing quote, or when a quote is in the
    ///   middle of a field that did not start with one. A file like that cannot be told apart from one whose
    ///   columns would be read out of place, so it is not read in part.
    static func parse(_ text: String) throws -> CSVTable {
        var reader = Reader()
        try reader.read(Array(text.utf8))
        guard let header = reader.records.first else { throw ImportError.emptyFile }
        return CSVTable(header: header, rows: Array(reader.records.dropFirst()))
    }

    /// The state of reading: the records so far, the one being read and the field being read.
    private nonisolated struct Reader {
        private enum State {
            /// At the start of a field: nothing of it has been read.
            case fieldStart

            /// In a field that did not start with a quote.
            case plain

            /// In a field in quotes.
            case quoted

            /// After a quote in a field in quotes: the quote that ends the field, or the first of two that make one.
            case afterQuote
        }

        private static let quote = UInt8(ascii: "\"")
        private static let comma = UInt8(ascii: ",")
        private static let lineFeed = UInt8(ascii: "\n")
        private static let carriageReturn = UInt8(ascii: "\r")
        private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

        private(set) var records: [[String]] = []
        private var record: [String] = []
        private var field: [UInt8] = []
        private var state = State.fieldStart
        private var line = 1

        /// The line a field in quotes was opened on, for the error of a quote that is never closed.
        private var quoteLine = 1

        mutating func read(_ bytes: [UInt8]) throws {
            var index = bytes.starts(with: Self.byteOrderMark) ? Self.byteOrderMark.count : 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                switch state {
                case .fieldStart:
                    switch byte {
                    case Self.quote:
                        state = .quoted
                        quoteLine = line
                    case Self.comma:
                        endField()
                    case Self.lineFeed, Self.carriageReturn:
                        skipLineFeedAfterCarriageReturn(byte, in: bytes, at: &index)
                        // A line with nothing on it is not a record.
                        if !record.isEmpty {
                            endRecord()
                        }
                        line += 1
                    default:
                        field.append(byte)
                        state = .plain
                    }
                case .plain:
                    switch byte {
                    case Self.comma:
                        endField()
                    case Self.lineFeed, Self.carriageReturn:
                        skipLineFeedAfterCarriageReturn(byte, in: bytes, at: &index)
                        endRecord()
                        line += 1
                    case Self.quote:
                        throw ImportError.damagedFile(line: line)
                    default:
                        field.append(byte)
                    }
                case .quoted:
                    if byte == Self.quote {
                        state = .afterQuote
                    } else {
                        field.append(byte)
                        if byte == Self.lineFeed {
                            line += 1
                        }
                    }
                case .afterQuote:
                    switch byte {
                    case Self.quote:
                        field.append(Self.quote)
                        state = .quoted
                    case Self.comma:
                        endField()
                    case Self.lineFeed, Self.carriageReturn:
                        skipLineFeedAfterCarriageReturn(byte, in: bytes, at: &index)
                        endRecord()
                        line += 1
                    default:
                        throw ImportError.damagedFile(line: line)
                    }
                }
            }
            if state == .quoted {
                throw ImportError.damagedFile(line: quoteLine)
            }
            // The last record needs no line end.
            if state != .fieldStart || !record.isEmpty {
                endRecord()
            }
        }

        /// The line feed of a CRLF belongs to the carriage return before it: it is not a line end of its own.
        private func skipLineFeedAfterCarriageReturn(_ byte: UInt8, in bytes: [UInt8], at index: inout Int) {
            if byte == Self.carriageReturn, index < bytes.count, bytes[index] == Self.lineFeed {
                index += 1
            }
        }

        private mutating func endField() {
            record.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
            state = .fieldStart
        }

        private mutating func endRecord() {
            endField()
            records.append(record)
            record = []
        }
    }
}
