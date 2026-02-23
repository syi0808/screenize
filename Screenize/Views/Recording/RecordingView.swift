import SwiftUI

/// Main recording view (V1 style)
struct RecordingView: View {

    @ObservedObject var appState: AppState

    var body: some View {
        ZStack {
            // Main content
            if appState.selectedTarget != nil {
                RecordingPreviewView(appState: appState)
            } else {
                EmptyStateView(appState: appState)
            }

            // Recording overlay (bottom-right)
            if appState.isRecording {
                RecordingOverlay(appState: appState)
            }

            // Bottom control bar
            VStack {
                Spacer()
                RecordingControlBar(appState: appState)
                    .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .overlay(alignment: .topTrailing) {
            ShortcutHelpButton(context: .recording)
                .padding()
        }
        .sheet(isPresented: $appState.showSourcePicker) {
            SourcePickerView(appState: appState)
        }
        .alert("Error", isPresented: .init(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("OK") {
                appState.errorMessage = nil
            }
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }
}

// MARK: - Empty State View

private struct EmptyStateView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        DesignEmptyState(
            icon: "display",
            title: "No Source Selected",
            subtitle: "Select a display or window to start recording",
            iconSize: 64,
            actionLabel: "Select Source"
        ) {
            appState.showSourcePicker = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignColors.windowBackground)
    }
}

// MARK: - Recording Overlay (bottom-right)

private struct RecordingOverlay: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                RecordingIndicator(
                    duration: appState.recordingDuration,
                    isPaused: appState.isPaused
                )
                .padding()
            }
        }
    }
}

private struct RecordingIndicator: View {
    let duration: TimeInterval
    let isPaused: Bool
    @State private var isBlinking = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .opacity(isBlinking ? 0.5 : 1.0)
                .animation(AnimationTokens.pulse, value: isBlinking)

            Text(formattedDuration)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.white)

            if isPaused {
                Text("PAUSED")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(DesignColors.overlay.opacity(DesignOpacity.strong))
        .cornerRadius(CornerRadius.lg)
        .onAppear {
            isBlinking = true
        }
    }

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Control Bar

private struct RecordingControlBar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 20) {
            // Home button (return to welcome screen, hidden during recording)
            if !appState.isRecording {
                Button {
                    appState.returnToWelcome()
                } label: {
                    Image(systemName: "house")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Return to Home")
            }

            // Source info (click to change)
            Button {
                appState.showSourcePicker = true
            } label: {
                HStack {
                    Image(systemName: sourceIcon)
                    Text(appState.selectedTarget?.displayName ?? "No Source")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(appState.isRecording)

            Spacer()

            // Recording time (only during recording)
            if appState.isRecording {
                HStack(spacing: 8) {
                    RecordingDot()

                    Text(formattedDuration)
                        .font(.system(.body, design: .monospaced))

                    if appState.isPaused {
                        Text("PAUSED")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Control buttons
            HStack(spacing: 12) {
                // Button to open the editor (when not recording and previous recording exists)
                if !appState.isRecording && appState.hasRecording {
                    Button {
                        appState.showEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "slider.horizontal.3")
                            Text("Edit")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.borderless)
                    .help("Open Editor")
                }

                if appState.isRecording {
                    // Pause/Resume button
                    Button {
                        appState.togglePause()
                    } label: {
                        Image(systemName: appState.isPaused ? "play.fill" : "pause.fill")
                            .font(.title2)
                    }
                    .buttonStyle(.borderless)
                    .help(appState.isPaused ? "Resume" : "Pause")

                    // Stop button
                    Button {
                        Task {
                            await appState.stopRecording()
                        }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Stop Recording")
                } else {
                    // Record button
                    Button {
                        Task {
                            await appState.startRecordingWithCountdown()
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 12, height: 12)
                            Text("Record")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.borderless)
                    .disabled(appState.selectedTarget == nil || appState.isCountingDown)
                    .help("Start Recording (⌘⇧2)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private var sourceIcon: String {
        guard let target = appState.selectedTarget else { return "display" }
        switch target {
        case .display: return "display"
        case .window: return "macwindow"
        case .region: return "rectangle.dashed"
        }
    }

    private var formattedDuration: String {
        let duration = appState.recordingDuration
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Recording Dot

private struct RecordingDot: View {
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 10, height: 10)
            .opacity(isAnimating ? 0.5 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Preview

#Preview("No Source") {
    RecordingView(appState: AppState.shared)
}
