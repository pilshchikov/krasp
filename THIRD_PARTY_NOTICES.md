# Third Party Notices

Krasp downloads and bundles third-party runtime components during `make neural` and `make app`.

## Hush

- Project: `weya-ai/hush`
- Source: https://huggingface.co/weya-ai/hush
- Component used: `onnx/advanced_dfnet16k_model_best_onnx.tar.gz`
- License: Apache-2.0

## DeepFilterNet / libDF

- Project: DeepFilterNet
- Source: https://github.com/Rikorose/DeepFilterNet
- Component used: `libDF` C API built as `libdf.dylib`
- License: Apache-2.0 or MIT, as published by the upstream project.

## Apple Frameworks

Krasp uses Apple system frameworks including SwiftUI, AppKit, AVFoundation, CoreAudio, CoreFoundation, and CoreMedia. These are provided by macOS and the Xcode toolchain.
