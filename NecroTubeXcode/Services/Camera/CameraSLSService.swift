@preconcurrency import AVFoundation
import Combine
import os
import Photos
import SwiftUI
import UIKit
import Vision

@MainActor
final class CameraSLSService: NSObject, ObservableObject, CameraServicing {
    enum CameraError: LocalizedError {
        case permissionDenied
        case unavailable
        case configurationFailed
        case recordingUnavailable
        case microphonePermissionDenied
        case photosPermissionDenied
        case invalidRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied: "L’accès à la caméra est refusé."
            case .unavailable: "Aucune caméra n’est disponible."
            case .configurationFailed: "La caméra n’a pas pu être configurée."
            case .recordingUnavailable: "L’enregistrement vidéo n’est pas disponible."
            case .microphonePermissionDenied: "L’accès au microphone est requis pour enregistrer la vidéo avec le son."
            case .photosPermissionDenied: "L’accès à Photos est refusé."
            case .invalidRecording: "La vidéo enregistrée est vide ou illisible."
            }
        }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var skeletonSegments: [SkeletonSegment] = []
    @Published private(set) var isRecording = false
    @Published private(set) var lastRecordingURL: URL?
    @Published private(set) var recordingError: String?
    @Published private(set) var recordingMessage: String?
    @Published private(set) var recentRecordings: [URL] = []
    @Published var isSLSEnabled = false {
        didSet {
            let enabled = isSLSEnabled
            slsState.withLock { $0 = enabled }
        }
    }

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.necrotube.camera.session")
    private let videoQueue = DispatchQueue(label: "com.necrotube.camera.frames", qos: .userInitiated)
    private let movieOutput = AVCaptureMovieFileOutput()
    nonisolated private let slsState = OSAllocatedUnfairLock(initialState: false)
    nonisolated private let lastPoseTimestamp = OSAllocatedUnfairLock(initialState: ContinuousClock.Instant?.none)
    private var currentPosition: AVCaptureDevice.Position = .back
    private var configured = false
    private var recordingStartContinuation: CheckedContinuation<Void, Error>?
    private var recordingStopContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        refreshRecordings()
    }

    func requestAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start() async throws {
#if targetEnvironment(simulator)
        throw CameraError.unavailable
#else
        guard AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: currentPosition
        ) != nil else {
            throw CameraError.unavailable
        }
        guard await requestAuthorization() else { throw CameraError.permissionDenied }
        if !configured {
            try configure(position: currentPosition)
        }
        let captureSession = session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if !captureSession.isRunning { captureSession.startRunning() }
                continuation.resume()
            }
        }
        isRunning = true
