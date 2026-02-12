//
//  ContentView.swift
//  HaileyLanguageAI
//
//  Created by 郭蕙瑄 on 2026/1/22.
//

import AVFoundation
import Combine
import Speech
import SwiftUI
import UniformTypeIdentifiers

struct LocaleOption: Identifiable, Hashable {
    let id: String
    let locale: Locale
    let displayName: String
}

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

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()
    @State private var isImporterPresented = false
    @State private var isLanguageSheetPresented = false

    private var isRightToLeft: Bool {
        (viewModel.detectedLocale ?? Locale.current).languageCode == "ar"
    }

    private var preferredLanguageSummary: String {
        let names = viewModel.commonLocaleOptions
            .filter { viewModel.preferredLocaleIDs.contains($0.id) }
            .map { $0.displayName }
        if names.isEmpty { return "尚未選擇" }
        return names.joined(separator: "、")
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.72, blue: 0.92),
                    Color(red: 0.98, green: 0.55, blue: 0.62),
                    Color(red: 0.99, green: 0.45, blue: 0.36)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                glassCard {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "waveform")
                                .font(.system(size: 18, weight: .semibold))
                            Text("匯入語音檔")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .foregroundStyle(.white)

                        Button {
                            isImporterPresented = true
                        } label: {
                            Text("選擇語音檔")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                glassCard {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "globe.asia.australia")
                                .font(.system(size: 18, weight: .semibold))
                            Text("常用語言")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                            Button {
                                isLanguageSheetPresented = true
                            } label: {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white.opacity(0.9))
                        }
                        .foregroundStyle(.white)

                        Text(preferredLanguageSummary)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if viewModel.isProcessing {
                    glassCard {
                        VStack(spacing: 12) {
                            ZStack {
                                ProgressView(value: viewModel.progress)
                                    .progressViewStyle(.circular)
                                    .scaleEffect(1.7)
                                Text("\(Int(viewModel.progress * 100))%")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            Text(viewModel.statusText)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                } else {
                    Text(viewModel.statusText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }

                glassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "text.quote")
                                .font(.system(size: 18, weight: .semibold))
                            Text("語音文字輸出")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $viewModel.transcript)
                                .font(.system(size: 16))
                                .foregroundStyle(.white)
                                .padding(10)
                                .scrollContentBackground(.hidden)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .textSelection(.enabled)

                            if viewModel.transcript.isEmpty {
                                Text("尚未收到語音內容")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 18)
                            }
                        }
                        .frame(minHeight: 360, maxHeight: 520)
                        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)

                        if let errorMessage = viewModel.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            viewModel.requestAuthorizationIfNeeded()
        }
        .onOpenURL { url in
            viewModel.handleIncoming(url: url)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.audio, .mpeg4Audio, .mp3, .wav],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.handleIncoming(url: url)
                }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isLanguageSheetPresented) {
            NavigationStack {
                List(viewModel.commonLocaleOptions, selection: $viewModel.preferredLocaleIDs) { option in
                    HStack {
                        Text(option.displayName)
                        Spacer()
                        if viewModel.preferredLocaleIDs.contains(option.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("選擇常用語言")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            isLanguageSheetPresented = false
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.15), radius: 16, x: 0, y: 8)
    }
}

#Preview {
    ContentView()
}
