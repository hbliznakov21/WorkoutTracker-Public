import SwiftUI

struct GoalsEditorSheet: View {
    let currentGoals: UserPhaseGoals?
    let onSave: (UserPhaseGoals) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var phase: String = "post_cut"
    @State private var calories: String = ""
    @State private var protein: String = ""
    @State private var carbs: String = ""
    @State private var fat: String = ""
    @State private var endDate: Date = Date()

    private let phases = [("cut", "Cutting"), ("post_cut", "Post-Cut"), ("bulk", "Bulking")]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        // Phase picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phase")
                                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                                .foregroundColor(Theme.subtle)
                            HStack(spacing: 8) {
                                ForEach(phases, id: \.0) { (id, label) in
                                    Button {
                                        phase = id
                                    } label: {
                                        Text(label)
                                            .font(.system(size: 13, weight: .semibold))
                                            .padding(.horizontal, 16).padding(.vertical, 10)
                                            .frame(maxWidth: .infinity)
                                            .background(phase == id ? phaseColor(id) : Color.clear)
                                            .foregroundColor(phase == id ? .black : Theme.subtle)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(phase == id ? Color.clear : Theme.border))
                                    }
                                }
                            }
                        }

                        // Calories
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Daily Calories")
                                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                                .foregroundColor(Theme.subtle)
                            TextField("e.g. 1800", text: $calories)
                                .keyboardType(.numberPad)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Theme.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
                        }

                        // Macros
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Macros (grams)")
                                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                                .foregroundColor(Theme.subtle)
                            HStack(spacing: 10) {
                                macroField("Protein", $protein, "22c55e")
                                macroField("Carbs", $carbs, "3b82f6")
                                macroField("Fat", $fat, "f59e0b")
                            }
                        }

                        // End date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phase End Date")
                                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                                .foregroundColor(Theme.subtle)
                            DatePicker("", selection: $endDate, displayedComponents: .date)
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .colorScheme(.dark)
                        }

                        // Save button
                        Button {
                            let goals = UserPhaseGoals(
                                phase: phase,
                                targetCalories: Int(calories) ?? 0,
                                targetProtein: Int(protein) ?? 0,
                                targetCarbs: Int(carbs) ?? 0,
                                targetFat: Int(fat) ?? 0,
                                endDate: {
                                    let f = DateFormatter()
                                    f.dateFormat = "yyyy-MM-dd"
                                    f.locale = Locale(identifier: "en_US_POSIX")
                                    return f.string(from: endDate)
                                }()
                            )
                            onSave(goals)
                            dismiss()
                        } label: {
                            Text("Save Goals")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color(hex: "a855f7"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(calories.isEmpty || protein.isEmpty)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("My Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .onAppear {
            if let g = currentGoals {
                phase = g.phase
                calories = "\(g.targetCalories)"
                protein = "\(g.targetProtein)"
                carbs = "\(g.targetCarbs)"
                fat = "\(g.targetFat)"
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.locale = Locale(identifier: "en_US_POSIX")
                if let d = f.date(from: g.endDate) { endDate = d }
            }
        }
    }

    private func macroField(_ label: String, _ value: Binding<String>, _ color: String) -> some View {
        VStack(spacing: 4) {
            TextField("0", text: value)
                .keyboardType(.numberPad)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: color).opacity(0.4)))
            Text(label)
                .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                .foregroundColor(Color(hex: color))
        }
    }

    private func phaseColor(_ id: String) -> Color {
        switch id {
        case "cut":      return Color(hex: "ef4444")
        case "post_cut": return Color(hex: "f59e0b")
        case "bulk":     return Color(hex: "22c55e")
        default:         return Color(hex: "94a3b8")
        }
    }
}
