import SwiftUI

struct ExerciseListView: View {
    @Environment(WorkoutStore.self) var store
    @State private var search = ""
    @State private var editingExercise: Exercise?
    @State private var showCreateSheet = false

    private var grouped: [(String, [Exercise])] {
        let filtered = search.isEmpty
            ? store.allExercises
            : store.allExercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
        let dict = Dictionary(grouping: filtered) { $0.muscleGroup ?? "Other" }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            List {
                ForEach(grouped, id: \.0) { group, exercises in
                    Section {
                        ForEach(exercises) { ex in
                            Button {
                                editingExercise = ex
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(Color(hex: "e2e8f0"))
                                        if let eq = ex.equipment, !eq.isEmpty {
                                            Text(eq)
                                                .font(.system(size: 11))
                                                .foregroundColor(Theme.muted)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundColor(Color(hex: "475569"))
                                }
                            }
                        }
                    } header: {
                        Text(group)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.subtle)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .searchable(text: $search, prompt: "Search exercises")
        }
        .task {
            await store.reloadAllExercises()
        }
        .navigationTitle("Exercises")
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
                Button { showCreateSheet = true } label: {
                    Image(systemName: "plus")
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .sheet(item: $editingExercise) { ex in
            EditExerciseSheet(exercise: ex)
        }
        .sheet(isPresented: $showCreateSheet) {
            StandaloneCreateExerciseSheet()
        }
    }
}

// MARK: - Edit Exercise Sheet
struct EditExerciseSheet: View {
    @Environment(WorkoutStore.self) var store
    @Environment(\.dismiss) var dismiss
    let exercise: Exercise

    @State private var name: String
    @State private var muscleGroup: String
    @State private var equipment: String
    @State private var showDeleteAlert = false

    private let muscleGroups = [
        "", "Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms",
        "Quads", "Hamstrings", "Glutes", "Calves", "Core", "Full Body"
    ]

    init(exercise: Exercise) {
        self.exercise = exercise
        _name = State(initialValue: exercise.name)
        _muscleGroup = State(initialValue: exercise.muscleGroup ?? "")
        _equipment = State(initialValue: exercise.equipment ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                Form {
                    Section {
                        TextField("Exercise name", text: $name)
                    }
                    Section {
                        Picker("Muscle Group", selection: $muscleGroup) {
                            Text("None").tag("")
                            ForEach(muscleGroups.filter { !$0.isEmpty }, id: \.self) { mg in
                                Text(mg).tag(mg)
                            }
                        }
                    }
                    Section {
                        TextField("Equipment (optional)", text: $equipment)
                    }
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Exercise")
                                Spacer()
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.subtle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            await store.updateExercise(
                                id: exercise.id,
                                name: trimmed,
                                muscleGroup: muscleGroup.isEmpty ? nil : muscleGroup,
                                equipment: equipment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : equipment.trimmingCharacters(in: .whitespaces)
                            )
                            dismiss()
                        }
                    }
                    .foregroundColor(Theme.accent)
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Delete Exercise?", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        await store.deleteExercise(id: exercise.id)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete \"\(exercise.name)\". It cannot be undone.")
            }
        }
    }
}

// MARK: - Standalone Create Exercise Sheet (no routine add)
struct StandaloneCreateExerciseSheet: View {
    @Environment(WorkoutStore.self) var store
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var muscleGroup = ""
    @State private var equipment = ""

    private let muscleGroups = [
        "", "Chest", "Back", "Shoulders", "Biceps", "Triceps", "Forearms",
        "Quads", "Hamstrings", "Glutes", "Calves", "Core", "Full Body"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                Form {
                    Section {
                        TextField("Exercise name", text: $name)
                    }
                    Section {
                        Picker("Muscle Group", selection: $muscleGroup) {
                            Text("None").tag("")
                            ForEach(muscleGroups.filter { !$0.isEmpty }, id: \.self) { mg in
                                Text(mg).tag(mg)
                            }
                        }
                    }
                    Section {
                        TextField("Equipment (optional)", text: $equipment)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.subtle)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            _ = await store.createExercise(
                                name: trimmed,
                                muscleGroup: muscleGroup.isEmpty ? nil : muscleGroup,
                                equipment: equipment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : equipment.trimmingCharacters(in: .whitespaces)
                            )
                            dismiss()
                        }
                    }
                    .foregroundColor(Theme.accent)
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
