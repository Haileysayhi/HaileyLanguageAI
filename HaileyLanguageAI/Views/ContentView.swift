//
//  ContentView.swift
//  HaileyLanguageAI
//
//  Created by 郭蕙瑄 on 2026/1/22.
//

import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers


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
                    GlassCard {
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

                    GlassCard {
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
                        GlassCard {
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

                    GlassCard {
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
}

#Preview {
    ContentView()
}
