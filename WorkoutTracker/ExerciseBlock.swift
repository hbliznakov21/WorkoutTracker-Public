import SwiftUI

// MARK: - Exercise block
struct ExerciseBlock: View {
    @Environment(WorkoutStore.self) var store
    let re: RoutineExercise
    let onLogSet: (Int) -> Void
    let onUnlogSet: (Int) -> Void
    let onEditSet: (Int, Double, Int) -> Void
    let onAddSet: (Int) -> Void
    let onRemoveSet: (Int) -> Void
    var onDropSet: (() -> Void)? = nil
    var restSeconds: Int
    var onRestChanged: ((Int) -> Void)? = nil

    @State private var showWarmUpSheet = false
    @State private var showRestPicker = false

    private var sets: [SetState] { store.sets[re.exercises.id] ?? [] }
    private var lastSets: [SetState] { store.lastSets[re.exercises.id] ?? [] }
    private var allDone: Bool { !sets.isEmpty && sets.allSatisfy(\.isDone) }
    private var isBodyweightExercise: Bool { re.exercises.equipment?.lowercased() == "bodyweight" }

    /// Detect working weight: first set's weight in current session, or last session's first set weight
    private var workingWeight: Double {
        if let first = sets.first, first.weight > 0 { return first.weight }
        if let last = lastSets.first, last.weight > 0 { return last.weight }
        return 0
    }

