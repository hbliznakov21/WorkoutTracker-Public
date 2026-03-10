import SwiftUI

struct ReportsView: View {
    @Environment(WorkoutStore.self) var store

    @State private var weekStats: [WorkoutWeekStats] = []
    @State private var lastWeekVol: Double = 0
    @State private var recoveryData: [MuscleRecovery] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    HomeAnalyticsSection(
                        weekStats: weekStats,
                        lastWeekVol: lastWeekVol,
                        recoveryData: recoveryData
                    )
                }
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
        }
        .task {
            async let ws = store.loadWeekData()
            async let lwv = store.loadLastWeekVolume()
            async let rec = store.loadRecovery()
            weekStats = await ws
            lastWeekVol = await lwv
            recoveryData = await rec
            loading = false
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = .home } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Home")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }
}
