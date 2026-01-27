# HaileyLanguageAI

A SwiftUI iOS app that turns imported audio files into text by auto-detecting the best language from a user-selected set of locales. It provides progress feedback, confidence-based selection, and a clean glassmorphism-style interface.

## Features
- Import audio files and transcribe to text
- Auto-detect the best language among preferred locales
- Progress and status display during recognition
- Language selection sheet with common locales
- Editable transcript output

## Requirements
- Xcode 26.2
- iOS 26.2 (minimum)
- Speech recognition permission enabled on device

## Setup
1. Open `HaileyLanguageAI.xcodeproj` in Xcode.
2. Select a signing team in the project settings if needed.
3. Build and run on a real device (speech recognition may be limited on the simulator).

## Usage
1. Tap **Select Audio File** and choose an audio file (e.g., m4a, mp3, wav).
2. The app tries your preferred languages and picks the best result by confidence.
3. The transcript appears in the editor; you can copy or edit it.

## Notes
- Speech recognition availability and quality depend on locale and device settings.
- If no preferred locale is selected, the app falls back to the current system locale.

## Tech Stack
- SwiftUI
- Speech framework (SFSpeechRecognizer)
- AVFoundation

## License
MIT
