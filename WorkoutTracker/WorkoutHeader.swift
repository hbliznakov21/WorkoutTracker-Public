import SwiftUI

// MARK: - Workout Header
/// Top bar of ActiveWorkoutView showing sets count, volume, elapsed time,
/// heart rate/calories, and the Finish button.

struct WorkoutHeader: View {
    @Environment(WorkoutStore.self) var store

    let elapsed: String
    @Binding var showFinishAlert: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(store.totalSetsLogged)").font(.title2).fontWeight(.black).foregroundColor(Theme.accent)
                    Text("SETS").font(.system(size: 9, weight: .bold)).foregroundColor(Theme.subtle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(store.totalSetsLogged) sets logged")
                VStack(alignment: .leading, spacing: 2) {
                    Text(formattedVolume).font(.title2).fontWeight(.black).foregroundColor(Theme.accent)
                    Text("KG VOL").font(.system(size: 9, weight: .bold)).foregroundColor(Theme.subtle)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(formattedVolume) kilograms total volume")
                .padding(.leading, 16)
                Spacer()
                Text(elapsed).font(.system(size: 18, weight: .black)).foregroundColor(Theme.subtle)
                Spacer()
                Button {
                    showFinishAlert = true
                } label: {
                    Text("Finish")
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color(hex: "ef4444"))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, statusBarHeight + 10)
            .padding(.bottom, store.liveHeartRate > 0 ? 6 : 10)

            if store.liveHeartRate > 0 {
                HStack(spacing: 16) {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "ef4444"))
                        Text("\(Int(store.liveHeartRate)) bpm")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "ef4444"))
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "fbbf24"))
                        Text("\(Int(store.liveCalories)) kcal")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "fbbf24"))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(Theme.bg)
        .overlay(Divider(), alignment: .bottom)
        .animation(.easeInOut(duration: 0.3), value: store.liveHeartRate > 0)
    }

    private var formattedVolume: String {
        store.totalVolume >= 1000
            ? String(format: "%.1fk", store.totalVolume / 1000)
            : "\(Int(store.totalVolume))"
    }
}
