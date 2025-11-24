# MeetSum

An open-source macOS meeting transcription app using AI, powered by Whisper.cpp and LLama.cpp.

## Features

- Meeting audio recording with timer display
- Automatic transcription using Whisper.cpp
- AI-powered summarization with LLama.cpp
- Export transcriptions and summaries to text files
- Progress indicators during processing
- Clear and intuitive SwiftUI interface
- Native macOS app for Apple Silicon (macOS 15+)
- Open-source and privacy-focused

## Development

This app uses:
- Whisper.cpp for speech-to-text transcription
- LLama.cpp for AI summarization
- SwiftUI for the native macOS interface

## Getting Started

1. Clone the repository
2. Install dependencies: `brew install whisper-cpp llama.cpp`
3. Download models: Models are included in the models/ directory (ggml-tiny.bin for Whisper, tinyllama-1.1b-chat-v1.0.Q4_0.gguf for LLama)
4. Open the Xcode project (MeetSum.xcodeproj)
5. Build and run the app
6. Grant microphone permission when prompted
7. Click "Start Recording" to begin recording your meeting
8. Click "Stop Recording" to process the audio and generate transcription and summary
9. Use the export buttons to save results to files

## Future Plans

- Embed Whisper.cpp and LLama.cpp directly into the app for better performance and offline capability
- Real-time transcription streaming
- Support for multiple languages
- Export transcriptions and summaries

## Contributing

Contributions welcome! Please open issues and pull requests on GitHub.

## License

MIT License