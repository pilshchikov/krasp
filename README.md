# Krasp

Krasp is a macOS menu-bar app that turns a physical microphone into a local noise-cancelled virtual microphone named `Krasp Microphone`.

It captures audio from the selected input device, runs local speech enhancement, and publishes the processed mono 48 kHz PCM stream through a CoreAudio HAL plug-in. Audio processing is local; Krasp does not send microphone audio to a server.

## Features

- Menu-bar SwiftUI app for microphone selection, enable/disable, suppression level, and live meters.
- CoreAudio HAL virtual input device named `Krasp Microphone`.
- Shared-memory PCM ring buffer between the menu-bar app and HAL plug-in.
- Hush neural speech enhancement as the primary denoiser.
- Adaptive high-pass/noise-gate fallback when the neural runtime or model cannot load.
- Ad-hoc signed local app bundle and macOS installer package target.

## Requirements

- macOS 14 or newer.
- Xcode command-line tools with Swift 6.1 support.
- Rust toolchain with Cargo.
- Internet access for the first neural build, which downloads Hush and clones DeepFilterNet.

## Build

```sh
make app
```

The app bundle is written to:

```text
.build/release/Krasp.app
```

Run it locally:

```sh
make run
```

Build a distributable installer package and checksum:

```sh
make dist
```

Artifacts are written to `dist/` as a `.pkg` installer and `.sha256` checksum.

## Install The Virtual Microphone

1. Build and launch Krasp with `make run`.
2. Click `Install` in the Virtual Microphone row.
3. Approve the macOS administrator prompt.
4. Select `Krasp Microphone` as the input device in your conferencing or recording app.

The installer copies the embedded HAL driver to:

```text
/Library/Audio/Plug-Ins/HAL/KraspHAL.driver
```

and restarts CoreAudio so macOS can discover the new virtual microphone.

For development, the HAL driver can also be installed from the terminal:

```sh
make install-hal
```

Uninstall it with:

```sh
make uninstall-hal
```

## How It Works

Krasp captures microphone frames through `AVCaptureSession`. The audio path is:

```text
physical microphone -> Krasp app -> Hush/DeepFilterNet or fallback DSP -> shared ring buffer -> KraspHAL -> Krasp Microphone
```

Hush runs at 16 kHz with 10 ms neural frames. Krasp downsamples 48 kHz capture frames to 16 kHz, processes them, then upsamples the enhanced frames back to 48 kHz for the virtual microphone.

See [Architecture](docs/ARCHITECTURE.md) for more detail.

## Release Status

This repository is prepared for public source publication and unsigned/ad-hoc build artifacts. A production release still needs Developer ID signing and Apple notarization before most end users can install it without warnings.

Release workflow notes are in [Release](docs/RELEASE.md).

## Third-Party Components

- Hush model by Weya AI, Apache-2.0.
- DeepFilterNet/libDF by the DeepFilterNet authors, Apache-2.0 or MIT.

See [Third Party Notices](THIRD_PARTY_NOTICES.md).

## License

Krasp source code is released under the MIT License. See [LICENSE](LICENSE).
