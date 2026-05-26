# Development

## Setup

Install the required toolchains:

```sh
xcode-select --install
rustup default stable
```

Then build the app:

```sh
make app
```

The first neural build downloads the Hush model into `ThirdParty/Hush/` and clones DeepFilterNet into `ThirdParty/DeepFilterNet/`. Those paths are ignored by git and can be deleted at any time; `make neural` recreates them.

## Common Commands

```sh
make build       # Swift executable only
make hal         # HAL driver only
make neural      # Hush model plus libDF.dylib
make app         # Full app bundle
make dist        # Release installer package plus SHA-256 checksum
make verify      # Fast source/build sanity checks
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
