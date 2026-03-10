import SwiftUI

struct PostWorkoutAnalysisView: View {
    @Environment(WorkoutStore.self) var store
    let workoutId: UUID
    let routineName: String
    let sets: [WorkoutSet]
    let onDismiss: () -> Void

    @State private var analysis: AIAnalysisResult?
    @State private var loading = true
    @State private var error: String?
    @State private var suggestionStatuses: [String: String] = [:]  // exerciseName -> "accepted"/"rejected"

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if loading {
                loadingView
            } else if let error {
                errorView(error)
            } else if let analysis {
                analysisContent(analysis)
            }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.2)
            Text("Analyzing your workout...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.subtle)
            Text("AI is reviewing your performance")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
        }
        .task { await runAnalysis() }
    }

    // MARK: - Error

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(Color(hex: "ef4444"))
            Text("Analysis Failed")
                .font(.headline).foregroundColor(.white)
            Text(msg)
                .font(.caption).foregroundColor(Theme.subtle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("Done") { onDismiss() }
                .font(.headline).fontWeight(.bold)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Theme.accent)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
    }

    // MARK: - Analysis Content

    private func analysisContent(_ a: AIAnalysisResult) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI ANALYSIS")
                        .font(.system(size: 10, weight: .bold)).tracking(1.5)
                        .foregroundColor(Theme.subtle)
                    Text(routineName)
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(.white)
                }
                Spacer()
                Button {
                    Task { await refreshAnalysis() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.subtle)
                }
                .disabled(loading)
                ratingBadge(a.overallRating)
            }
            .padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 14) {
                    // Volume analysis
                    if let vol = a.volumeAnalysis {
                        volumeAnalysisCard(vol)
                    }

                    // Summary card
                    summaryCard(a.summary)

                    // Strengths & Weaknesses
                    if !a.strengths.isEmpty || !a.weaknesses.isEmpty {
                        strengthsWeaknessesCard(strengths: a.strengths, weaknesses: a.weaknesses)
                    }

                    // Plateau alerts
                    if let alerts = a.plateauAlerts, !alerts.isEmpty {
                        plateauAlertsCard(alerts)
                    }

                    // Next session targets
                    if let targets = a.nextSessionTargets, !targets.isEmpty {
                        nextSessionSection(targets)
                    }

                    // Suggestions
                    if !a.suggestions.isEmpty {
                        suggestionsSection(a.suggestions)
                    }

                    // Done button
                    Button {
                        onDismiss()
                    } label: {
                        Text("Done")
                            .font(.headline).fontWeight(.bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Theme.accent)
                            .foregroundColor(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Rating Badge

    private func ratingBadge(_ rating: String) -> some View {
        let (text, color) = ratingInfo(rating)
        return Text(text)
            .font(.system(size: 11, weight: .black))
            .foregroundColor(Color(hex: color))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(hex: color).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: color).opacity(0.4)))
    }

    private func ratingInfo(_ rating: String) -> (String, String) {
        switch rating {
        case "excellent":         return ("EXCELLENT", "22c55e")
        case "good":              return ("GOOD", "3b82f6")
        case "average":           return ("AVERAGE", "f59e0b")
        case "needs_improvement": return ("NEEDS WORK", "ef4444")
        default:                  return (rating.uppercased(), "94a3b8")
        }
    }

    // MARK: - Summary Card

    private func summaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text("Summary")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
            }
            Text(summary)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(hex: "e2e8f0"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Strengths & Weaknesses

    private func strengthsWeaknessesCard(strengths: [String], weaknesses: [String]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !strengths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Strengths", systemImage: "arrow.up.circle.fill")
                        .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                        .foregroundColor(Color(hex: "22c55e"))
                    ForEach(strengths, id: \.self) { s in
                        Text(s)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "e2e8f0"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !weaknesses.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Improve", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                        .foregroundColor(Color(hex: "f59e0b"))
                    ForEach(weaknesses, id: \.self) { w in
                        Text(w)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "e2e8f0"))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Suggestions

    private func suggestionsSection(_ suggestions: [AISuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "fbbf24"))
                Text("Suggestions for Next Session")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
            }
            .padding(.horizontal, 14)

            ForEach(suggestions) { s in
                suggestionRow(s)
            }
        }
    }

    private func suggestionRow(_ s: AISuggestion) -> some View {
        let status = suggestionStatuses[s.exerciseName]
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.exerciseName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text(s.actionLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: s.actionColor))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: s.actionColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Current -> Suggested
            HStack(spacing: 8) {
                let curW = s.currentWeight == 0 ? "BW" : "\(s.currentWeight.clean)kg"
                let sugW = s.suggestedWeight == 0 ? "BW" : "\(s.suggestedWeight.clean)kg"
                Text("\(curW) \u{00D7} \(s.currentReps)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.subtle)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.accent)
                Text("\(sugW) \u{00D7} \(s.suggestedReps)")
                    .font(.system(size: 13, weight: .black))
                    .foregroundColor(Theme.accent)
            }

            // Drop set recommendation
            if let dsW = s.dropSetWeight, let dsR = s.dropSetReps {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "a855f7"))
                    Text("Drop set: \(dsW.clean)kg \u{00D7} \(dsR) reps")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "a855f7"))
                }
            }

            Text(s.reason)
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            // Accept / Reject buttons
            if status == nil {
                HStack(spacing: 10) {
                    Button {
                        suggestionStatuses[s.exerciseName] = "accepted"
                        Task { await store.updateSuggestionStatus(id: s.id, status: "accepted") }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Accept")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Color(hex: "22c55e"))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        suggestionStatuses[s.exerciseName] = "rejected"
                        Task { await store.updateSuggestionStatus(id: s.id, status: "rejected") }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text("Skip")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(Theme.subtle)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                    }
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: status == "accepted" ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                    Text(status == "accepted" ? "Accepted" : "Skipped")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(status == "accepted" ? Color(hex: "22c55e") : Theme.muted)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Volume Analysis Card

    private func volumeAnalysisCard(_ vol: VolumeAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "3b82f6"))
                Text("Volume")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
            }
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text(formatVolume(vol.todayVolume))
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(Theme.accent)
                    Text("Today")
                        .font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                        .foregroundColor(Theme.muted)
                }
                if let prev = vol.previousVolume {
                    VStack(spacing: 2) {
                        Text(formatVolume(prev))
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(Theme.subtle)
                        Text("Previous")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                            .foregroundColor(Theme.muted)
                    }
                }
                if let pct = vol.changePct {
                    let isUp = pct >= 0
                    VStack(spacing: 2) {
                        HStack(spacing: 2) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%+.1f%%", pct))
                                .font(.system(size: 16, weight: .black))
                        }
                        .foregroundColor(Color(hex: isUp ? "22c55e" : "ef4444"))
                        Text("Change")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                            .foregroundColor(Theme.muted)
                    }
                }
                Spacer()
            }
            Text(vol.assessment)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "cbd5e1"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func formatVolume(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))"
    }

    // MARK: - Plateau Alerts Card

    private func plateauAlertsCard(_ alerts: [PlateauAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "ef4444"))
                Text("Plateau Alerts")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
            }
            ForEach(alerts) { alert in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(alert.exerciseName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Text("\(alert.sessionsStalled) sessions")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color(hex: "ef4444"))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(hex: "ef4444").opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(alert.suggestion)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "cbd5e1"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color(hex: "ef4444").opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "ef4444").opacity(0.3)))
        .padding(.horizontal, 14)
    }

    // MARK: - Next Session Targets

    private func nextSessionSection(_ targets: [NextSessionTarget]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "22c55e"))
                Text("Next Session Targets")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
            }
            .padding(.horizontal, 14)

            ForEach(targets) { t in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(t.exerciseName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(t.note)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    VStack(spacing: 2) {
                        let w = t.targetWeight == 0 ? "BW" : "\(t.targetWeight.clean)kg"
                        VStack(spacing: 1) {
                            Text("\(w)")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(Color(hex: "22c55e"))
                            Text("\u{00D7}\(t.targetReps)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(hex: "22c55e").opacity(0.8))
                        }
                        if let dsW = t.dropSetWeight, let dsR = t.dropSetReps {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 7, weight: .bold))
                                Text("\(dsW.clean)kg\u{00D7}\(dsR)")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(Color(hex: "a855f7"))
                        }
                    }
                }
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
                .padding(.horizontal, 14)
            }
        }
    }

    // MARK: - Data loading

    private func runAnalysis() async {
        let result = await store.requestAIAnalysis(
            workoutId: workoutId,
            routineName: routineName,
            sets: sets
        )
        if let result {
            analysis = result
        } else {
            error = "Could not analyze workout. Check your internet connection."
        }
        loading = false
    }

    private func refreshAnalysis() async {
        loading = true
        analysis = nil
        error = nil
        suggestionStatuses = [:]
        await store.deleteAnalysisCache(workoutId: workoutId)
        await runAnalysis()
    }
}
