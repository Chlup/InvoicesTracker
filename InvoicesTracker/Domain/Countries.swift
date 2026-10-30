import Foundation

/// The countries of the app, by their ISO 3166-1 alpha-2 codes: the list the client form offers and the names that the
/// form, Odběratelé, Faktury, the search and the printed invoice give them. It is the one place that names a country.
/// (The spellings the import of Fakturoid maps to a code, which go the other way, are `ImportPlanner`'s.)
nonisolated enum Countries {
    /// The name of a country, from its ISO 3166-1 alpha-2 code in any case, in `language`. The countries a freelancer
    /// is likely to invoice have their names written out here: `Czech Republic` and `United States of America` in
    /// English, `Česko` and `Spojené státy americké` in Czech, and so on. Any other code takes the name that the system
    /// has for the language. Text that is not a code the system knows, such as the country of an imported client typed
    /// as `Brazil`, and the code `ZZ`, for which the system has only "Unknown Region", comes back as it was typed,
    /// without the white space around it. No text gives no name.
    static func name(_ code: String, language: InvoiceLanguage) -> String {
        let typed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return "" }
        let code = typed.uppercased()
        if let name = writtenOut[code] {
            return language == .cs ? name.czech : name.english
        }
        guard code != unknownRegion,
            let name = Locale(identifier: language.rawValue).localizedString(forRegionCode: code)
        else {
            return typed
        }
        return name
    }

    /// The code of every country of ISO 3166-1, in the order of their names in Czech, where "Č" comes after "C" and
    /// "Ch" after "H". (The system's own list also has regions that are no country, such as the European Union.)
    static let all: [String] = {
        let czech = Locale(identifier: "cs")
        let named = isoCodes.map { (code: $0, czechName: name($0, language: .cs)) }
        return named.sorted { first, second in
            switch first.czechName.compare(second.czechName, locale: czech) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: first.code < second.code
            }
        }.map(\.code)
    }()

    /// The code that means "no region" and that the system names "Unknown Region".
    private static let unknownRegion = "ZZ"

    private nonisolated struct CountryName {
        var english: String
        var czech: String
    }

    /// The countries of the EU and the EEA, the United Kingdom, Switzerland, the United States, Canada and Australia,
    /// whose names are written here rather than taken from the system: it calls the Czech Republic "Czechia" and the
    /// United States "United States", which is not what an invoice prints.
    private static let writtenOut: [String: CountryName] = [
        "AT": CountryName(english: "Austria", czech: "Rakousko"),
        "AU": CountryName(english: "Australia", czech: "Austrálie"),
        "BE": CountryName(english: "Belgium", czech: "Belgie"),
        "BG": CountryName(english: "Bulgaria", czech: "Bulharsko"),
        "CA": CountryName(english: "Canada", czech: "Kanada"),
        "CH": CountryName(english: "Switzerland", czech: "Švýcarsko"),
        "CY": CountryName(english: "Cyprus", czech: "Kypr"),
        "CZ": CountryName(english: "Czech Republic", czech: "Česko"),
        "DE": CountryName(english: "Germany", czech: "Německo"),
        "DK": CountryName(english: "Denmark", czech: "Dánsko"),
        "EE": CountryName(english: "Estonia", czech: "Estonsko"),
        "ES": CountryName(english: "Spain", czech: "Španělsko"),
        "FI": CountryName(english: "Finland", czech: "Finsko"),
        "FR": CountryName(english: "France", czech: "Francie"),
        "GB": CountryName(english: "United Kingdom", czech: "Spojené království"),
        "GR": CountryName(english: "Greece", czech: "Řecko"),
        "HR": CountryName(english: "Croatia", czech: "Chorvatsko"),
        "HU": CountryName(english: "Hungary", czech: "Maďarsko"),
        "IE": CountryName(english: "Ireland", czech: "Irsko"),
        "IS": CountryName(english: "Iceland", czech: "Island"),
        "IT": CountryName(english: "Italy", czech: "Itálie"),
        "LI": CountryName(english: "Liechtenstein", czech: "Lichtenštejnsko"),
        "LT": CountryName(english: "Lithuania", czech: "Litva"),
        "LU": CountryName(english: "Luxembourg", czech: "Lucembursko"),
        "LV": CountryName(english: "Latvia", czech: "Lotyšsko"),
        "MT": CountryName(english: "Malta", czech: "Malta"),
        "NL": CountryName(english: "Netherlands", czech: "Nizozemsko"),
        "NO": CountryName(english: "Norway", czech: "Norsko"),
        "PL": CountryName(english: "Poland", czech: "Polsko"),
        "PT": CountryName(english: "Portugal", czech: "Portugalsko"),
        "RO": CountryName(english: "Romania", czech: "Rumunsko"),
        "SE": CountryName(english: "Sweden", czech: "Švédsko"),
        "SI": CountryName(english: "Slovenia", czech: "Slovinsko"),
        "SK": CountryName(english: "Slovakia", czech: "Slovensko"),
        "US": CountryName(english: "United States of America", czech: "Spojené státy americké"),
    ]

    /// The 249 codes of ISO 3166-1 alpha-2. The system's list of regions has more (the numeric codes of the continents,
    /// the European Union, Ascension Island and so on), none of which a client lives in.
    private static let isoCodes: [String] = """
        AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ \
        CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO \
        FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE \
        JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO \
        MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW \
        PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM \
        TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW
        """.split(separator: " ").map(String.init)
}