    /// Show warm-up button only for weighted, non-warmup exercises with no sets logged yet
    private var showWarmUpButton: Bool {
        guard !re.isWarmup else { return false }
        guard re.exercises.equipment?.lowercased() != "bodyweight" else { return false }
        guard workingWeight > 0 else { return false }
        // Hide if any set is already done (user already started working)
        guard !sets.contains(where: \.isDone) else { return false }
        // Hide if sets count already exceeds target (warm-up sets were added)
        guard sets.count <= re.targetSets else { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(re.exercises.name).font(.system(size: 15, weight: .bold))
                    if re.isWarmup {
                        Text("warm-up").font(.caption2).foregroundColor(Theme.subtle)
                    }
                    if let videoURL = ExerciseVideoLinks.url(for: re.exercises.name) {
                        Link(destination: videoURL) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color(hex: "38bdf8"))
                        }
                    }
                    Spacer()
                    // Rest time badge
                    Button { showRestPicker.toggle() } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "timer")
                                .font(.system(size: 10))
                            Text("\(restSeconds)s")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    Button { withAnimation { store.activeExercises.removeAll { $0.id == re.id } } } label: {
                        Image(systemName: "xmark").foregroundColor(Theme.border)
                    }
                }
                Text("\(re.targetSets) sets \u{00D7} \(re.targetRepsMin ?? 0)\u{2013}\(re.targetRepsMax ?? 0) reps")
                    .font(.caption).foregroundColor(Theme.subtle)
                if store.isDeloadWeek && !re.isWarmup {
                    let deloadSets = max(1, re.targetSets / 2)
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 9))
                        Text("Deload: \(deloadSets) sets recommended")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "38bdf8"))
                    .padding(.top, 1)
                }
                if let notes = re.notes {
                    Text(notes).font(.caption).foregroundColor(Theme.subtle).italic()
                }

                // Warm-up button
                if showWarmUpButton {
                    Button { showWarmUpSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10))
                            Text("Warm-up")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "fbbf24"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "fbbf24").opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .overlay(Divider(), alignment: .bottom)

            // Set rows
            ForEach(Array(sets.enumerated()), id: \.element.id) { i, setItem in
                SwipeableSetRow(
                    canDelete: !setItem.isDone && sets.count > 1,
                    onDelete: { onRemoveSet(i) }
                ) {
                    SetRow(
                        setNumber: i + 1,
                        state: Binding(
                            get: {
                                guard let arr = store.sets[re.exercises.id], arr.indices.contains(i) else {
                                    return SetState(weight: 20, reps: 10)
                                }
                                return arr[i]
                            },
                            set: {
                                guard store.sets[re.exercises.id]?.indices.contains(i) == true else { return }
                                store.sets[re.exercises.id]?[i] = $0
                            }
                        ),
                        lastSet: lastSets.indices.contains(i) ? lastSets[i] : nil,
                        isBodyweight: re.exercises.equipment?.lowercased() == "bodyweight",
                        isCableMachine: {
                            let eq = re.exercises.equipment?.lowercased() ?? ""
                            return eq.contains("cable") || eq.contains("machine")
                        }(),
                        targetRepsMin: re.targetRepsMin,
                        targetRepsMax: re.targetRepsMax,
                        onLog: {
                            if re.exercises.equipment?.lowercased() == "bodyweight" {
                                store.sets[re.exercises.id]?[i].weight = 0
                            }
                            onLogSet(i)
                        },
                        onUnlog: { onUnlogSet(i) },
                        onEdit: { weight, reps in onEditSet(i, weight, reps) }
                    )
                }
                .contextMenu {
                    if setItem.isDone {
                        Button {
                            onUnlogSet(i)
                        } label: {
                            Label("Unmark Set", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
                if i < sets.count - 1 {
                    Divider().padding(.leading, 40).background(Theme.surface)
                }
            }

            // Add set / Drop set
            HStack(spacing: 12) {
                Button { onAddSet(sets.count - 1) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle").font(.caption)
                        Text("Add set").font(.caption).fontWeight(.semibold)
                    }
                    .foregroundColor(Theme.subtle)
                }
                if !isBodyweightExercise, let onDrop = onDropSet {
                    Button { onDrop() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle").font(.caption)
                            Text("Drop set").font(.caption).fontWeight(.semibold)
                        }
                        .foregroundColor(Color(hex: "f59e0b"))
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(allDone ? Theme.accent : Theme.border, lineWidth: 1)
        )
        .opacity(allDone ? 0.65 : 1.0)
        .padding(.horizontal, 12)
        .sheet(isPresented: $showRestPicker) {
            RestPickerSheet(
                restSeconds: restSeconds,
                exerciseName: re.exercises.name,
                onChange: { newVal in onRestChanged?(newVal) },
                onDismiss: { showRestPicker = false }
            )
            .presentationDetents([.height(220)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Theme.surface)
        }
        .sheet(isPresented: $showWarmUpSheet) {
            WarmUpSheet(
                exerciseName: re.exercises.name,
                workingWeight: workingWeight,
                warmUpSets: WarmUpGenerator.generate(workingWeight: workingWeight),
                onAdd: { warmUps in
                    store.addWarmUpSets(exerciseId: re.exercises.id, warmUpSets: warmUps)
                }
            )
        }
    }
}

// MARK: - Set row
struct SetRow: View {
    let setNumber: Int
    @Binding var state: SetState
    var lastSet: SetState? = nil
    var isBodyweight: Bool = false
    var isCableMachine: Bool = false
    var targetRepsMin: Int? = nil
    var targetRepsMax: Int? = nil
    let onLog: () -> Void
    let onUnlog: () -> Void
    var onEdit: ((Double, Int) -> Void)? = nil
    @State private var weightStr = ""
    @State private var showUncheckAlert = false
    @State private var repsStr   = ""
    @FocusState private var weightFocused: Bool
    @FocusState private var repsFocused: Bool

    private var repRange: String? {
        guard let min = targetRepsMin, let max = targetRepsMax else { return nil }
        return min == max ? "\(min)" : "\(min)\u{2013}\(max)"
    }

    private var repsOutOfRange: Bool {
        guard state.isDone,
              let min = targetRepsMin, let max = targetRepsMax,
              min > 0 || max > 0
        else { return false }
        return state.reps < min || state.reps > max
    }

    // MARK: - Subviews

    private var setNumberColumn: some View {
        VStack(spacing: 1) {
            HStack(spacing: 2) {
                Text("\(setNumber)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(state.isDropSet ? Color(hex: "f59e0b") : (state.isDone ? Theme.accent : Theme.subtle))
                if state.isTarget && !state.isDone {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Theme.accent)
                }
            }
            if state.isDropSet {
                Text("DROP")
                    .font(.system(size: 7, weight: .black)).tracking(0.5)
                    .foregroundColor(Color(hex: "f59e0b"))
            } else if let last = lastSet {
                Text(isBodyweight ? "\(last.reps)" : "\(last.weight.clean)\u{00D7}\(last.reps)")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "475569"))
                    .lineLimit(1)
            }
        }
        .frame(width: 32)
    }

    private var weightField: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TextField("", text: $weightStr)
                    .font(.system(size: 16, weight: .bold))
                    .multilineTextAlignment(.center)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
                    .foregroundColor(state.isDone ? Theme.subtle : Color(hex: "e2e8f0"))
                    .onChange(of: weightStr) { _, v in
                        let clean = v.replacingOccurrences(of: ",", with: ".")
                        if let d = Double(clean), d >= 0 {
                            state.weight = d
                            if state.isDone { onEdit?(d, state.reps) }
                        }
                    }
                Text("kg")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.muted)
                    .padding(.trailing, 8)
            }
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(
                weightFocused ? Theme.accent : Theme.border))
            #if SONYA
            .overlay(alignment: .bottom) {
                if isCableMachine && state.weight > 0 {
                    Text("= \(Int(ceil(state.weight / 4.5))) blocks")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Theme.muted)
                        .offset(y: 12)
                }
            }
            #endif
        }
    }

    private var repsField: some View {
        VStack(spacing: 0) {
            TextField("", text: $repsStr)
                .font(.system(size: 16, weight: .bold))
                .multilineTextAlignment(.center)
                .keyboardType(.numberPad)
                .focused($repsFocused)
                .foregroundColor(state.isDone ? Theme.subtle : Color(hex: "e2e8f0"))
                .onChange(of: repsStr) { _, v in
                    if let i = Int(v), i >= 0 {
                        state.reps = i
                        if state.isDone { onEdit?(state.weight, i) }
                    }
                }
            if let range = repRange {
                Text(range)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(repsOutOfRange ? Color(hex: "f59e0b") : (state.isDone ? Theme.border : Theme.muted))
            }
        }
        .frame(height: 40)
        .frame(width: isBodyweight ? nil : 56)
        .frame(maxWidth: isBodyweight ? .infinity : nil)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(
            repsFocused ? Theme.accent : Theme.border))
    }

    private var logButton: some View {
        Button {
            if state.isDone { showUncheckAlert = true } else { onLog() }
        } label: {
            Image(systemName: state.isDone ? "checkmark" : "circle")
                .font(.system(size: 16, weight: .bold))
                .frame(width: 40, height: 40)
                .background(state.isDone ? (repsOutOfRange ? Color(hex: "f59e0b") : Theme.accent) : Color.clear)
                .foregroundColor(state.isDone ? .black : Theme.subtle)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(state.isDone ? Color.clear : Theme.border, lineWidth: 1.5)
                )
        }
        .accessibilityLabel(state.isDone ? "Unmark set \(setNumber)" : "Log set \(setNumber), \(fmtWeight(state.weight)) kg, \(state.reps) reps")
        .alert("Unmark set \(setNumber)?", isPresented: $showUncheckAlert) {
            Button("Unmark", role: .destructive) { onUnlog() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the logged set from your workout.")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                setNumberColumn
                #if SONYA
                // Sonya: reps first, then weight
                repsField
                if !isBodyweight { weightField }
                #else
                // Hristo: weight first, then reps
                if !isBodyweight { weightField }
                repsField
                #endif
                logButton
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
        }
        .background(state.isDone ? Theme.accent.opacity(0.06) : Color.clear)
        .onAppear {
            weightStr = fmtWeight(state.weight)
            repsStr   = "\(state.reps)"
        }
        .onChange(of: state.weight) { _, newVal in
            let current = Double(weightStr.replacingOccurrences(of: ",", with: ".")) ?? -1
            if current != newVal { weightStr = fmtWeight(newVal) }
        }
        .onChange(of: state.reps) { _, newVal in
            if Int(repsStr) != newVal { repsStr = "\(newVal)" }
        }
    }

    private func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w)
    }
}

