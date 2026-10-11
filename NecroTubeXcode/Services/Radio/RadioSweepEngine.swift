import AVFoundation
import Combine
import Foundation

enum RadioBand: String, CaseIterable, Sendable {
    case am = "AM"
    case fm = "FM"
}

@MainActor
final class RadioSweepEngine: ObservableObject, RadioSweepServicing {
    enum SweepState: Equatable {
        case idle
        case loading
        case active
        case stopped
        case failed(String)
    }

    enum RadioError: LocalizedError {
        case noStations
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .noStations: "Aucune station vocale compatible n’a été trouvée."
            case .invalidResponse: "Le service de stations radio a renvoyé une réponse invalide."
            }
        }
    }

    @Published private(set) var state: SweepState = .idle
    @Published private(set) var currentStationNames = ["—", "—"]
    @Published private(set) var stationCount = 0
    @Published private(set) var channelEnabled = [true, true]
    @Published private(set) var channelBands: [RadioBand] = [.fm, .am]
    @Published private(set) var channelIntervalsMilliseconds = [300, 450]
    @Published private(set) var channelVolumes: [Float] = [0.8, 0.7]
    @Published private(set) var channelReversed = [false, false]
    @Published private(set) var isWhiteNoisePlaying = false
    @Published var whiteNoiseEnabled = true
    @Published var whiteNoiseVolume: Float {
        didSet {
            let clamped = min(0.05, max(0, whiteNoiseVolume))
            if clamped != whiteNoiseVolume {
                whiteNoiseVolume = clamped
                return
            }
            UserDefaults.standard.set(Double(clamped), forKey: "spiritbox.whiteNoiseVolume")
        }
    }
    @Published var errorMessage: String?
    @Published var selectedLanguage: AppLanguage {
        didSet {
            guard !suppressesLanguageReload, oldValue != selectedLanguage else { return }
            Task { await reloadForSelectedLanguageIfNeeded() }
        }
    }

    private let session: URLSession
    private static let playerCountPerChannel = 8
    private let players = (0..<2).map { _ in
        (0..<RadioSweepEngine.playerCountPerChannel).map { _ in AVPlayer() }
    }
    private let noiseEngine = AVAudioEngine()
    private var noiseNode: AVAudioSourceNode?
    private var sweepTasks: [Task<Void, Never>?] = [nil, nil]
    private var stationLoadTask: Task<[RadioStation], Error>?
    private var stationsByBand: [RadioBand: [RadioStation]] = [:]
    private var generation = 0
    private var suppressesLanguageReload = false
    private var activePlayerIndices = [0, 0]
    private var nextStationIndices = [0, 0]
    private let radioVolume: Float = 0.8
    private let emfVolumeFactor: Float = 1
    private var stationAssignments = Array(
        repeating: Array<RadioStation?>(repeating: nil, count: RadioSweepEngine.playerCountPerChannel),
        count: 2
    )
    private var resumptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    init(session: URLSession = .shared, selectedLanguage: AppLanguage = .french) {
        self.session = session
        self.selectedLanguage = selectedLanguage
        let defaults = UserDefaults.standard
        whiteNoiseVolume = defaults.object(forKey: "spiritbox.whiteNoiseVolume") == nil
            ? 0.015
            : min(0.05, max(0, defaults.float(forKey: "spiritbox.whiteNoiseVolume")))
        for channel in players.indices {
            for player in players[channel] {
                player.volume = 0
                player.automaticallyWaitsToMinimizeStalling = false
            }
        }
        resumptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.resumeAfterSystemAudioChange() }
        }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [self] in self.resumeAfterSystemAudioChange() }
        }
    }

    func start(language: AppLanguage) async throws {
        suppressesLanguageReload = true
        selectedLanguage = language
        suppressesLanguageReload = false
        try await startCurrentLanguage()
    }

    func stop() async {
        generation &+= 1
        stationLoadTask?.cancel()
        stationLoadTask = nil
        cancelSweepTasks()
        silenceAllPlayers()
        stopWhiteNoisePlayback()
        stationsByBand.removeAll()
        currentStationNames = ["—", "—"]
        stationCount = 0
        AudioSessionCoordinator.shared.release(.radio)
        state = .stopped
    }

    func setChannelEnabled(_ enabled: Bool, channel: Int) {
        guard players.indices.contains(channel) else { return }
        channelEnabled[channel] = enabled
        if !enabled {
            players[channel].forEach { $0.volume = 0 }
        }
    }

    func setBand(_ band: RadioBand, channel: Int) {
        guard players.indices.contains(channel), channelBands[channel] != band else { return }
        channelBands[channel] = band
    }

    func setSweepInterval(milliseconds: Int, channel: Int) {
        guard players.indices.contains(channel) else { return }
        let stepped = Int((Double(milliseconds) / 50).rounded()) * 50
        channelIntervalsMilliseconds[channel] = min(400, max(50, stepped))
    }

    func setVolume(_ volume: Float, channel: Int) {
        guard players.indices.contains(channel) else { return }
        let clamped = min(1, max(0, volume))
        channelVolumes[channel] = clamped
        let activeIndex = activePlayerIndices[channel]
        players[channel][activeIndex].volume = channelEnabled[channel] ? effectiveVolume(for: channel) : 0
    }

    func toggleDirection(channel: Int) {
        guard players.indices.contains(channel) else { return }
        channelReversed[channel].toggle()
    }

    func setWhiteNoiseEnabled(_ enabled: Bool) async throws {
        whiteNoiseEnabled = enabled
        if enabled, state == .active {
            try await startWhiteNoisePlayback()
        } else {
            stopWhiteNoisePlayback()
        }
    }

    private func startCurrentLanguage() async throws {
        generation &+= 1
        let requestedGeneration = generation

        stationLoadTask?.cancel()
        cancelSweepTasks()
        silenceAllPlayers()
        stopWhiteNoisePlayback()
        state = .loading
        currentStationNames = ["—", "—"]
        stationCount = 0

        try AudioSessionCoordinator.shared.acquire(.radio)

        let language = selectedLanguage
        let loadTask = Task { try await fetchStations(language: language) }
        stationLoadTask = loadTask

        do {
            let stations = try await loadTask.value
            guard requestedGeneration == generation, !Task.isCancelled else {
                throw CancellationError()
            }
            guard !stations.isEmpty else { throw RadioError.noStations }

            // Android fills two independently shuffled pools from the same
            // voice-oriented station candidates.
            stationsByBand[.am] = stations.shuffled()
            stationsByBand[.fm] = stations.shuffled()
            stationCount = stations.count
            stationLoadTask = nil

            for channel in players.indices {
                primeChannel(channel)
            }
            let hasPlayableStations = await waitForInitialBuffers(generation: requestedGeneration)
            guard requestedGeneration == generation else { throw CancellationError() }
            guard hasPlayableStations else { throw RadioError.noStations }

            state = .active
            if whiteNoiseEnabled {
                try await startWhiteNoisePlayback()
            }
            for channel in players.indices {
                let offset = channel == 1 ? channelIntervalsMilliseconds[0] / 2 : 0
                restartSweepTask(channel: channel, initialDelayMilliseconds: offset)
            }
        } catch is CancellationError {
            if requestedGeneration == generation {
                state = .stopped
            }
        } catch {
            guard requestedGeneration == generation else { return }
            stationLoadTask = nil
            silenceAllPlayers()
            stopWhiteNoisePlayback()
            AudioSessionCoordinator.shared.release(.radio)
            let message = Self.userFacingMessage(for: error)
            state = .failed(message)
            errorMessage = message
            throw error
        }
    }

    private func reloadForSelectedLanguageIfNeeded() async {
        guard state == .active || state == .loading else { return }
        do {
            try await startCurrentLanguage()
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func primeChannel(_ channel: Int) {
        guard let pool = stationsByBand[channelBands[channel]], !pool.isEmpty else { return }
        activePlayerIndices[channel] = 0
        nextStationIndices[channel] = channel

        for slot in players[channel].indices {
            loadNextStation(into: slot, channel: channel, pool: pool)
        }
    }

    private func loadNextStation(into slot: Int, channel: Int, pool: [RadioStation]) {
        guard !pool.isEmpty else { return }
        let rawIndex = nextStationIndices[channel]
        let index = (rawIndex % pool.count + pool.count) % pool.count
        let station = pool[index]
        nextStationIndices[channel] += channelReversed[channel] ? -1 : 1

        let item = AVPlayerItem(url: station.url)
        item.preferredForwardBufferDuration = 1
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        let player = players[channel][slot]
        player.volume = 0
        player.replaceCurrentItem(with: item)
        player.playImmediately(atRate: 1)
        stationAssignments[channel][slot] = station
    }

    private func restartSweepTask(channel: Int, initialDelayMilliseconds: Int = 0) {
        sweepTasks[channel]?.cancel()

        for player in players[channel] where player.currentItem != nil {
            player.volume = 0
            player.playImmediately(atRate: 1)
        }

        let requestedGeneration = generation
        sweepTasks[channel] = makeSweepTask(
            channel: channel,
            generation: requestedGeneration,
            initialDelayMilliseconds: initialDelayMilliseconds
        )
    }

    private func makeSweepTask(
        channel: Int,
        generation requestedGeneration: Int,
        initialDelayMilliseconds: Int
    ) -> Task<Void, Never> {
        Task { [weak self] in
            if initialDelayMilliseconds > 0 {
                do {
                    try await Task.sleep(for: .milliseconds(initialDelayMilliseconds))
                } catch {
                    return
                }
            }

            guard let self else { return }
            var lastStationChange = ContinuousClock.now

            while !Task.isCancelled {
                guard requestedGeneration == self.generation,
                      self.state == .active,
                      self.stationsByBand[self.channelBands[channel]]?.isEmpty == false else { return }

                if self.channelEnabled[channel] {
                    let interval = Duration.milliseconds(self.channelIntervalsMilliseconds[channel])
                    if ContinuousClock.now - lastStationChange >= interval {
                        lastStationChange = .now
                        let previousIndex = self.activePlayerIndices[channel]
                        let previousPlayer = self.players[channel][previousIndex]
                        self.activePlayerIndices[channel] =
                            (previousIndex + 1) % self.players[channel].count
                        previousPlayer.volume = 0
                        if let pool = self.stationsByBand[self.channelBands[channel]], !pool.isEmpty {
                            self.loadNextStation(into: previousIndex, channel: channel, pool: pool)
                        }
                    }

                    let activeIndex = self.activePlayerIndices[channel]
                    let activePlayer = self.players[channel][activeIndex]
                    if activePlayer.currentItem?.status == .failed {
                        activePlayer.volume = 0
                        if let pool = self.stationsByBand[self.channelBands[channel]], !pool.isEmpty {
                            self.loadNextStation(into: activeIndex, channel: channel, pool: pool)
                        }
                        self.currentStationNames[channel] = "Station suivante…"
                        try? await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                    // Same volume gate as Android:
                    // channel volume × global radio volume × EMF factor.
                    activePlayer.volume = self.effectiveVolume(for: channel)
                    activePlayer.playImmediately(atRate: 1)
                    self.currentStationNames[channel] =
                        self.stationAssignments[channel][activeIndex]?.name ?? "—"
                } else {
                    self.players[channel].forEach { $0.volume = 0 }
                }

                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    private func effectiveVolume(for channel: Int) -> Float {
        min(1, max(0, channelVolumes[channel] * radioVolume * emfVolumeFactor))
    }

    private func waitForInitialBuffers(generation requestedGeneration: Int) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(8)
        while ContinuousClock.now < deadline,
              requestedGeneration == generation,
              !Task.isCancelled {
            let enabledChannels = players.indices.filter { channelEnabled[$0] }
            let ready = enabledChannels.allSatisfy { channel in
                players[channel].filter { $0.currentItem?.status == .readyToPlay }.count >= 2
            }
            if ready { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return players.indices
            .filter { channelEnabled[$0] }
            .allSatisfy { channel in
                players[channel].contains { $0.currentItem?.status == .readyToPlay }
            }
    }

    private func cancelSweepTasks() {
        sweepTasks.forEach { $0?.cancel() }
        sweepTasks = [nil, nil]
    }

    private func silencePlayer(channel: Int) {
        for slot in players[channel].indices {
            let player = players[channel][slot]
            player.cancelPendingPrerolls()
            player.volume = 0
            player.pause()
            player.rate = 0
            player.replaceCurrentItem(with: nil)
            stationAssignments[channel][slot] = nil
        }
        activePlayerIndices[channel] = 0
    }

    private func silenceAllPlayers() {
        players.indices.forEach(silencePlayer(channel:))
    }

    private func startWhiteNoisePlayback() async throws {
        guard !isWhiteNoisePlaying else { return }

        var generator = SystemRandomNumberGenerator()
        var smoothedLevel = whiteNoiseVolume
        let source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let targetLevel = self.whiteNoiseVolume
            for frame in 0..<Int(frameCount) {
                smoothedLevel += (targetLevel - smoothedLevel) * 0.002
                for buffer in buffers {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    data[frame] = Float.random(in: -1...1, using: &generator) * smoothedLevel
                }
            }
            return noErr
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        noiseEngine.attach(source)
        noiseNode = source
        try noiseEngine.connectNode(source, to: noiseEngine.mainMixerNode, format: format)
        noiseEngine.prepare()
        try noiseEngine.start()
        isWhiteNoisePlaying = true
    }

    private func stopWhiteNoisePlayback() {
        guard let noiseNode else {
            isWhiteNoisePlaying = false
            return
        }
        noiseEngine.disconnectNodeOutput(noiseNode)
        noiseEngine.detach(noiseNode)
        noiseEngine.stop()
        self.noiseNode = nil
        isWhiteNoisePlaying = false
    }

    private func resumeAfterSystemAudioChange() {
        guard state == .active else { return }
        do {
            try AudioSessionCoordinator.shared.reactivateIfNeeded()
            if whiteNoiseEnabled, isWhiteNoisePlaying, !noiseEngine.isRunning {
                try noiseEngine.start()
            }
            for channel in players.indices where channelEnabled[channel] {
                players[channel][activePlayerIndices[channel]].playImmediately(atRate: 1)
            }
        } catch {
            errorMessage = "Audio temporairement indisponible. Reprise automatique en attente."
        }
    }

    private func fetchStations(language: AppLanguage) async throws -> [RadioStation] {
        let profile = searchProfile(for: language)
        let languages = language == .chinese ? ["chinese", "mandarin"] : [profile.language]
        let decoded = try await withThrowingTaskGroup(of: [RadioStation].self) { group in
            for country in profile.countries {
                for requestedLanguage in languages {
                    group.addTask { [session] in
                        var components = URLComponents(string: "https://de1.api.radio-browser.info/json/stations/search")
                        components?.queryItems = [
                            URLQueryItem(name: "country", value: country),
                            URLQueryItem(name: "language", value: requestedLanguage),
                            URLQueryItem(name: "limit", value: "100"),
                            URLQueryItem(name: "hidebroken", value: "true"),
                            URLQueryItem(name: "order", value: "clickcount"),
                            URLQueryItem(name: "reverse", value: "true")
                        ]
                        guard let url = components?.url else { return [] }
                        var request = URLRequest(url: url)
                        request.timeoutInterval = 8
                        request.setValue("NecroTube-iOS/1.0", forHTTPHeaderField: "User-Agent")
                        let (data, response) = try await session.data(for: request)
                        guard let http = response as? HTTPURLResponse,
                              200..<300 ~= http.statusCode else {
                            return []
                        }
                        return (try? JSONDecoder().decode([RadioStation].self, from: data)) ?? []
                    }
                }
            }
            var combined: [RadioStation] = []
            for try await stations in group {
                combined.append(contentsOf: stations)
            }
            return combined
        }
        try Task.checkCancellation()
        let music = ["hits", "top40", "pop", "rock", "dance", "electro", "house", "music", "song", "mix", "chart", "rnb", "rap", "jazz", "classical", "reggae", "metal", "country", "dj", "musical", "chanson", "musica", "disco", "soul", "blues", "party", "top", "playlist"]
        let talk = ["talk", "news", "parole", "info", "speech", "debate", "actualité", "vocal", "discurs", "entrevista", "podcast", "radio nationale", "journal", "diario", "noticias", "information", "culture", "education", "religion", "politics", "sport", "interview", "discussion"]
        let acceptedLanguages = languageMetadataAliases(for: language)

        var seen = Set<String>()
        let eligible = decoded.filter { station in
            guard seen.insert(station.changeuuid).inserted else { return false }
            let declaredLanguages = metadataTokens(from: station.language)
            guard station.url.scheme?.lowercased() == "https",
                  declaredLanguages.isEmpty || !acceptedLanguages.isDisjoint(with: declaredLanguages) else {
                return false
            }
            return true
        }

        func descriptor(for station: RadioStation) -> String {
            "\(station.name) \(station.tags)".folding(
                options: [.diacriticInsensitive, .caseInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ).lowercased()
        }

        // Match Android's preference for speech, but do not fail the whole
        // Spirit Box when Radio Browser metadata is missing or inconsistent.
        let spoken = eligible.filter { station in
            let value = descriptor(for: station)
            return talk.contains(where: value.contains) && !music.contains(where: value.contains)
        }
        let nonMusic = eligible.filter { station in
            let value = descriptor(for: station)
            return !music.contains(where: value.contains)
        }

        var selected: [RadioStation] = []
        var selectedIDs = Set<String>()
        for station in spoken + nonMusic + eligible {
            guard selectedIDs.insert(station.changeuuid).inserted else { continue }
            selected.append(station)
            if selected.count == 30 { break }
        }
        return selected
    }

    private func metadataTokens(from value: String) -> Set<String> {
        let separators = CharacterSet(charactersIn: ",;/|")
        return Set(value.components(separatedBy: separators).compactMap { component in
            let normalized = component.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            return normalized.isEmpty ? nil : normalized
        })
    }

    private func languageMetadataAliases(for language: AppLanguage) -> Set<String> {
        switch language {
        case .french: ["fr", "fra", "fre", "french", "francais", "français"]
        case .english: ["en", "eng", "english"]
        case .spanish: ["es", "spa", "spanish", "espanol", "español"]
        case .german: ["de", "deu", "ger", "german", "deutsch"]
        case .italian: ["it", "ita", "italian", "italiano"]
        case .portuguese: ["pt", "por", "portuguese", "portugues", "português"]
        case .romanian: ["ro", "ron", "rum", "romanian", "romana", "română"]
        case .japanese: ["ja", "jpn", "japanese", "日本語"]
        case .khmer: ["km", "khm", "khmer", "cambodian", "ភាសាខ្មែរ"]
        case .chinese: ["zh", "zho", "chi", "chinese", "mandarin", "中文"]
        case .arabic: ["ar", "ara", "arabic", "العربية"]
        }
    }

    private func searchProfile(for language: AppLanguage) -> (language: String, countries: [String]) {
        switch language {
        case .french: ("french", ["France", "Canada", "Belgium"])
        case .english: ("english", ["United States", "United Kingdom", "Canada"])
        case .spanish: ("spanish", ["Spain", "Mexico", "Argentina"])
        case .german: ("german", ["Germany", "Austria", "Switzerland"])
        case .italian: ("italian", ["Italy"])
        case .portuguese: ("portuguese", ["Portugal", "Brazil"])
        case .romanian: ("romanian", ["Romania"])
        case .japanese: ("japanese", ["Japan"])
        case .khmer: ("khmer", ["Cambodia"])
        case .chinese: ("chinese", ["China", "Taiwan"])
        case .arabic: ("arabic", ["Egypt", "Morocco", "Saudi Arabia"])
        }
    }

    private static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain, nsError.code == 561_017_449 {
            return "La sortie audio est momentanément utilisée par le système. Fermez Siri ou l’appel en cours, puis réessayez."
        }
        return error.localizedDescription
    }
}
