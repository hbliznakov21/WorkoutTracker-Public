import SwiftUI

struct PRsView: View {
    @Environment(WorkoutStore.self) var store
    @State private var prs: [PREntry] = []
    @State private var loading = true
    @State private var filter  = "All"
    @State private var errorText: String?

    struct PREntry: Identifiable {
        let id = UUID()
        let exercise: String
        let muscle:   String
        let weight:   Double
        let reps:     Int
        let date:     Date
    }

    var muscles: [String] { ["All"] + Array(Set(prs.map(\.muscle).filter { !$0.isEmpty })).sorted() }
    var filtered: [PREntry] { filter == "All" ? prs : prs.filter { $0.muscle == filter } }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                if loading {
                    Spacer(); ProgressView().tint(Theme.accent); Spacer()
                } else if let errorText {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundColor(.orange)
                        Text(errorText).font(.caption).foregroundColor(Theme.subtle).multilineTextAlignment(.center)
                        Button("Retry") { Task { await loadPRs() } }
                            .font(.subheadline.bold()).foregroundColor(Theme.accent)
                    }.padding()
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(muscles, id: \.self) { m in
                                Button { filter = m } label: {
                                    Text(m).font(.caption).fontWeight(.semibold)
                                        .padding(.horizontal, 14).padding(.vertical, 6)
                                        .background(filter == m ? Theme.accent : Color.clear)
                                        .foregroundColor(filter == m ? .black : Theme.subtle)
                                        .clipShape(Capsule())
                                        .overlay(Capsule().stroke(
                                            filter == m ? Color.clear : Theme.border))
                                }
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filtered) { pr in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pr.exercise).font(.subheadline).fontWeight(.semibold)
                                        Text(pr.muscle).font(.caption).foregroundColor(Theme.subtle)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(pr.weight == 0 ? "\(pr.reps) reps" : "\(pr.weight.clean)kg×\(pr.reps)")
                                            .font(.system(size: 15, weight: .black))
                                            .foregroundColor(Theme.accent)
                                        Text(dateLabel(pr.date)).font(.caption)
                                            .foregroundColor(Theme.subtle)
                                    }
                                    Image(systemName: "chart.line.uptrend.xyaxis")
                                        .font(.system(size: 13))
                                        .foregroundColor(Theme.border)
                                        .padding(.leading, 8)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 13)
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel("\(pr.exercise), \(pr.muscle), \(pr.weight == 0 ? "\(pr.reps) reps" : "\(pr.weight.clean) kg times \(pr.reps)"), \(dateLabel(pr.date))")
                                .accessibilityAddTraits(.isButton)
                                .onTapGesture { store.activeScreen = .progress(pr.exercise) }
                                if pr.id != filtered.last?.id {
                                    Divider().padding(.leading, 16).background(Theme.border)
                                }
                            }
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .padding(14)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .prs) }
        .task { await loadPRs() }
        .navigationTitle("PRs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = .home } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func loadPRs() async {
        struct SetRow: Decodable {
            let exercise_name: String
            let weight_kg: Double
            let reps: Int
            let logged_at: Date
            let exercises: ExRow?
            struct ExRow: Decodable { let muscle_group: String? }

            var e1rm: Double {
                if weight_kg == 0 { return Double(reps) } // bodyweight: use reps as score
                if reps == 1 { return weight_kg }
                return weight_kg * (1 + Double(reps) / 30.0) // Epley formula
            }
        }
        do {
            let rows: [SetRow] = try await SupabaseClient.shared.get(
                "workout_sets?select=exercise_name,weight_kg,reps,logged_at,exercises(muscle_group)" +
                "&order=logged_at.desc"
            )
            var best: [String: (row: SetRow, e1rm: Double)] = [:]
            for r in rows {
                let score = r.e1rm
                if let existing = best[r.exercise_name] {
                    if score > existing.e1rm {
                        best[r.exercise_name] = (r, score)
                    }
                } else {
                    best[r.exercise_name] = (r, score)
                }
            }
            prs = best.values.map { entry in
                PREntry(
                    exercise: entry.row.exercise_name,
                    muscle:   entry.row.exercises?.muscle_group ?? "",
                    weight:   entry.row.weight_kg,
                    reps:     entry.row.reps,
                    date:     entry.row.logged_at
                )
            }.sorted { $0.weight > $1.weight }
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    private static let dMMMFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private func dateLabel(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d)     { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        return Self.dMMMFmt.string(from: d)
    }

}
