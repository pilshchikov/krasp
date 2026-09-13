# Third-party notices

Krasp bundles the following components during `make app`. License texts are included in the app's `Contents/Resources/Licenses` directory.

| Component | Source | License |
|---|---|---|
| DPDFNet `dpdfnet2_48khz_hr.onnx` | https://github.com/ceva-ip/DPDFNet | Apache-2.0 |
| sherpa-onnx 1.13.8 native runtime and vendored C header | https://github.com/k2-fsa/sherpa-onnx/tree/v1.13.8 | Apache-2.0 |
| ONNX Runtime 1.28.2, supplied with sherpa-onnx | https://github.com/microsoft/onnxruntime/tree/v1.28.2 | MIT, plus bundled third-party notices |

The model is the streaming export published in sherpa-onnx's `speech-enhancement-models` release. Both the model and runtime archive are pinned by SHA-256 in `Scripts/prepare-dpdfnet.sh`. The unmodified upstream C header and its license are in `Sources/CDPDFNet/vendor`.

Krasp uses Apple system frameworks including SwiftUI, AppKit, AVFoundation, CoreAudio, CoreFoundation, and CoreMedia, supplied by macOS and Xcode. It does not enable Apple's voice-processing mode.