#endif
    }

    func stop() async {
        if movieOutput.isRecording {
            await stopRecording()
        }
        let captureSession = session
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                if captureSession.isRunning { captureSession.stopRunning() }
                continuation.resume()
            }
        }
        isRunning = false
        skeletonSegments = []
    }

    func switchCamera() async throws {
        guard !movieOutput.isRecording else { throw CameraError.recordingUnavailable }
        currentPosition = currentPosition == .back ? .front : .back
        try configure(position: currentPosition)
    }

    func toggleRecording() async throws {
        if movieOutput.isRecording {
            await stopRecording()
            return
        }
        guard isRunning else { throw CameraError.recordingUnavailable }
        guard await AVAudioApplication.requestRecordPermission() else {
            throw CameraError.microphonePermissionDenied
        }
        try AudioSessionCoordinator.shared.acquire(.videoRecording)
        do {
            try await ensureAudioInput()
        } catch {
            AudioSessionCoordinator.shared.release(.videoRecording)
            throw error
        }

        let recordingsDirectory = recordingsDirectory()
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        let fileName = "NecroTube_\(UUID().uuidString).mov"
        let destination = recordingsDirectory.appending(path: fileName)
        recordingError = nil
        recordingMessage = nil
        lastRecordingURL = destination
        let output = movieOutput
        try await withCheckedThrowingContinuation { continuation in
            recordingStartContinuation = continuation
            sessionQueue.async {
                output.startRecording(to: destination, recordingDelegate: self)
            }
        }
    }

    func deleteRecording(at url: URL) throws {
        let directory = recordingsDirectory().standardizedFileURL
        let candidate = url.standardizedFileURL
        guard candidate.deletingLastPathComponent() == directory else { return }
        if FileManager.default.fileExists(atPath: candidate.path) {
            try FileManager.default.removeItem(at: candidate)
        }
        refreshRecordings()
    }

    private func configure(position: AVCaptureDevice.Position) throws {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: position
        ) else {
            throw CameraError.unavailable
        }

        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)

        session.beginConfiguration()
        session.sessionPreset = .high
        session.automaticallyConfiguresApplicationAudioSession = false
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)

        guard session.canAddInput(input), session.canAddOutput(output), session.canAddOutput(movieOutput) else {
            session.commitConfiguration()
            throw CameraError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(output)
        session.addOutput(movieOutput)
        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
        session.commitConfiguration()
        configured = true
    }

    private func ensureAudioInput() async throws {
        let captureSession = session
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    if captureSession.inputs.contains(where: {
                        $0.ports.contains(where: { $0.mediaType == .audio })
                    }) {
                        continuation.resume()
                        return
                    }
                    guard let microphone = AVCaptureDevice.default(for: .audio) else {
                        throw CameraError.recordingUnavailable
                    }
                    let audioInput = try AVCaptureDeviceInput(device: microphone)
                    guard captureSession.canAddInput(audioInput) else {
                        throw CameraError.configurationFailed
                    }
                    captureSession.beginConfiguration()
                    captureSession.addInput(audioInput)
                    captureSession.commitConfiguration()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func stopRecording() async {
        guard movieOutput.isRecording else { return }
        await withCheckedContinuation { continuation in
            recordingStopContinuation = continuation
            let output = movieOutput
            sessionQueue.async {
                output.stopRecording()
            }
        }
    }

    private func recordingsDirectory() -> URL {
        URL.documentsDirectory.appending(path: "NecroTube Videos", directoryHint: .isDirectory)
    }

    private func refreshRecordings() {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        recentRecordings = ((try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectory(),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (lhs ?? .distantPast) > (rhs ?? .distantPast)
            }
    }

    private func saveToPhotos(_ url: URL) async throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) > 1_024 else {
            throw CameraError.invalidRecording
        }
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric, duration.seconds > 0 else {
            throw CameraError.invalidRecording
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw CameraError.photosPermissionDenied
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CameraError.recordingUnavailable)
                }
            }
        }
    }

    private nonisolated func detectPose(in sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let request = VNDetectHumanBodyPoseRequest()
        do {
            // The capture connection rotates portrait frames and mirrors the front
            // camera before delivery, so Vision and the SwiftUI overlay share the
            // same coordinate system.
            try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
            guard let observation = request.results?.first else {
                clearPoseAfterGracePeriod()
                return
            }
            let segments = Self.makeSegments(from: observation)
            guard !segments.isEmpty else {
                clearPoseAfterGracePeriod()
                return
            }
            lastPoseTimestamp.withLock { $0 = .now }
            Task { @MainActor in self.skeletonSegments = segments }
        } catch {
            clearPoseAfterGracePeriod()
        }
    }

    private nonisolated func clearPoseAfterGracePeriod() {
        let shouldClear = lastPoseTimestamp.withLock { timestamp in
            guard let timestamp else { return true }
            return timestamp.duration(to: .now) > .milliseconds(600)
        }
        guard shouldClear else { return }
        Task { @MainActor in self.skeletonSegments = [] }
    }

    private nonisolated static func makeSegments(from observation: VNHumanBodyPoseObservation) -> [SkeletonSegment] {
        let pairs: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
            (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
            (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
            (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
            (.neck, .root), (.root, .leftHip), (.root, .rightHip),
            (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
            (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
        ]
        guard let points = try? observation.recognizedPoints(.all) else { return [] }
        return pairs.compactMap { startName, endName in
            guard let start = points[startName], let end = points[endName],
                  start.confidence >= 0.35, end.confidence >= 0.35 else { return nil }
            return SkeletonSegment(
                start: CGPoint(x: start.location.x, y: 1 - start.location.y),
                end: CGPoint(x: end.location.x, y: 1 - end.location.y),
                confidence: min(start.confidence, end.confidence)
            )
        }
    }
}

extension CameraSLSService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor in
            self.isRecording = true
            self.lastRecordingURL = fileURL
            self.recordingStartContinuation?.resume()
            self.recordingStartContinuation = nil
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.isRecording = false
            AudioSessionCoordinator.shared.release(.videoRecording)
            let recordingSucceeded = error.map { error in
                (error as NSError).userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            } ?? true
            if let continuation = self.recordingStartContinuation {
                if let error, !recordingSucceeded {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(throwing: CameraError.recordingUnavailable)
                }
                self.recordingStartContinuation = nil
            }
            if let error, !recordingSucceeded {
                self.recordingError = error.localizedDescription
            } else {
                self.lastRecordingURL = outputFileURL
                self.refreshRecordings()
                do {
                    try await self.saveToPhotos(outputFileURL)
                    self.recordingMessage = "Enregistrement sauvegardé dans Photos."
                } catch {
                    self.recordingError = "Vidéo conservée dans l’app, mais non ajoutée à Photos : \(error.localizedDescription)"
                }
            }
            self.recordingStopContinuation?.resume()
            self.recordingStopContinuation = nil
        }
    }
}

extension CameraSLSService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard slsState.withLock({ $0 }) else {
            Task { @MainActor in
                if !self.skeletonSegments.isEmpty { self.skeletonSegments = [] }
            }
            return
        }
        detectPose(in: sampleBuffer)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let layer = layer as? AVCaptureVideoPreviewLayer else {
            preconditionFailure("Couche de prévisualisation caméra indisponible.")
        }
        return layer
    }
}

struct SkeletonOverlay: View {
    let segments: [SkeletonSegment]

    var body: some View {
        Canvas { context, size in
            for segment in segments {
                var path = Path()
                path.move(to: CGPoint(x: segment.start.x * size.width, y: segment.start.y * size.height))
                path.addLine(to: CGPoint(x: segment.end.x * size.width, y: segment.end.y * size.height))
                context.stroke(path, with: .color(NecroTheme.accent), lineWidth: 3)
            }
        }
        .allowsHitTesting(false)
    }
}
