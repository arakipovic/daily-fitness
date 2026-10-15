import SwiftUI

struct RestTimerOverlay: View {
    let seconds: Int
    let onDismiss: () -> Void

    @State private var remaining: Int
    @State private var isRunning = true

    init(seconds: Int, onDismiss: @escaping () -> Void) {
        self.seconds = seconds
        self.onDismiss = onDismiss
        _remaining = State(initialValue: seconds)
    }

    var progress: Double {
        remaining <= 0 ? 1 : 1 - (Double(remaining) / Double(seconds))
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Rest Timer")
                    .font(.headline)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title2)
                }
            }

            ZStack {
                Circle()
                    .stroke(Color(.systemFill), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(remaining <= 10 ? Color.orange : Color.accentColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text(timeString(remaining))
                    .font(.system(size: 36, weight: .semibold, design: .monospaced))
                    .foregroundStyle(remaining <= 10 ? .orange : .primary)
            }
            .frame(width: 140, height: 140)

            HStack(spacing: 16) {
                Button("-15s") {
                    remaining = max(0, remaining - 15)
                }
                .buttonStyle(.bordered)

                Button(isRunning ? "Pause" : "Resume") {
                    isRunning.toggle()
                }
                .buttonStyle(.bordered)

                Button("+15s") {
                    remaining += 15
                }
                .buttonStyle(.bordered)
            }

            Button("Skip") {
                onDismiss()
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding()
        .shadow(radius: 20)
        .task {
            await runTimer()
        }
    }

    private func runTimer() async {
        while remaining > 0 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if isRunning {
                remaining -= 1
                if remaining == 0 {
                    onDismiss()
                }
            }
        }
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
