# Release

Krasp currently produces an unsigned macOS `.pkg` installer containing an ad-hoc signed app bundle. This is enough for developer testing and GitHub Actions artifacts, but not enough for a polished public installer.

## Prepare A Local Release Build

```sh
make clean
make dist VERSION=2026.1.1 BUILD_NUMBER=1
```

The output is:

```text
dist/Krasp-2026.1.1-macos-<arch>.pkg
dist/Krasp-2026.1.1-macos-<arch>.pkg.sha256
```

## GitHub Actions

The `Build macOS` workflow runs on app-affecting pushes to `master`, app-affecting pull requests, manual dispatches, and version tags. It builds the app bundle, packages it as a `.pkg` installer, uploads the installer/checksum as workflow artifacts, and publishes a GitHub prerelease for successful `master` app builds.

Automatic `master` prereleases use tags like `build-2026.1.<run-number>`. Version tags like `v2026.1.1` create tagged prereleases.

Docs-only, README-only, metadata-only, and workflow-only pushes do not rebuild the app package.

Create a versioned release tag:

```sh
git tag v2026.1.1
git push origin v2026.1.1
```

## Production Signing And Notarization

Before promoting Krasp as an end-user release, add a Developer ID signing path:

1. Sign `KraspHAL.driver`, `libdf.dylib`, and `Krasp.app` with a Developer ID Application certificate.
2. Sign the installer package or wrap the app in a signed DMG.
3. Submit the artifact to Apple notarization.
4. Staple the notarization ticket.
5. Update the GitHub workflow to use repository secrets for signing identity and notarization credentials.

Until that is done, release notes should clearly call artifacts developer builds.

## Release Checklist

- `make verify` passes.
- `make dist VERSION=2026.x.<build> BUILD_NUMBER=<build>` passes.
- `Krasp.app` launches on a clean macOS 14 or newer machine.
- Virtual microphone install, repair, and uninstall paths work.
- `Krasp Microphone` appears in Sound settings and receives processed audio.
- `THIRD_PARTY_NOTICES.md` is still accurate for bundled model/runtime versions.
