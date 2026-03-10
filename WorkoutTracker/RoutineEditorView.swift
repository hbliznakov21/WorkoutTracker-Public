import SwiftUI
import Combine

struct RoutineEditorView: View {
    @Environment(WorkoutStore.self) var store
    let routineId: UUID
    @State private var showExercisePicker = false
    @State private var showRenameAlert = false
    @State private var showDeleteAlert = false
    @State private var renameText = ""

    private var routineName: String {
        store.routines.first { $0.id == routineId }?.name ?? "Routine"
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if store.editingExercises.isEmpty {
                    emptyState
                } else {
                    exerciseList
                }
                addButton
            }
        }
        .task {
            await store.loadRoutineExercises(routineId: routineId)
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerView(routineId: routineId)
        }
        .alert("Rename Routine", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                Task { await store.renameRoutine(id: routineId, name: name) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete \"\(routineName)\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                Task {
                    await store.deleteRoutine(id: routineId)
                    store.activeScreen = .choose
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this routine and all its exercises.")
        }
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
        }
    }

    // MARK: - Header
    private var header: some View {
        VStack(spacing: 4) {
            Button {
                renameText = routineName
                showRenameAlert = true
            } label: {
                HStack(spacing: 6) {
                    Text(routineName)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(Color(hex: "e2e8f0"))
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            Text("\(store.editingExercises.count) exercises")
                .font(.system(size: 13))
                .foregroundColor(Theme.subtle)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Empty state
    private var emptyState: some View {
        Spacer()
            .frame(maxHeight: .infinity)
            .overlay {
                Text("No exercises yet")
                    .foregroundColor(Theme.muted)
            }
    }

    // MARK: - Exercise list
    private var exerciseList: some View {
        List {
            ForEach(store.editingExercises) { re in
                ExerciseEditorRow(routineId: routineId, exercise: re)
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.border)
            }
            .onDelete(perform: deleteExercises)
            .onMove(perform: moveExercises)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Bottom buttons
    private var addButton: some View {
        VStack(spacing: 8) {
            Button {
                showExercisePicker = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Exercise")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                showDeleteAlert = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Routine")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(Color(hex: "ef4444").opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Actions
    private func deleteExercises(at offsets: IndexSet) {
        for i in offsets {
            let re = store.editingExercises[i]
            Task { await store.deleteRoutineExercise(id: re.id) }
        }
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        store.editingExercises.move(fromOffsets: source, toOffset: destination)
        Task { await store.reorderRoutineExercises(routineId: routineId) }
    }
}

// MARK: - Exercise Editor Row
struct ExerciseEditorRow: View {
    @Environment(WorkoutStore.self) var store
    let routineId: UUID
    let exercise: RoutineExercise

    @State private var targetSets: Int
    @State private var repsMin: Int
    @State private var repsMax: Int
    @State private var restSeconds: Int
    @State private var supersetGroup: String
    @State private var isWarmup: Bool
    @State private var notes: String
    @State private var showNotes = false
    @State private var saveTask: Task<Void, Never>?

    init(routineId: UUID, exercise: RoutineExercise) {
        self.routineId = routineId
        self.exercise = exercise
        _targetSets = State(initialValue: exercise.targetSets)
        _repsMin = State(initialValue: exercise.targetRepsMin ?? 8)
        _repsMax = State(initialValue: exercise.targetRepsMax ?? 12)
        #if SONYA
        _restSeconds = State(initialValue: exercise.restSeconds ?? 60)
        #else
        _restSeconds = State(initialValue: exercise.restSeconds ?? 90)
        #endif
        _supersetGroup = State(initialValue: exercise.supersetGroup ?? "")
        _isWarmup = State(initialValue: exercise.isWarmup)
        _notes = State(initialValue: exercise.notes ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Exercise name + badges
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.exercises.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Color(hex: "e2e8f0"))
                    if let mg = exercise.exercises.muscleGroup {
                        Text(mg)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.subtle)
                    }
                }
                Spacer()
                if isWarmup {
                    badge("WARM-UP", color: "f59e0b")
                }
                if !supersetGroup.isEmpty {
                    badge(supersetGroup, color: "8b5cf6")
                }
            }

            // Editable fields row
            HStack(spacing: 12) {
                fieldGroup("Sets", value: $targetSets, range: 1...10)
                fieldGroup("Min", value: $repsMin, range: 1...50)
                fieldGroup("Max", value: $repsMax, range: 1...50)
                fieldGroup("Rest", value: $restSeconds, range: 15...300, step: 15)
            }

            // Superset + Warmup + Notes row
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("SS")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.subtle)
                    TextField("—", text: $supersetGroup)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "e2e8f0"))
                        .frame(width: 44)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 4)
                        .background(Theme.border)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .onChange(of: supersetGroup) { debouncedSave() }
                }

                Button {
                    isWarmup.toggle()
                    debouncedSave()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isWarmup ? "checkmark.square.fill" : "square")
                            .foregroundColor(isWarmup ? Color(hex: "f59e0b") : Theme.muted)
                        Text("Warm-up")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.subtle)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showNotes.toggle()
                } label: {
                    Image(systemName: "note.text")
                        .font(.system(size: 14))
                        .foregroundColor(notes.isEmpty ? Theme.muted : Theme.accent)
                }
                .buttonStyle(.plain)
            }

            // Notes field (expandable)
            if showNotes {
                TextField("Notes...", text: $notes, axis: .vertical)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "e2e8f0"))
                    .padding(8)
                    .background(Theme.border)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .lineLimit(1...4)
                    .onChange(of: notes) { debouncedSave() }
            }
        }
        .padding(.vertical, 6)
        .onChange(of: targetSets) { debouncedSave() }
        .onChange(of: repsMin) { debouncedSave() }
        .onChange(of: repsMax) { debouncedSave() }
        .onChange(of: restSeconds) { debouncedSave() }
    }

    // MARK: - Helpers

    private func badge(_ text: String, color: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black))
            .tracking(0.5)
            .foregroundColor(Color(hex: color))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(hex: color).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func fieldGroup(_ label: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int = 1) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Theme.muted)
            HStack(spacing: 0) {
                Button {
                    let new = value.wrappedValue - step
                    if new >= range.lowerBound { value.wrappedValue = new }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.subtle)
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)

                Text("\(value.wrappedValue)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "e2e8f0"))
                    .frame(minWidth: label == "Rest" ? 32 : 20)

                Button {
                    let new = value.wrappedValue + step
                    if new <= range.upperBound { value.wrappedValue = new }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.subtle)
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .background(Theme.border)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            let update = RoutineExerciseUpdate(
                targetSets: targetSets,
                targetRepsMin: repsMin,
                targetRepsMax: repsMax,
                restSeconds: restSeconds,
                supersetGroup: supersetGroup.isEmpty ? .some(nil) : .some(supersetGroup),
                isWarmup: isWarmup,
                notes: notes.isEmpty ? .some(nil) : .some(notes)
            )
            await store.updateRoutineExercise(id: exercise.id, update: update)
        }
    }
}
