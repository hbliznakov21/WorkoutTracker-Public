import SwiftUI

struct ExercisePickerView: View {
    @Environment(WorkoutStore.self) var store
    @Environment(\.dismiss) var dismiss
    let routineId: UUID
    @State private var search = ""
    @State private var showCreateSheet = false

    private var grouped: [(String, [Exercise])] {
        let filtered = search.isEmpty
            ? store.allExercises
            : store.allExercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
        let dict = Dictionary(grouping: filtered) { $0.muscleGroup ?? "Other" }
        return dict.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "0f172a").ignoresSafeArea()
                List {
                    // Create new exercise button
                    Button {
                        showCreateSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(Color(hex: "22c55e"))
                            Text("Create New Exercise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(hex: "22c55e"))
                            Spacer()
                        }
                    }
                    .listRowBackground(Color(hex: "1e293b"))

                    ForEach(grouped, id: \.0) { group, exercises in
                        Section {
                            ForEach(exercises) { ex in
                                Button {
                                    Task {
                                        await store.addRoutineExercise(routineId: routineId, exerciseId: ex.id)
                                        dismiss()
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ex.name)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundColor(Color(hex: "e2e8f0"))
                                            if let eq = ex.equipment, !eq.isEmpty {
                                                Text(eq)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Color(hex: "64748b"))
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle")
                                            .foregroundColor(Color(hex: "22c55e"))
                                    }
                                }
                            }
                        } header: {
                            Text(group)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: "94a3b8"))
                        }
                        .listRowBackground(Color(hex: "1e293b"))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .searchable(text: $search, prompt: "Search exercises")
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(hex: "1e293b"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color(hex: "94a3b8"))
                }
            }
        }
        .task {
            await store.loadAllExercises()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateExerciseSheet(routineId: routineId, onCreated: { dismiss() })
        }
    }
}

// MARK: - Create Exercise Sheet
struct CreateExerciseSheet: View {
    @Environment(WorkoutStore.self) var store
    @Environment(\.dismiss) var dismiss
    let routineId: UUID
    var onCreated: (() -> Void)? = nil

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
                Color(hex: "0f172a").ignoresSafeArea()
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
            .toolbarBackground(Color(hex: "1e293b"), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color(hex: "94a3b8"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        Task {
                            if let ex = await store.createExercise(
                                name: trimmed,
                                muscleGroup: muscleGroup.isEmpty ? nil : muscleGroup,
                                equipment: equipment.trimmingCharacters(in: .whitespaces).isEmpty ? nil : equipment.trimmingCharacters(in: .whitespaces)
                            ) {
                                await store.addRoutineExercise(routineId: routineId, exerciseId: ex.id)
                                dismiss()
                                onCreated?()
                            }
                        }
                    }
                    .foregroundColor(Color(hex: "22c55e"))
                    .fontWeight(.bold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
