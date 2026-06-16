//
//  TranscriptionViewModel.swift
//  HaileyLanguageAI
//
//  Created by 郭蕙瑄 on 2026/6/15.
//

import Combine
import Speech


final class TranscriptionViewModel: ObservableObject {
    @Published var transcript: String = ""
    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0
    @Published var statusText: String = "等待語音輸入"
    @Published var errorMessage: String? = nil
    @Published var preferredLocaleIDs: Set<String>
    @Published var detectedLocale: Locale? = nil

    let supportedLocales: [Locale]
    let commonLocaleOptions: [LocaleOption]

    private var recognitionTask: SFSpeechRecognitionTask?
    private var progressTimer: Timer?

    init() {
        let locales = SFSpeechRecognizer.supportedLocales().sorted { $0.identifier < $1.identifier }
        supportedLocales = locales

        let commonIdentifiers: [String] = [
            "zh-TW", "zh-CN", "en-US", "en-GB", "ja-JP", "ko-KR", "ar-SA",
            "es-ES", "fr-FR", "de-DE", "it-IT", "pt-BR", "pt-PT",
            "vi-VN", "th-TH", "id-ID", "ru-RU", "hi-IN"
        ]

        let options = locales.filter { commonIdentifiers.contains($0.identifier) }.map { locale in
            LocaleOption(
                id: locale.identifier,
                locale: locale,
                displayName: locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            )
        }.sorted { $0.displayName < $1.displayName }

        commonLocaleOptions = options

        var defaults = Set(["zh-TW", "en-US", "ar-SA"])
        defaults = defaults.intersection(Set(locales.map { $0.identifier }))
        if defaults.isEmpty, let first = options.first {
            defaults = [first.id]
        }
        preferredLocaleIDs = defaults
    }

    var preferredLocales: [Locale] {
        let preferred = supportedLocales.filter { preferredLocaleIDs.contains($0.identifier) }
        return preferred.isEmpty ? [Locale.current] : preferred
    }

    func requestAuthorizationIfNeeded() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                print("語音辨識權限被拒絕")
            }
        }
    }

    func handleIncoming(url: URL) {
        self.errorMessage = nil
        self.detectedLocale = nil
        let localURL = self.copyToTemporaryLocation(url: url)
        if let localURL {
            self.transcribeWithAutoDetect(at: localURL)
        } else {
            self.errorMessage = "無法讀取音訊檔案。"
        }
    }

    func transcribeWithAutoDetect(at url: URL) {
        guard !isProcessing else { return }

        transcript = ""
        isProcessing = true
        progress = 0
        statusText = "語言偵測中..."
        errorMessage = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        progressTimer?.invalidate()
        progressTimer = nil

        Task { @MainActor in
            let locales = preferredLocales
            var bestText: String = ""
            var bestScore: Float = -1
            var bestLocale: Locale? = nil

            for (index, locale) in locales.enumerated() {
                statusText = "偵測語言 \(index + 1)/\(locales.count)"
                if let result = await recognizeOnce(url: url, locale: locale) {
                    if result.score > bestScore {
                        bestScore = result.score
                        bestText = result.text
                        bestLocale = locale
                    }
                }
                let stepProgress = Double(index + 1) / Double(max(locales.count, 1))
                progress = min(0.9, stepProgress)
            }

            if bestScore >= 0, !bestText.isEmpty {
                transcript = bestText
                detectedLocale = bestLocale
                statusText = "完成"
                finishProgress(success: true)
            } else {
                statusText = "辨識失敗"
                errorMessage = "未找到可辨識的語言或內容。"
                finishProgress(success: false)
            }
        }
    }

    private func recognizeOnce(url: URL, locale: Locale) async -> (text: String, score: Float)? {
        await withCheckedContinuation { continuation in
            let recognizer = SFSpeechRecognizer(locale: locale)
            guard let recognizer, recognizer.isAvailable else {
                continuation.resume(returning: nil)
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: url)
            request.shouldReportPartialResults = false

            var didFinish = false
            recognitionTask?.cancel()
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self, !didFinish else { return }

                if let error {
                    didFinish = true
                    self.recognitionTask = nil
                    continuation.resume(returning: nil)
                    _ = error
                    return
                }

                if let result, result.isFinal {
                    didFinish = true
                    let text = result.bestTranscription.formattedString
                    let score = self.averageConfidence(for: result.bestTranscription)
                    self.recognitionTask = nil
                    continuation.resume(returning: (text, score))
                }
            }
        }
    }

    private func averageConfidence(for transcription: SFTranscription) -> Float {
        let segments = transcription.segments
        guard !segments.isEmpty else { return 0 }
        let total = segments.reduce(Float(0)) { partial, segment in
            partial + segment.confidence
        }
        return total / Float(segments.count)
    }

    private func finishProgress(success: Bool) {
        progressTimer?.invalidate()
        progressTimer = nil
        progress = 1
        isProcessing = false
        if !success, transcript.isEmpty {
            transcript = ""
        }
    }

    private func copyToTemporaryLocation(url: URL) -> URL? {
        var didAccess = false
        if url.startAccessingSecurityScopedResource() {
            didAccess = true
        }
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)

        do {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try FileManager.default.copyItem(at: url, to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
