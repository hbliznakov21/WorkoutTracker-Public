import SwiftUI

struct ChooseRoutineView: View {
    @Environment(WorkoutStore.self) var store
    @State private var showNewRoutineAlert = false
    @State private var newRoutineName = ""

    private func icon(for name: String) -> String {
        // Strip week suffix (e.g. "Push (Mon) W2" → "Push (Mon)")
        let base = name.replacingOccurrences(of: " W[234]$", with: "", options: .regularExpression)
        let icons: [String: String] = [
            "Push": "🫸", "Pull A": "🦾", "Pull B": "🦾", "Legs": "🦵"
        ]
        return icons.first(where: { base.hasPrefix($0.key) })?.value ?? "💪"
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Strength routines
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(store.visibleRoutines) { routine in
                            routineCard(routine)
                        }
                        newRoutineCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    // Cardio section
                    Text("CARDIO")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(Theme.subtle)
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                        .padding(.bottom, 10)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(cardioTypes) { type in
                            cardioCard(type)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .task { await store.loadRoutines() }
        .navigationTitle("Choose Workout")
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
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Button { store.activeScreen = .scheduleEditor } label: {
                        Image(systemName: "calendar")
                            .foregroundColor(Theme.subtle)
                    }
                    Button { store.activeScreen = .exercises } label: {
                        Image(systemName: "dumbbell")
                            .foregroundColor(Theme.subtle)
                    }
                }
            }
        }
        .alert("New Routine", isPresented: $showNewRoutineAlert) {
            TextField("Routine name", text: $newRoutineName)
            Button("Create") {
                let name = newRoutineName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task {
                    if let routine = await store.createRoutine(name: name) {
                        store.activeScreen = .editRoutine(routine.id)
                    }
                }
                newRoutineName = ""
            }
            Button("Cancel", role: .cancel) { newRoutineName = "" }
        }
    }

    private func cardioCard(_ type: CardioType) -> some View {
        Button {
            Task { await store.startCardio(type: type) }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.system(size: 30))
                    .foregroundColor(Color(hex: "38bdf8"))
                Text(type.name)
                    .font(.system(size: 15, weight: .black))
                    .foregroundColor(Color(hex: "e2e8f0"))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20).padding(.horizontal, 12)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var newRoutineCard: some View {
        Button {
            showNewRoutineAlert = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.muted)
                Text("New Routine")
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20).padding(.horizontal, 12)
            .background(Theme.surface.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundColor(Theme.border)
            )
        }
        .buttonStyle(.plain)
    }

    private func routineCard(_ routine: Routine) -> some View {
        let isToday = store.todayRoutine?.id == routine.id

        return Button {
            Task { await store.startWorkout(routine: routine) }
        } label: {
            VStack(spacing: 8) {
                if isToday {
                    Text("TODAY")
                        .font(.system(size: 8, weight: .black)).tracking(1.2)
                        .foregroundColor(Theme.accent)
                }
                Text(icon(for: routine.name)).font(.system(size: 32))
                Text(routine.name)
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(Color(hex: "e2e8f0"))
                if let label = routine.dayLabel {
                    Text(label).font(.caption).foregroundColor(Theme.subtle)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20).padding(.horizontal, 12)
            .background(isToday ? Theme.accent.opacity(0.06) : Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isToday ? Theme.accent : Theme.border, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                store.activeScreen = .editRoutine(routine.id)
            } label: {
                Label("Edit Routine", systemImage: "pencil")
            }
            Button {
                Task { await store.duplicateRoutine(routine) }
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                Task { await store.deleteRoutine(id: routine.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
