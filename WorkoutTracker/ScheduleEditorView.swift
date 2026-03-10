import SwiftUI

struct ScheduleEditorView: View {
    @Environment(WorkoutStore.self) var store

    private let days = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private var routineOptions: [String] {
        var names = store.routines.map(\.name)
        names.insert("Rest", at: 0)
        return names
    }

    /// Days that have the same non-Rest routine assigned more than expected.
    /// PPL repeats are normal (Push Mon/Thu, etc.) so we only flag if a routine
    /// appears 3+ times — likely a mistake.
    private var overusedRoutines: Set<String> {
        var counts: [String: Int] = [:]
        for day in days {
            let r = store.schedule[day] ?? "Rest"
            guard r != "Rest" else { continue }
            counts[r, default: 0] += 1
        }
        return Set(counts.filter { $0.value >= 3 }.keys)
    }

    private func isOverused(day: String) -> Bool {
        let r = store.schedule[day] ?? "Rest"
        return overusedRoutines.contains(r)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            List {
                if !overusedRoutines.isEmpty {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(Color(hex: "f59e0b"))
                            Text("A routine is scheduled 3+ days — check for duplicates.")
                                .font(.caption).foregroundColor(Color(hex: "f59e0b"))
                        }
                        .listRowBackground(Color(hex: "f59e0b").opacity(0.1))
                    }
                }
                ForEach(days, id: \.self) { day in
                    HStack {
                        Text(day)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isOverused(day: day) ? Color(hex: "f59e0b") : Color(hex: "e2e8f0"))
                            .frame(width: 100, alignment: .leading)

                        Spacer()

                        Picker("", selection: Binding(
                            get: { store.schedule[day] ?? "Rest" },
                            set: { store.updateSchedule(day: day, routineName: $0) }
                        )) {
                            ForEach(routineOptions, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .task { await store.loadRoutines() }
        .navigationTitle("Weekly Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = store.previousScreen } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    for day in days {
                        store.updateSchedule(day: day, routineName: defaultWeeklySchedule[day] ?? "Rest")
                    }
                } label: {
                    Text("Reset")
                        .foregroundColor(Theme.subtle)
                }
            }
        }
    }
}
