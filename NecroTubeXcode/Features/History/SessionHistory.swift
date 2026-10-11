import Combine
import Foundation
import SwiftUI

struct SessionEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let value: String
}

struct InvestigationSessionLog: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date?
    var events: [SessionEvent]
}

@MainActor
final class SessionHistoryStore: ObservableObject {
    @Published private(set) var sessions: [InvestigationSessionLog] = []

    private let defaults: UserDefaults
    private let storageKey = "necrotube.session.history"
    private var activeSessionID: UUID?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([InvestigationSessionLog].self, from: data) {
            sessions = decoded
        }
    }

    func beginSession() {
        let session = InvestigationSessionLog(id: UUID(), startedAt: .now, events: [])
        sessions.insert(session, at: 0)
        activeSessionID = session.id
        persist()
    }

    func append(_ value: String) {
        guard let activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[index].events.insert(SessionEvent(id: UUID(), date: .now, value: value), at: 0)
        persist()
    }

    func endSession() {
        guard let activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[index].endedAt = .now
        self.activeSessionID = nil
        persist()
    }

    func deleteSessions(at offsets: IndexSet) {
        sessions.remove(atOffsets: offsets)
        persist()
    }

    func clear() {
        sessions = []
        activeSessionID = nil
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

struct SessionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: SessionHistoryStore

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text("Session History")
                    .font(.system(size: 25, design: .monospaced))
                    .foregroundStyle(NecroTheme.accent)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        if store.sessions.isEmpty {
                            Text("No sessions")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.gray)
                                .frame(maxWidth: .infinity, minHeight: 180)
                        } else {
                            ForEach(store.sessions) { session in
                                SessionHistorySection(session: session)
                            }
                        }
                    }
                }

                HStack {
                    if !store.sessions.isEmpty {
                        Button("CLEAR", role: .destructive, action: store.clear)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    Spacer()
                    Button("BACK") { dismiss() }
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(NecroTheme.accent)
                }
            }
            .padding(24)
            .frame(width: 310, height: 440)
            .background(Color(red: 0.055, green: 0.055, blue: 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 29))
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct SessionHistorySection: View {
    let session: InvestigationSessionLog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(session.startedAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                    .foregroundStyle(NecroTheme.gold)
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "share.fill")
                        .foregroundStyle(NecroTheme.accent)
                }
            }
            .font(.system(size: 11, design: .monospaced))

            if session.events.isEmpty {
                Text("No words detected")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(session.events) { event in
                    HStack(alignment: .firstTextBaseline) {
                        Text(event.date, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                        Text("[SENSOR ACTIVITY]: \(event.value)")
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.gray)
                }
            }
            Divider().overlay(Color.white.opacity(0.08))
        }
    }

    private var shareText: String {
        let entries = session.events.map {
            "\($0.date.formatted(date: .omitted, time: .standard)) [SENSOR ACTIVITY]: \($0.value)"
        }
        return (["NecroTube — \(session.startedAt.formatted())"] + entries).joined(separator: "\n")
    }
}
