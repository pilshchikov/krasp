import AppKit
import SwiftUI

struct AppMenuView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            virtualMicrophone
            Divider()
            controls
            meters
            footer
        }
        .padding(16)
        .task {
            await appState.prepare()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.isEnabled ? "waveform.circle.fill" : "waveform.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(appState.isEnabled ? .green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Krasp")
                    .font(.headline)
                Text(appState.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: $appState.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!appState.canRun)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Microphone")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Microphone", selection: selectedDeviceBinding) {
                if appState.devices.isEmpty {
                    Text("No microphones found").tag("")
                } else {
                    ForEach(appState.devices) { device in
                        Text(device.displayName).tag(device.uid)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(appState.devices.isEmpty)

            HStack(spacing: 10) {
                Text("Suppression")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Slider(value: $appState.suppressionAmount, in: 0.25...1.0)
                    .disabled(!appState.canRun)

                Text("\(Int(appState.suppressionAmount * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 8) {
                Image(systemName: appState.processorName == "Fallback DSP" ? "exclamationmark.triangle" : "brain.head.profile")
                    .foregroundStyle(appState.processorName == "Fallback DSP" ? .orange : .green)
                Text(appState.processorName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var virtualMicrophone: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: virtualMicrophoneIcon)
                    .foregroundStyle(virtualMicrophoneColor)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Virtual Microphone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(appState.virtualMicrophoneState.title)
                        .font(.caption)
                        .lineLimit(2)
                }

                Spacer()

                Button {
                    appState.installVirtualMicrophone()
                } label: {
                    if appState.virtualMicrophoneState.isInstalling {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Installing")
                        }
                    } else {
                        Label(
                            appState.virtualMicrophoneState.actionTitle,
                            systemImage: appState.virtualMicrophoneState == .installed ? "arrow.triangle.2.circlepath" : "square.and.arrow.down"
                        )
                    }
                }
                .help(appState.virtualMicrophoneState.actionTitle)
                .disabled(appState.virtualMicrophoneState.isInstalling)
            }

            if case let .failed(message) = appState.virtualMicrophoneState {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var virtualMicrophoneIcon: String {
        switch appState.virtualMicrophoneState {
        case .installed:
            return "checkmark.circle.fill"
        case .needsUpdate:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .installing:
            return "clock"
        case .missing:
            return "exclamationmark.circle"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    private var virtualMicrophoneColor: Color {
        switch appState.virtualMicrophoneState {
        case .installed:
            return .green
        case .needsUpdate:
            return .orange
        case .installing:
            return .secondary
        case .missing:
            return .orange
        case .failed:
            return .red
        }
    }

    private var meters: some View {
        VStack(alignment: .leading, spacing: 8) {
            MeterRow(title: "Input", value: appState.inputLevel, color: .blue)
            MeterRow(title: "Reduction", value: appState.reductionLevel, color: .green)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                Task { await appState.refreshDevices() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Sound.prefPane"))
            } label: {
                Image(systemName: "speaker.wave.2")
            }
            .help("Open Sound settings")
            .buttonStyle(.borderless)

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .help("Quit Krasp")
            .buttonStyle(.borderless)
        }
    }

    private var selectedDeviceBinding: Binding<String> {
        Binding(
            get: { appState.selectedDeviceUID ?? "" },
            set: { appState.selectedDeviceUID = $0.isEmpty ? nil : $0 }
        )
    }
}

private struct MeterRow: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(4, proxy.size.width * value))
                }
            }
            .frame(height: 8)
        }
    }
}
