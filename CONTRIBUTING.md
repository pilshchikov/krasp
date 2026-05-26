# Contributing

Krasp is early-stage macOS audio software. Please keep changes small, testable, and explicit about which part of the audio path they affect.

## Before Opening A Pull Request

```sh
make verify
make app
```

For changes that touch the HAL driver, also install the driver locally and confirm that `Krasp Microphone` still appears and produces audio.

## Areas To Be Careful With

- CoreAudio HAL contracts and property sizes.
- Shared-memory layout in `Shared/KraspSharedRing.h`.
- Bundle IDs and CoreAudio device UIDs.
- Signing, installation, and `coreaudiod` restart behavior.
- Any dependency or model licensing change.

## Reporting Issues

Include:

- macOS version and CPU architecture.
- Whether the app launches.
- Whether the virtual microphone appears in Sound settings.
- Whether Krasp is using `Hush neural 2026` or `Fallback DSP`.
- Any visible install or permission error.
