import SwiftUI

struct ActiveCardioView: View {
    @Environment(WorkoutStore.self) var store
    @State private var elapsed = 0
    @State private var timer: Timer?
    @State private var showDiscard = false

    private var activityName: String { store.activeWorkout?.routineName ?? "Cardio" }

    private var cardioIcon: String {
        let n = activityName.lowercased()
        if n.contains("cycl") || n.contains("bike")                      { return "figure.indoor.cycle" }
        if n.contains("treadmill") || (n.contains("indoor") && n.contains("run")) { return "figure.run" }
        if n.contains("run")                                              { return "figure.run" }
        if n.contains("step") || n.contains("stair")                     { return "figure.stair.stepper" }
        if n.contains("elliptical")                                       { return "figure.elliptical" }
        if n.contains("row")                                              { return "oar.2.crossed" }
        if n.contains("walk")                                             { return "figure.walk" }
        return "figure.run"
    }

    private var fmtElapsed: String {
        let h = elapsed / 3600
        let m = (elapsed % 3600) / 60
        let s = elapsed % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Icon + name
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "38bdf8").opacity(0.12))
                            .frame(width: 96, height: 96)
                        Image(systemName: cardioIcon)
                            .font(.system(size: 44, weight: .light))
                            .foregroundColor(Color(hex: "38bdf8"))
                    }
                    Text(activityName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(hex: "e2e8f0"))
                }

                Spacer()

                // Elapsed time
                VStack(spacing: 6) {
                    Text(fmtElapsed)
                        .font(.system(size: 62, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .monospacedDigit()
                    Text("ELAPSED")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.5)
                        .foregroundColor(Color(hex: "475569"))
                }

                Spacer()

                // Live stats
                HStack(spacing: 0) {
                    liveStatCell(
                        icon:  "heart.fill",
                        value: store.liveHeartRate > 0 ? "\(Int(store.liveHeartRate))" : "—",
                        label: "BPM",
                        color: Color(hex: "ef4444")
                    )
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 1, height: 52)
                    liveStatCell(
                        icon:  "flame.fill",
                        value: store.liveCalories > 0 ? "\(Int(store.liveCalories))" : "—",
                        label: "KCAL",
                        color: Color(hex: "fbbf24")
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
                .padding(.horizontal, 16)

                Spacer()

                // Finish
                Button {
                    timer?.invalidate()
                    Task { await store.finishCardio() }
                } label: {
                    Text("FINISH")
                        .font(.headline).fontWeight(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.accent)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)

                Button { showDiscard = true } label: {
                    Text("Discard session")
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "ef4444").opacity(0.6))
                        .padding(.vertical, 12)
                }

                Spacer().frame(height: 8)
            }
        }
        .onAppear {
            if let start = store.workoutStartTime {
                elapsed = Int(Date().timeIntervalSince(start))
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in elapsed += 1 }
            }
        }
        .onDisappear { timer?.invalidate() }
        .confirmationDialog(
            "Discard this cardio session?",
            isPresented: $showDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive) {
                timer?.invalidate()
                Task { await store.discardWorkout() }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func liveStatCell(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text(value)
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(color)
            }
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundColor(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
    }
}
