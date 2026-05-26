# Security

Krasp processes microphone audio locally and does not intentionally transmit audio over the network.

## Reporting A Vulnerability

Please report security issues privately to the repository owner before opening a public issue. Include reproduction steps, affected macOS version, and whether the issue requires administrator privileges.

## Privileged Operations

Krasp requests administrator approval only to install or repair the CoreAudio HAL driver at:

```text
/Library/Audio/Plug-Ins/HAL/KraspHAL.driver
```

The app also restarts CoreAudio after driver installation so macOS can discover the virtual microphone.
