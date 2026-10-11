import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var history: SessionHistoryStore
    let lexicon: LexiconEngine

    @State private var showsAddWords = false
    @State private var showsWords = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Settings")
                        .font(.system(size: 22, design: .monospaced))
                        .foregroundStyle(NecroTheme.accent)
                    LanguageSection(
                        title: "APP LANGUAGE",
                        selection: appLanguageBinding
                    )
                    Divider()
                    LanguageSection(
                        title: "LEXICON LANGUAGE",
                        selection: lexiconLanguageBinding
                    )
                    Divider()
                    SettingsActionSection(
                        onViewWords: { showsWords = true },
                        onAddWords: { showsAddWords = true },
                        onHistory: {}
                    )
                    NavigationLink {
                        SessionHistoryView(store: history)
                    } label: {
                        SettingsWideButton(title: "VIEW SESSION HISTORY", color: NecroTheme.accent)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showsAddWords) {
            AddWordsView(lexicon: lexicon, language: selectedLexiconLanguage)
                .presentationBackground(.black)
        }
        .sheet(isPresented: $showsWords) {
            UserWordsView(lexicon: lexicon, language: selectedLexiconLanguage)
                .presentationBackground(.black)
        }
    }

    private var selectedLexiconLanguage: AppLanguage {
        appState.lexiconLanguage
    }

    private var appLanguageBinding: Binding<String> {
        Binding(
            get: { appState.appLanguage.rawValue },
            set: { appState.appLanguage = AppLanguage(rawValue: $0) ?? .english }
        )
    }

    private var lexiconLanguageBinding: Binding<String> {
        Binding(
            get: { appState.lexiconLanguage.rawValue },
            set: { appState.lexiconLanguage = AppLanguage(rawValue: $0) ?? .english }
        )
    }
}

private struct LanguageSection: View {
    let title: LocalizedStringKey
    @Binding var selection: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 12) {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        selection = language.rawValue
                    } label: {
                        Text(language.nativeName)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .foregroundStyle(.white)
                    .background(
                        selection == language.rawValue ? Color(red: 0.36, green: 0.33, blue: 0.45) : .clear,
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(NecroTheme.border) }
                }
            }
        }
    }
}

private struct SettingsActionSection: View {
    let onViewWords: () -> Void
    let onAddWords: () -> Void
    let onHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("CUSTOM LEXICON")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            HStack {
                Button(action: onViewWords) {
                    SettingsWideButton(title: "VIEW MY WORDS", color: NecroTheme.accent)
                }
                Button(action: onAddWords) {
                    SettingsWideButton(title: "ADD WORDS", color: NecroTheme.gold)
                }
            }
        }
    }
}

struct SettingsWideButton: View {
    let title: String
    let color: Color

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(.callout.monospaced().weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(NecroTheme.raisedPanel, in: Capsule())
    }
}

private struct AddWordsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let lexicon: LexiconEngine
    let language: AppLanguage
    @State private var input = ""
    @State private var status: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add up to 100 words or phrases separated by commas or line breaks.")
                    .foregroundStyle(.secondary)
                TextEditor(text: $input)
                    .font(.body.monospaced())
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(NecroTheme.raisedPanel, in: RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 180)
                Button("ADD") {
                    Task {
                        do {
                            try await lexicon.addUserWords(input, language: language)
                            status = String(localized: "Words added.", locale: locale)
                            input = ""
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(NecroTheme.accent)
                if let status { Text(status).font(.caption.monospaced()) }
                Spacer()
            }
            .padding()
            .foregroundStyle(.white)
            .background(.black)
            .navigationTitle("Custom Lexicon")
            .toolbar {
                Button("CLOSE") { dismiss() }
            }
        }
    }
}

private struct UserWordsView: View {
    @Environment(\.dismiss) private var dismiss
    let lexicon: LexiconEngine
    let language: AppLanguage
    @State private var words: [String] = []

    var body: some View {
        NavigationStack {
            List(words, id: \.self) { word in
                Text(word).font(.body.monospaced())
            }
            .overlay {
                if words.isEmpty {
                    ContentUnavailableView("No custom words", systemImage: "text.badge.plus")
                }
            }
            .navigationTitle("My Words")
            .toolbar {
                Button("CLOSE") { dismiss() }
            }
            .task { words = await lexicon.userWords(for: language) }
        }
    }
}

extension AppLanguage {
    nonisolated var nativeName: String {
        switch self {
        case .french: "Français"
        case .english: "English"
        case .spanish: "Español"
        case .german: "Deutsch"
        case .italian: "Italiano"
        case .portuguese: "Português"
        case .romanian: "Română"
        case .japanese: "日本語"
        case .khmer: "ភាសាខ្មែរ"
        case .chinese: "中文"
        case .arabic: "العربية"
        }
    }
}
