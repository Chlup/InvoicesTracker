import Foundation
import Testing
@testable import InvoicesTracker

/// Reading CSV text as RFC 4180 has it: quoted fields, doubled quotes, commas and line breaks inside quotes, and the
/// line endings and the byte order mark that files from other programs have.
struct CSVTableTests {
    @Test func theFirstRecordIsTheHeaderAndTheOthersAreRows() throws {
        let table = try CSVTable.parse("a,b,c\n1,2,3\n4,5,6\n")

        #expect(table.header == ["a", "b", "c"])
        #expect(table.rows == [["1", "2", "3"], ["4", "5", "6"]])
    }

    @Test func aCommaInQuotesIsPartOfTheField() throws {
        let table = try CSVTable.parse("name,city\n\"Beta Labs, Inc.\",\"Austin, TX\"\n")

        #expect(table.rows == [["Beta Labs, Inc.", "Austin, TX"]])
    }

    @Test func aDoubledQuoteInQuotesIsOneQuote() throws {
        let table = try CSVTable.parse("subject\n\"Konzultace \"\"říjen\"\", 2. část\"\n\"\"\"\"\n")

        #expect(table.rows == [["Konzultace \"říjen\", 2. část"], ["\""]])
    }

    @Test func aLineBreakInQuotesIsPartOfTheField() throws {
        let table = try CSVTable.parse("note,amount\n\"first line\nsecond line\",5\n")

        #expect(table.rows == [["first line\nsecond line", "5"]])
    }

    @Test func aCRLFLineEndingEndsARowAndOneInQuotesStaysInTheField() throws {
        let table = try CSVTable.parse("a,b\r\n1,2\r\n\"x\r\ny\",4\r\n")

        #expect(table.header == ["a", "b"])
        #expect(table.rows == [["1", "2"], ["x\r\ny", "4"]])
    }

    @Test func aLoneCarriageReturnEndsARowToo() throws {
        let table = try CSVTable.parse("a,b\r1,2\r3,4\r")

        #expect(table.rows == [["1", "2"], ["3", "4"]])
    }

    @Test func aByteOrderMarkInFrontOfTheTextIsDropped() throws {
        let table = try CSVTable.parse("\u{FEFF}Number,Issued on\n20260901,2026-09-30\n")

        #expect(table.header == ["Number", "Issued on"])
        #expect(table.rows == [["20260901", "2026-09-30"]])
    }

    @Test func aByteOrderMarkThatIsReadFromBytesIsDropped() throws {
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("Number,Issued on\n1,2\n".utf8)
        let text = try #require(String(data: bytes, encoding: .utf8))

        #expect(try CSVTable.parse(text).header == ["Number", "Issued on"])
    }

    @Test func theLastRowNeedsNoLineEnding() throws {
        #expect(try CSVTable.parse("a,b\n1,2").rows == [["1", "2"]])
        #expect(try CSVTable.parse("a,b\n1,\"2\"").rows == [["1", "2"]])
    }

    @Test func emptyFieldsAreKept() throws {
        let table = try CSVTable.parse("a,b,c\n,,\n1,,3\n,2,\n")

        #expect(table.rows == [["", "", ""], ["1", "", "3"], ["", "2", ""]])
    }

    @Test func spacesAreNotTrimmed() throws {
        let table = try CSVTable.parse(" a , b \n 1 ,\" 2 \"\n")

        #expect(table.header == [" a ", " b "])
        #expect(table.rows == [[" 1 ", " 2 "]])
    }

    @Test func blankLinesAreSkipped() throws {
        let table = try CSVTable.parse("\n\na,b\n\n1,2\n\n\n3,4\n\n")

        #expect(table.header == ["a", "b"])
        #expect(table.rows == [["1", "2"], ["3", "4"]])
    }

    @Test func aRowOfOnlyEmptyFieldsIsKeptWhenItHasSeveralFields() throws {
        #expect(try CSVTable.parse("a,b\n,\n").rows == [["", ""]])
    }

    @Test func aHeaderWithoutRowsIsAnEmptyTable() throws {
        let table = try CSVTable.parse("a,b\n")

        #expect(table.header == ["a", "b"])
        #expect(table.rows.isEmpty)
    }

    @Test func rowsKeepTheirOwnNumberOfFields() throws {
        // The table does not judge the shape of an export: that is for the reader of the rows.
        let table = try CSVTable.parse("a,b,c\n1,2\n1,2,3,4\n")

        #expect(table.rows == [["1", "2"], ["1", "2", "3", "4"]])
    }

    @Test(arguments: ["", "\n", "\r\n\r\n", "\u{FEFF}", "\u{FEFF}\n"])
    func aTextWithoutAHeaderIsAnEmptyFile(text: String) {
        #expect(throws: ImportError.emptyFile) { try CSVTable.parse(text) }
    }

    @Test func aQuoteThatIsNeverClosedDamagesTheFile() {
        #expect(throws: ImportError.damagedFile(line: 2)) { try CSVTable.parse("a,b\n1,\"2\n3,4\n") }
        #expect(throws: ImportError.damagedFile(line: 1)) { try CSVTable.parse("\"a,b\n") }
    }

    @Test func textAfterAClosingQuoteDamagesTheFile() {
        #expect(throws: ImportError.damagedFile(line: 2)) { try CSVTable.parse("a,b\n\"x\"y,2\n") }
    }

    @Test func aQuoteInTheMiddleOfAnUnquotedFieldDamagesTheFile() {
        #expect(throws: ImportError.damagedFile(line: 3)) { try CSVTable.parse("a,b\n1,2\n5\" pipe,2\n") }
    }

    @Test func theLineOfAProblemCountsTheLineBreaksInQuotedFields() {
        // The quoted field of line 2 spans lines 2 to 4, and the stray quote is on line 5.
        #expect(throws: ImportError.damagedFile(line: 5)) {
            try CSVTable.parse("a,b\n\"x\ny\nz\",1\n5\"6,2\n")
        }
    }

    @Test func aLargeTableIsReadQuickly() throws {
        var text = "Id,Name,Note\n"
        for i in 0..<20_000 {
            text += "\(i),\"Name, \(i)\",\"a \"\"quoted\"\" word\"\n"
        }
        let start = ContinuousClock.now

        let table = try CSVTable.parse(text)

        #expect(table.rows.count == 20_000)
        #expect(table.rows[19_999] == ["19999", "Name, 19999", "a \"quoted\" word"])
        #expect(ContinuousClock.now - start < .seconds(2))
    }
}