// MARK: - Rest Picker Sheet
struct RestPickerSheet: View {
    let restSeconds: Int
    let exerciseName: String
    let onChange: (Int) -> Void
    let onDismiss: () -> Void

    private let presets = [30, 45, 60, 90, 120, 150, 180, 210, 240, 300]

    var body: some View {
        VStack(spacing: 16) {
            // Title
            Text(exerciseName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "e2e8f0"))

            // Stepper row
            HStack(spacing: 20) {
                Button {
                    onChange(max(15, restSeconds - 15))
                } label: {
                    Text("\u{2212}15")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 52, height: 40)
                        .background(Theme.bg)
                        .foregroundColor(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .buttonStyle(.plain)

                Text(fmtSecs(restSeconds))
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(Theme.accent)
                    .frame(minWidth: 80)
                    .monospacedDigit()

                Button {
                    onChange(min(300, restSeconds + 15))
                } label: {
                    Text("+15")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 52, height: 40)
                        .background(Theme.bg)
                        .foregroundColor(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                }
                .buttonStyle(.plain)
            }

            // Quick presets — two rows of 5
            VStack(spacing: 6) {
                ForEach([Array(presets.prefix(5)), Array(presets.suffix(5))], id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(row, id: \.self) { secs in
                            Button {
                                onChange(secs)
                                onDismiss()
                            } label: {
                                Text(fmtPreset(secs))
                                    .font(.system(size: 13, weight: secs == restSeconds ? .black : .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(secs == restSeconds ? Theme.accent : Theme.bg)
                                    .foregroundColor(secs == restSeconds ? .black : Theme.subtle)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(secs == restSeconds ? Color.clear : Theme.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    private func fmtSecs(_ s: Int) -> String {
        "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func fmtPreset(_ s: Int) -> String {
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return r == 0 ? "\(m)m" : "\(m):\(String(format: "%02d", r))"
    }
}

// MARK: - Swipeable Set Row (swipe right to reveal delete)
struct SwipeableSetRow<Content: View>: View {
    let canDelete: Bool
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var showDeleteConfirm = false

    private let deleteWidth: CGFloat = 72

    var body: some View {
        ZStack(alignment: .leading) {
            // Delete button behind the row (revealed on swipe right)
            if canDelete {
                Button {
                    showDeleteConfirm = true
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Delete")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(width: deleteWidth)
                    .frame(maxHeight: .infinity)
                    .background(Color(hex: "ef4444"))
                }
                .buttonStyle(.plain)
            }

            // Foreground content
            content
                .frame(maxWidth: .infinity)
                .background(Theme.surface)
                .offset(x: offset)
                .gesture(
                    canDelete
                    ? DragGesture(minimumDistance: 20)
                        .onChanged { value in
                            let x = value.translation.width
                            // Only allow rightward drag
                            if x > 0 {
                                offset = min(x, deleteWidth)
                            } else if offset > 0 {
                                offset = max(0, deleteWidth + x)
                            }
                        }
                        .onEnded { value in
                            withAnimation(.easeOut(duration: 0.2)) {
                                // Snap open if dragged past halfway, otherwise snap closed
                                offset = value.translation.width > deleteWidth / 2 ? deleteWidth : 0
                            }
                        }
                    : nil
                )
        }
        .clipped()
        .alert("Delete this set?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                withAnimation {
                    offset = 0
                    Haptics.light()
                    onDelete()
                }
            }
            Button("Cancel", role: .cancel) {
                withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
            }
        } message: {
            Text("This set will be removed from your workout.")
        }
    }
}
