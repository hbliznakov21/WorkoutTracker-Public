import SwiftUI

struct WarmUpSheet: View {
    let exerciseName: String
    let workingWeight: Double
    let warmUpSets: [WarmUpSet]
    let onAdd: ([WarmUpSet]) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 3)
                .fill(Theme.border)
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            // Title
            VStack(spacing: 4) {
                Text("Warm-Up Sets")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "e2e8f0"))
                Text(exerciseName)
                    .font(.caption)
                    .foregroundColor(Theme.subtle)
                Text("Working weight: \(workingWeight.clean) kg")
                    .font(.caption2)
                    .foregroundColor(Theme.muted)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider().background(Theme.border)

            // Warm-up set rows
            VStack(spacing: 0) {
                ForEach(Array(warmUpSets.enumerated()), id: \.element.id) { index, ws in
                    HStack {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.muted)
                            .frame(width: 24)

                        Text(ws.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.subtle)
                            .frame(width: 64, alignment: .leading)

                        Spacer()

                        Text("\(ws.weight.clean) kg")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.muted)

                        Text("\u{00D7}")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.border)

                        Text("\(ws.reps)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(Theme.muted)
                            .frame(width: 28, alignment: .trailing)

                        Text("reps")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.border)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < warmUpSets.count - 1 {
                        Divider().padding(.leading, 40).background(Theme.border)
                    }
                }
            }

            Divider().background(Theme.border).padding(.top, 4)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Dismiss")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.border)
                        .foregroundColor(Theme.subtle)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button {
                    onAdd(warmUpSets)
                    dismiss()
                } label: {
                    Text("Add as Sets")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Theme.surface)
        .presentationDetents([.height(CGFloat(200 + warmUpSets.count * 48))])
        .presentationDragIndicator(.hidden)
    }
}
