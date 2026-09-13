# Development

## Setup

Install the required toolchains:

```sh
xcode-select --install
```

Then build the app:

```sh
make app
```

The first neural build downloads DPDFNet and the universal macOS sherpa-onnx runtime into `ThirdParty/DPDFNet/`. `Scripts/prepare-dpdfnet.sh` verifies pinned SHA-256 checksums before installing the assets. The cache is ignored by git; `make neural` recreates it. Rust is not required.

## Common Commands

```sh
make build       # Swift executable only
make hal         # HAL driver only
make neural      # Verified DPDFNet model and native runtime
make app         # Full app bundle
make dist        # Release installer package plus SHA-256 checksum
make verify      # Unit tests, real-model integration test, and HAL checks
make clean       # Remove Swift build output
```

## Local Testing

1. Run `make app`.
2. Open `.build/release/Krasp.app`.
3. Install or repair the virtual microphone from the menu-bar UI.
4. Open macOS Sound settings and confirm `Krasp Microphone` appears as an input.
5. Select the physical microphone in Krasp, enable cancellation, then select `Krasp Microphone` in a recording app.

When testing HAL changes, restart CoreAudio after reinstalling:

```sh
sudo killall coreaudiod
```

## Notes

- Generated build output belongs in `.build/` or `dist/`.
- Third-party source and model downloads stay out of git.
- Keep `Shared/KraspSharedRing.h` in sync with the Swift shared-memory writer.
- Avoid changing CoreAudio device identifiers after public release unless you intentionally want macOS to see a different virtual device.
