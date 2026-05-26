# Architecture

Krasp has two cooperating runtime pieces:

- `Krasp.app`, the menu-bar app that owns microphone capture, denoising, preferences, and HAL installation.
- `KraspHAL.driver`, a CoreAudio AudioServerPlugIn that exposes the processed stream as an input device.

## Audio Pipeline

```text
AVCaptureDevice
  -> AVCaptureAudioDataOutput, mono float PCM
  -> NeuralNoiseSuppressor or AdaptiveNoiseSuppressor
  -> SharedMemoryVirtualMicrophoneSink
  -> /tmp/io.github.pilshchikov.krasp.audio
  -> KraspHAL.driver
  -> CoreAudio clients
```

The app writes processed samples into a fixed-size shared-memory ring buffer described by `Shared/KraspSharedRing.h`. The HAL driver maps that file read-only and serves frames to CoreAudio clients. If the app is not writing, the driver returns silence.

## Neural Processing

`NeuralNoiseSuppressor` dynamically loads `libdf.dylib` and the Hush ONNX bundle from the app resources. The current app-level capture and HAL sample rate is 48 kHz, while Hush operates at 16 kHz. Krasp uses a simple 3:1 downsampling and interpolation upsampling adapter around the neural frame processor.

If the model or runtime cannot load, `AudioCaptureController` falls back to `AdaptiveNoiseSuppressor` so the app can still produce a processed stream.

## HAL Driver

The HAL driver is intentionally small and static:

- One virtual device, `Krasp Microphone`.
- One input stream.
- Mono 32-bit float PCM.
- 48 kHz nominal sample rate.
- 512-frame buffer size.

The driver has no UI and no direct dependency on Swift code. Bundle metadata is in `HAL/KraspHAL/Info.plist`, and the C implementation is in `HAL/KraspHAL/KraspHAL.c`.

## Installation Model

The app embeds `KraspHAL.driver` inside its resources. `HALInstaller` copies that driver to `/Library/Audio/Plug-Ins/HAL`, fixes ownership and permissions, removes any older per-user install, and restarts CoreAudio.

This system-wide install path requires administrator approval. That is expected for HAL virtual audio devices on macOS.

## Identifiers

- App bundle ID: `io.github.pilshchikov.krasp`
- HAL bundle ID: `io.github.pilshchikov.krasp.hal`
- CoreAudio device UID: `io.github.pilshchikov.krasp.microphone`
- Shared ring path: `/tmp/io.github.pilshchikov.krasp.audio`
