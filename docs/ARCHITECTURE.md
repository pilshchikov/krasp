# Architecture

Krasp has two cooperating runtime pieces:

- `Krasp.app`, the menu-bar app that owns microphone capture, denoising, preferences, and HAL installation.
- `KraspHAL.driver`, a CoreAudio AudioServerPlugIn that exposes the processed stream as an input device.

## Audio Pipeline

```text
AVCaptureDevice
  -> AVCaptureAudioDataOutput, mono float PCM
  -> DenoisingStream -> NeuralNoiseSuppressor, DPDFNet at 48 kHz
  -> SharedMemoryVirtualMicrophoneSink
  -> /tmp/io.github.pilshchikov.krasp.audio
  -> KraspHAL.driver
  -> CoreAudio clients
```

The app writes processed samples into a fixed-size shared-memory ring buffer described by `Shared/KraspSharedRing.h`. The HAL driver maps that file read-only and serves frames to CoreAudio clients. If the app is not writing, the driver returns silence.

## Neural Processing

`NeuralNoiseSuppressor` loads the pinned sherpa-onnx 1.13.8 C API through `CDPDFNet`. The `dpdfnet2_48khz_hr.onnx` model and ONNX Runtime ship in the app resources. Capture, model processing, playback monitoring, and the virtual microphone all use mono 48 kHz audio. No Apple voice processing is enabled.

`DenoisingStream` collects 480-sample model hops. The runtime withholds its first hop and then returns audio beginning at the start of the input stream. A fixed 959-sample output delay, about 20 ms, accommodates that warmup and arbitrary capture block boundaries. This excludes device and HAL latency. Original audio follows the same timeline before blending or listening comparison. Warmup produces silence; missing or invalid later output stops processing.

Suppression maps 0...100% to 0...60 dB using an original-signal weight of `10^(-dB/20)`. At 100%, the original weight is exactly zero. Weight changes ramp over one hop. The runtime's offline attenuation field does not control streaming, so Krasp applies this limit to aligned waveforms. There is no automatic gain compensation. The separate Output slider applies manual gain with a full-scale clamp.

Reset clears the runtime's recurrent state and all Swift audio queues. Missing assets or processing errors are reported instead of silently selecting a different processor.

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
