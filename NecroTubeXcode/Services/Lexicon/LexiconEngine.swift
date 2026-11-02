import Foundation

actor LexiconEngine: LexiconServicing {
    enum LexiconError: LocalizedError {
        case resourceMissing(AppLanguage)

        var errorDescription: String? {
            switch self {
            case .resourceMissing(let language):
                String(format: String(localized: "Lexicon not found for language %@."), language.rawValue)
            }
        }
    }

    private struct Pools {
        let words: [String]
        let phrases: [String]
        let contact: [String]
    }

    private let bundle = Bundle.main
    private let fileManager = FileManager()
    private var pools: [AppLanguage: Pools] = [:]
    private var recent: [String] = []

    func load(language: AppLanguage) throws {
        guard pools[language] == nil else { return }
        let resourceName = language == .arabic ? "words_ar" : language.rawValue
        guard let url = bundle.url(forResource: resourceName, withExtension: "txt") else {
            throw LexiconError.resourceMissing(language)
        }

        let bundled = try String(contentsOf: url, encoding: .utf8)
            .components(separatedBy: .newlines)
        let allEntries = (bundled + userWords(for: language))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: language.locale) }
            .filter { !$0.isEmpty }
        let unique = Array(NSOrderedSet(array: allEntries)) as? [String] ?? allEntries
        let phrases = unique.filter { $0.contains(where: \.isWhitespace) }
        let words = unique.filter { !$0.contains(where: \.isWhitespace) }

        pools[language] = Pools(
            words: words.isEmpty ? [fallbackWord(for: language)] : words,
            phrases: phrases.isEmpty ? [fallbackPhrase(for: language)] : phrases,
            contact: contactPool(for: language)
        )
    }

    func loadAll() throws {
        for language in AppLanguage.allCases {
            try load(language: language)
        }
    }

    func addUserWords(_ input: String, language: AppLanguage) throws {
        let separators = CharacterSet(charactersIn: ",\n\r")
        let candidates = input.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: language.locale) }
            .filter { !$0.isEmpty }

        let url = try userLexiconURL(for: language)
        let existing = userWords(for: language)
        var knownEntries = Set(existing.map { $0.uppercased(with: language.locale) })
        let additions = candidates.filter { knownEntries.insert($0).inserted }.prefix(100)
        guard !additions.isEmpty else { return }

        let merged = existing + additions
        try (merged.joined(separator: "\n") + "\n")
            .write(to: url, atomically: true, encoding: .utf8)
        pools[language] = nil
        try load(language: language)
    }

    func userWords(for language: AppLanguage) -> [String] {
        guard let url = try? userLexiconURL(for: language),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    func relevantResponse(to input: String, language: AppLanguage) -> String? {
        let normalized = input.lowercased(with: language.locale)
        for response in contextualResponses(for: language) {
            if response.keywords.contains(where: normalized.contains) {
                return response.answers.randomElement()
            }
        }

        guard let contact = pools[language]?.contact else { return nil }
        let categories: [(keywords: [String], matches: [String])] = [
            (["nom", "name", "nombre", "nome", "nume", "名前", "ឈ្មោះ", "名字", "اسم"],
             ["NOM", "NAME", "NOMBRE", "NOME", "NUME", "名前", "ឈ្មោះ", "名字", "اسم", "SPIRIT", "ESPRIT", "روح"]),
            (["où", "where", "dónde", "onde", "wo", "dove", "unde", "どこ", "ឯណា", "哪里", "أين"],
             ["ICI", "HERE", "AQUÍ", "AQUI", "HIER", "QUI", "AICI", "ここ", "នៅទីនេះ", "这里", "هنا", "NEAR", "PROCHE"]),
            (["peur", "afraid", "miedo", "medo", "angst", "paura", "frică", "怖い", "ខ្លាច", "害怕", "خائف"],
             ["AIDE", "HELP", "AYUDA", "AJUDA", "HILFE", "AIUTO", "AJUTOR", "助けて", "ជួយ", "救命", "ساعدني", "DANGER"])
        ]

        guard let category = categories.first(where: { item in
            item.keywords.contains(where: normalized.contains)
        }) else { return nil }

        return contact.filter { value in category.matches.contains(where: value.contains) }.randomElement()
            ?? contact.randomElement()
    }

    func nextOutput(for sample: SensorFusionSample, language: AppLanguage) async -> String? {
        do {
            try load(language: language)
        } catch {
            return nil
        }
        guard let pool = pools[language] else { return nil }

        // Match Android Lexicon.next(): discretize the three real magnetic
        // axes in 2 µT steps, preserving the spatial memory calculation.
        let xStep = kotlinRoundToInt(sample.magneticX / 2)
        let yStep = kotlinRoundToInt(sample.magneticY / 2)
        let zStep = kotlinRoundToInt(sample.magneticZ / 2)
        let spatialIndex = abs(Int64(xStep) * 31 + Int64(yStep) * 17 + Int64(zStep))
        let candidates = sample.totalEnergy > 15 && !pool.phrases.isEmpty ? pool.phrases : pool.words
        guard !candidates.isEmpty else { return nil }

        let start = Int(spatialIndex % Int64(candidates.count))
        var selected = candidates[start].uppercased(with: language.locale)
        var attempts = 0
        while recent.contains(selected), attempts < 15 {
            attempts += 1
            selected = candidates[(start + attempts) % candidates.count]
                .uppercased(with: language.locale)
        }
        recent.insert(selected, at: 0)
        recent = Array(recent.prefix(20))
        return selected
    }

    private func kotlinRoundToInt(_ value: Double) -> Int {
        // Kotlin roundToInt() resolves exact ties toward positive infinity.
        Int(floor(value + 0.5))
    }

    func counts() throws -> [AppLanguage: Int] {
        try loadAll()
        return pools.mapValues { $0.words.count + $0.phrases.count }
    }

    private func userLexiconURL(for language: AppLanguage) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Lexicons", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("user_\(language.rawValue).txt")
    }

    private func fallbackWord(for language: AppLanguage) -> String {
        language == .english ? "PRESENCE" : "PRÉSENCE"
    }

    private func fallbackPhrase(for language: AppLanguage) -> String {
        language == .english ? "I AM HERE" : "JE SUIS ICI"
    }

    private func contactPool(for language: AppLanguage) -> [String] {
        switch language {
        case .french: ["OUI", "NON", "ICI", "DERRIÈRE TOI", "AIDE", "ESPRIT", "MORT", "FROID", "REGARDE", "PARLE", "DANGER", "TON NOM", "JE SUIS LÀ", "ÉCOUTE", "PROCHE"]
        case .english: ["YES", "NO", "HERE", "BEHIND YOU", "HELP", "SPIRIT", "DEATH", "COLD", "LOOK", "SPEAK", "DANGER", "YOUR NAME", "I AM HERE", "LISTEN", "NEAR"]
        case .spanish: ["SÍ", "NO", "AQUÍ", "DETRÁS DE TI", "AYUDA", "ESPÍRITU", "MUERTE", "FRÍO", "MIRA", "HABLA", "PELIGRO", "TU NOMBRE", "ESTOY AQUÍ", "ESCUCHA", "CERCA"]
        case .portuguese: ["SIM", "NÃO", "AQUI", "ATRÁS DE VOCÊ", "AJUDA", "ESPÍRITO", "MORTE", "FRIO", "OLHE", "FALE", "PERIGO", "SEU NOME", "ESTOU AQUI", "OUÇA", "PERTO"]
        case .romanian: ["DA", "NU", "AICI", "ÎN SPATELE TĂU", "AJUTOR", "SPIRIT", "MOARTE", "FRIG", "PRIVEȘTE", "VORBEȘTE", "PERICOL", "NUMELE TĂU", "SUNT AICI", "ASCULTĂ", "APROAPE"]
        case .german: ["JA", "NEIN", "HIER", "HINTER DIR", "HILFE", "GEIST", "TOD", "KALT", "SCHAU", "SPRICH", "GEFAHR", "DEIN NAME", "ICH BIN HIER", "HÖR ZU", "NAH"]
        case .italian: ["SÌ", "NO", "QUI", "DIETRO DI TE", "AIUTO", "SPIRITO", "MORTE", "FREDDO", "GUARDA", "PARLA", "PERICOLO", "IL TUO NOME", "SONO QUI", "ASCOLTA", "VICINO"]
        case .japanese: ["はい", "いいえ", "ここ", "あなたの後ろ", "助けて", "霊", "死", "寒い", "見て", "話して", "危険", "あなたの名前", "私はここにいる", "聞いて", "近い"]
        case .khmer: ["បាទ", "ទេ", "នៅទីនេះ", "នៅពីក្រោយអ្នក", "ជួយ", "ខ្មោច", "សេចក្តីស្លាប់", "ត្រជាក់", "មើល", "និយាយ", "គ្រោះថ្នាក់", "ឈ្មោះរបស់អ្នក", "ខ្ញុំនៅទីនេះ", "ស្តាប់", "ជិត"]
        case .chinese: ["是", "不是", "这里", "在你身后", "救命", "灵魂", "死亡", "冷", "看", "说话", "危险", "你的名字", "我在这里", "听", "靠近"]
        case .arabic: ["نعم", "لا", "هنا", "خلفك", "ساعدني", "روح", "موت", "برد", "انظر", "تكلم", "خطر", "اسمي", "أنا هنا", "اسمع", "قريب"]
        }
    }

    private func contextualResponses(for language: AppLanguage) -> [(keywords: [String], answers: [String])] {
        switch language {
        case .french:
            [
                (["nom", "appelle", "qui es", "qui êtes"], ["JE NE SAIS PLUS", "MON NOM EST OUBLIÉ", "APPELLE-MOI", "JE SUIS UN ESPRIT"]),
                (["où", "endroit", "pièce", "près"], ["JE SUIS ICI", "PRÈS DE TOI", "DERRIÈRE TOI", "DANS CETTE PIÈCE"]),
                (["comment vas", "te sens", "peur", "mal"], ["J’AI FROID", "J’AI PEUR", "JE SUIS PERDU", "AIDE-MOI"])
            ]
        case .english:
            [
                (["name", "who are you"], ["I FORGOT MY NAME", "CALL ME", "I AM A SPIRIT"]),
                (["where", "place", "room", "near"], ["I AM HERE", "NEAR YOU", "BEHIND YOU", "IN THIS ROOM"]),
                (["how are", "feel", "afraid", "hurt"], ["I AM COLD", "I AM AFRAID", "I AM LOST", "HELP ME"])
            ]
        default: []
        }
    }
}

extension AppLanguage {
    nonisolated var locale: Locale {
        Locale(identifier: rawValue)
    }

    nonisolated var displayName: String {
        Locale.current.localizedString(forLanguageCode: rawValue) ?? rawValue.uppercased()
    }
}
