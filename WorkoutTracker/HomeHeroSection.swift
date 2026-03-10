import SwiftUI

// MARK: - Hero Section
/// Top area of HomeView: today's routine, start workout/cardio buttons,
/// change chips, deload banners, pending sync, AI analysis of last workout.

struct HomeHeroSection: View {
    @Environment(WorkoutStore.self) var store

    @Binding var isRestDay: Bool
    let onStreakRecalc: () async -> Int
    @Binding var showSummarySheet: Bool
    @State private var lastAIAnalysis: AIAnalysisResult?
    @State private var lastAIWorkoutId: UUID?
    @State private var showCardioChoose = false

    var body: some View {
        VStack(spacing: 0) {
            heroCard
            if OfflineQueue.shared.pendingCount > 0 {
                pendingSyncBanner
            }
            if store.shouldSuggestDeload {
                deloadSuggestionBanner
            }
            if store.isDeloadWeek {
                deloadActiveBanner
            }
            // AI analysis of last workout
            if let ai = lastAIAnalysis, let wkId = lastAIWorkoutId {
                lastWorkoutAICard(ai, workoutId: wkId)
            }
        }
        .task { await loadLastAIAnalysis() }
    }

    // MARK: - Hero Card

    private static let dayOfWeekFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE"; return f
    }()

    private var dayOfWeek: String {
        Self.dayOfWeekFmt.string(from: Date())
    }

    private var defaultCardioType: CardioType {
        #if SONYA
        cardioTypes.first { $0.name == "Step Climbing" } ?? cardioTypes[0]
        #else
        cardioTypes.first { $0.name == "Indoor Cycling" } ?? cardioTypes[0]
        #endif
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Today")
                    .font(.caption2).fontWeight(.bold)
                    .textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
                Spacer()
            }

            Text(store.todayRoutineName)
                .font(.system(size: 34, weight: .black))
                .foregroundColor(store.todayRoutineName == "Rest" ? Theme.subtle : Theme.accent)

            Text(store.todayRoutineName == "Rest" ? "Recovery day" : dayOfWeek + " session")
                .font(.subheadline)
                .foregroundColor(Theme.subtle)

            Spacer().frame(height: 12)

            // Primary + Secondary buttons side by side
            HStack(spacing: 10) {
                if store.todayRoutineName != "Rest" {
                    if store.todayRoutineCompleted && store.activeWorkout == nil {
                        // Already completed today — show done state
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Completed")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Theme.accent.opacity(0.15))
                        .foregroundColor(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.3)))
                    } else {
                        Button {
                            if let routine = store.todayRoutine {
                                Task { await store.startWorkout(routine: routine) }
                            } else {
                                store.activeScreen = .choose
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 14, weight: .bold))
                                Text(store.activeWorkout != nil ? "Resume" : "Start Workout")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Theme.accent)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }

                Button {
                    Task { await store.startCardio(type: defaultCardioType) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: defaultCardioType.icon)
                            .font(.system(size: 14, weight: .bold))
                        Text("Start Cardio")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Theme.surface)
                    .foregroundColor(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent.opacity(0.4)))
                }
            }

            // Change chips row
            HStack(spacing: 8) {
                if store.todayRoutineName != "Rest" {
                    Button { store.activeScreen = .choose } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Change Workout")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Theme.subtle)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.bg)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                    }
                } else {
                    Button { store.activeScreen = .choose } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Start Workout")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Theme.subtle)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.bg)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.border))
                    }
                }

                Button { showCardioChoose = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Change Cardio")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(Theme.subtle)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.bg)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.border))
                }

                if store.todayRoutineName != "Rest" {
                    Button {
                        Task {
                            await store.toggleRestDay(date: Date())
                            isRestDay = store.restDays.contains(Calendar.current.startOfDay(for: Date()))
                            _ = await onStreakRecalc()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isRestDay ? "checkmark.circle.fill" : "moon.zzz")
                                .font(.system(size: 10, weight: .semibold))
                            Text("Rest")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(isRestDay ? Theme.accent : Theme.subtle)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(isRestDay ? Theme.accent.opacity(0.12) : Theme.bg)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(isRestDay ? Theme.accent.opacity(0.5) : Theme.border))
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 16)
        .padding(.top, statusBarHeight + 16)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Theme.surface, Color(hex: "263447")],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .overlay(Divider().frame(maxWidth: .infinity).background(Theme.border),
                 alignment: .bottom)
        .sheet(isPresented: $showCardioChoose) {
            cardioPickerSheet
        }
    }

    // MARK: - Cardio Picker Sheet

    private var cardioPickerSheet: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(cardioTypes) { ct in
                            Button {
                                showCardioChoose = false
                                Task { await store.startCardio(type: ct) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: ct.icon)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(Theme.accent)
                                        .frame(width: 36)
                                    Text(ct.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if ct.name == defaultCardioType.name {
                                        Text("DEFAULT")
                                            .font(.system(size: 9, weight: .bold)).tracking(0.5)
                                            .foregroundColor(Theme.accent)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Theme.accent.opacity(0.12))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Theme.muted)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                }
            }
            .navigationTitle("Choose Cardio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { showCardioChoose = false }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - AI Last Workout Analysis Card

    private func lastWorkoutAICard(_ ai: AIAnalysisResult, workoutId: UUID) -> some View {
        let (ratingText, ratingColor) = aiRatingInfo(ai.overallRating)
        return Button { store.activeScreen = .detail(workoutId) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(hex: "a855f7"))
                        Text("Last Workout AI Analysis")
                            .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                            .foregroundColor(Theme.subtle)
                    }
                    Spacer()
                    Text(ratingText)
                        .font(.system(size: 9, weight: .black)).tracking(0.5)
                        .foregroundColor(Color(hex: ratingColor))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color(hex: ratingColor).opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Text(ai.summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(hex: "e2e8f0"))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                // Key suggestions
                if !ai.suggestions.isEmpty {
                    Rectangle().fill(Theme.border).frame(height: 1)
                    VStack(spacing: 4) {
                        ForEach(ai.suggestions.prefix(4)) { s in
                            HStack(spacing: 4) {
                                Text(s.exerciseName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text(s.actionLabel)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Color(hex: s.actionColor))
                            }
                        }
                        if ai.suggestions.count > 4 {
                            Text("+\(ai.suggestions.count - 4) more")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.muted)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("View Full Analysis")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            .padding(14)
            .background(
                LinearGradient(
                    colors: [Color(hex: "8b5cf6").opacity(0.06), Theme.surface],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "8b5cf6").opacity(0.3)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private func aiRatingInfo(_ rating: String) -> (String, String) {
        switch rating {
        case "excellent":         return ("EXCELLENT", "22c55e")
        case "good":              return ("GOOD", "3b82f6")
        case "average":           return ("AVERAGE", "f59e0b")
        case "needs_improvement": return ("NEEDS WORK", "ef4444")
        default:                  return (rating.uppercased(), "94a3b8")
        }
    }

    // MARK: - Load last AI analysis

    private func loadLastAIAnalysis() async {
        // Fetch last finished strength workout directly (history may not be loaded yet)
        struct MinWorkout: Codable, Identifiable {
            let id: UUID
            let routineId: UUID?

            enum CodingKeys: String, CodingKey {
                case id
                case routineId = "routine_id"
            }
        }
        guard let rows: [MinWorkout] = await store.sb.tryGet(
            "workouts?select=id,routine_id" +
            "&finished_at=not.is.null&routine_id=not.is.null" +
            "&order=started_at.desc&limit=1"
        ), let lastWk = rows.first else { return }

        if let result = await store.loadExistingAnalysis(workoutId: lastWk.id) {
            lastAIAnalysis = result
            lastAIWorkoutId = lastWk.id
        }
    }

    // MARK: - Pending Sync Banner

    private var pendingSyncBanner: some View {
        let count = OfflineQueue.shared.pendingCount
        return HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 12, weight: .bold))
            Text("\(count) pending sync\(count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button {
                Task { await OfflineQueue.shared.flush() }
            } label: {
                Text("Retry")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(hex: "f59e0b"))
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
        }
        .foregroundColor(Color(hex: "f59e0b"))
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: "f59e0b").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "f59e0b").opacity(0.3)))
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // MARK: - Deload Suggestion Banner

    private var deloadSuggestionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(hex: "f59e0b"))
                Text("Deload Recommended")
                    .font(.system(size: 11, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Color(hex: "f59e0b"))
                Spacer()
                Text("Week \(store.weeksWithoutDeload)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "f59e0b").opacity(0.7))
            }

            Text("You've trained \(store.weeksWithoutDeload) weeks straight. Consider a deload: reduce sets by 50%, keep weight the same.")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "e2e8f0"))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.startDeloadWeek()
                    }
                } label: {
                    Text("Start Deload Week")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color(hex: "f59e0b"))
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        store.dismissDeloadSuggestion()
                    }
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Theme.surface)
                        .foregroundColor(Theme.subtle)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
            }
        }
        .padding(14)
        .background(Color(hex: "f59e0b").opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "f59e0b").opacity(0.3)))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Deload Active Banner

    private var deloadActiveBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.2.circlepath")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "38bdf8"))
            VStack(alignment: .leading, spacing: 2) {
                Text("DELOAD WEEK ACTIVE")
                    .font(.system(size: 10, weight: .bold)).tracking(1)
                    .foregroundColor(Color(hex: "38bdf8"))
                Text("Same weight, 50% fewer sets")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.subtle)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    store.endDeloadWeek()
                }
            } label: {
                Text("End")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: "38bdf8").opacity(0.15))
                    .foregroundColor(Color(hex: "38bdf8"))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "38bdf8").opacity(0.4)))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color(hex: "38bdf8").opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: "38bdf8").opacity(0.25)))
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
