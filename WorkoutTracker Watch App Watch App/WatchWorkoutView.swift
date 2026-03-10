import SwiftUI
import WatchKit

struct WatchWorkoutView: View {
    @Environment(WatchStore.self) var store
    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    @State private var elapsed = "0:00"
    @State private var elapsedTimer: Timer?
    @State private var restTimer: Timer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if isLuminanceReduced {
                alwaysOnView
            } else if store.restSeconds > 0 {
                restView.transition(.opacity)
            } else {
                workoutView.transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.restSeconds > 0)
        .onAppear { startElapsedTimer() }
        .onDisappear { elapsedTimer?.invalidate(); restTimer?.invalidate() }
        .onChange(of: isLuminanceReduced) { _, dimmed in
            if dimmed {
                elapsedTimer?.invalidate()
            } else {
                updateElapsed()
                startElapsedTimer()
            }
        }
        .onChange(of: store.restSeconds) { old, new in
            // Start countdown when rest begins or is reset to a larger value from phone
            if new > 0 && (old == 0 || new > old + 2) {
                WKInterfaceDevice.current().play(.start)
                startRestCountdown()
            }
        }
    }

    // MARK: - Always-On Display (wrist lowered)

    private var alwaysOnView: some View {
        VStack(spacing: 6) {
            Text(elapsed)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
            if store.restSeconds > 0 {
                Text("REST  \(fmtSecs(store.restSeconds))")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.green)
            } else {
                Text(store.exerciseName.isEmpty ? "Workout" : store.exerciseName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if store.heartRate > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.red)
                    Text("\(Int(store.heartRate))")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rest View

    private var restView: some View {
        VStack(spacing: 0) {
            Text("REST")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundColor(.gray)
                .padding(.top, 8)

            Spacer()

            Text(fmtSecs(store.restSeconds))
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundColor(restColor)
                .monospacedDigit()

            Spacer()

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.15))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(restColor)
                        .frame(
                            width: max(0, geo.size.width * CGFloat(store.restSeconds) / CGFloat(max(store.totalRestSeconds, 1))),
                            height: 4
                        )
                        .animation(.linear(duration: 0.95), value: store.restSeconds)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)

            HStack(spacing: 12) {
                Text(store.exerciseName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button {
                    WKInterfaceDevice.current().play(.click)
                    store.restSeconds = 0
                    store.restEndTime = 0
                    restTimer?.invalidate()
                    WatchConnectivityManager.shared.sendRestSkip()
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var restColor: Color {
        store.restSeconds <= 5 ? .red : store.restSeconds <= 15 ? .orange : .green
    }

    // MARK: - Workout View

    private var workoutView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // Routine name + elapsed
                HStack {
                    Text(store.routineName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.green)
                        .lineLimit(1)
                    Spacer()
                    Text(elapsed)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.gray)
                }
                .padding(.bottom, 6)

                Divider().overlay(Color.green.opacity(0.25))
                    .padding(.bottom, 8)

                // Current exercise
                Text(store.exerciseName.isEmpty ? "Starting…" : store.exerciseName)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.bottom, 4)

                // Set · weight × reps
                if store.targetSets > 0 {
                    HStack(spacing: 0) {
                        Text("Set \(store.setIndex)/\(store.targetSets)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                        Text("  ·  ")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text("\(store.weight.clean)kg × \(store.reps)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.bottom, 8)
                }

                Divider().padding(.bottom, 8)

                // Heart rate + calories
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 10))
                            Text(store.heartRate > 0 ? "\(Int(store.heartRate))" : "—")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.red)
                        }
                        Text("BPM")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        HStack(spacing: 3) {
                            Text(store.activeCalories > 0 ? "\(Int(store.activeCalories))" : "—")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.yellow)
                            Image(systemName: "flame.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 10))
                        }
                        Text("KCAL")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                    }
                }

                // Next exercise
                if !store.nextExerciseName.isEmpty {
                    Divider().padding(.vertical, 6)
                    HStack(spacing: 4) {
                        Text("NEXT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text(store.nextExerciseName)
                            .font(.system(size: 11))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Timers

    private func updateElapsed() {
        guard let start = WatchStore.shared.workoutStartTime else { return }
        let s = Int(Date().timeIntervalSince(start))
        elapsed = "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func startElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                self.updateElapsed()
            }
        }
    }

    private func startRestCountdown() {
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                let remaining = max(0, Int(WatchStore.shared.restEndTime - Date().timeIntervalSince1970))
                WatchStore.shared.restSeconds = remaining
                if remaining == 0 {
                    // Three strong notification haptics — the strongest pattern on watchOS
                    WKInterfaceDevice.current().play(.notification)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        WKInterfaceDevice.current().play(.notification)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            WKInterfaceDevice.current().play(.notification)
                        }
                    }
                    self.restTimer?.invalidate()
                } else if remaining <= 3 {
                    WKInterfaceDevice.current().play(.click)
                }
            }
        }
    }

    private func fmtSecs(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

extension Double {
    var clean: String {
        truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(self))" : String(format: "%.1f", self)
    }
}
