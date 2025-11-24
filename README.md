# MeetSum

An open-source macOS meeting transcription app using AI, powered by Whisper.cpp and LLama.cpp.

## Features

- Real-time meeting transcription using Whisper
- AI-powered summarization with LLama
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
3. Download Whisper model: Visit https://ggml.ggerganov.com/ and download a model (e.g., ggml-base.bin)
4. Download LLama model: Visit https://huggingface.co/ and download a compatible model
5. Open the Xcode project
6. Update model paths in the code
7. Build and run

## Future Plans

- Embed Whisper.cpp and LLama.cpp directly into the app for better performance and offline capability
- Real-time transcription streaming
- Support for multiple languages
- Export transcriptions and summaries

## Contributing

Contributions welcome! Please open issues and pull requests on GitHub.

## License

MIT License