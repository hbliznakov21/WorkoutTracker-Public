import SwiftUI
import UniformTypeIdentifiers

// MARK: - Summary data model (snapshot captured at finish time)

struct WorkoutSummaryData: Equatable {
    let routineName: String
    let date: Date
    let durationMinutes: Int
    let totalVolume: Double
    let totalSets: Int
    let prsHit: Int
    let exercises: [ExerciseSummary]

    struct ExerciseSummary: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let bestWeight: Double
        let bestReps: Int
        let setCount: Int

        static func == (lhs: ExerciseSummary, rhs: ExerciseSummary) -> Bool {
            lhs.name == rhs.name && lhs.bestWeight == rhs.bestWeight && lhs.bestReps == rhs.bestReps
        }
    }
}

// MARK: - Share sheet (presented after finishing or from detail view)

struct WorkoutSummaryShareView: View {
    let summary: WorkoutSummaryData
    var onDismiss: () -> Void = {}

    @State private var renderedImage: UIImage?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { onDismiss() } label: {
                        Text("Done")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Theme.accent)
                    }
                    Spacer()
                    Text("Workout Summary")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    // Share button
                    if let img = renderedImage {
                        ShareLink(
                            item: img,
                            preview: SharePreview(summary.routineName, image: Image(uiImage: img))
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(Theme.accent)
                        }
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(Theme.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                ScrollView {
                    VStack(spacing: 16) {
                        // The card itself
                        SummaryCardView(summary: summary)
                            .padding(.horizontal, 20)

                        // Share as image button
                        if let img = renderedImage {
                            ShareLink(
                                item: img,
                                preview: SharePreview(summary.routineName, image: Image(uiImage: img))
                            ) {
                                HStack(spacing: 8) {
                                    Image(systemName: "photo")
                                    Text("Share as Image")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Theme.accent)
                                .foregroundColor(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 20)
                        }

                        // Share as text button
                        ShareLink(item: textSummary) {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.text")
                                Text("Share as Text")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.surface)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear { renderImage() }
    }

    // MARK: - Render card to UIImage

    private func renderImage() {
        let card = SummaryCardView(summary: summary)
            .frame(width: 390)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderedImage = renderer.uiImage
    }

    // MARK: - Text summary

    private var textSummary: String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, d MMM yyyy"
        var lines: [String] = []
        lines.append("\(summary.routineName)")
        lines.append(df.string(from: summary.date))
        lines.append("")
        lines.append("\(summary.durationMinutes) min | \(formattedVolume) kg volume")
        lines.append("")
        for ex in summary.exercises {
            let w = ex.bestWeight.clean
            lines.append("\(ex.name)  \(w) x \(ex.bestReps)")
        }
        lines.append("")
        lines.append("\(summary.exercises.count) exercises | \(summary.totalSets) sets")
        lines.append("")
        lines.append("WorkoutTracker")
        return lines.joined(separator: "\n")
    }

    private var formattedVolume: String {
        summary.totalVolume >= 1000
            ? String(format: "%.1fk", summary.totalVolume / 1000)
            : "\(Int(summary.totalVolume))"
    }
}

// MARK: - The visual card (rendered to image)

struct SummaryCardView: View {
    let summary: WorkoutSummaryData

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM yyyy"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.routineName)
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.white)
                Text(Self.dateFmt.string(from: summary.date))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.subtle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 16)

            // Stats row
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                statCell(icon: "clock.fill", value: "\(summary.durationMinutes)", unit: "min")
                Rectangle().fill(Theme.border).frame(width: 1, height: 44)
                statCell(icon: "scalemass.fill", value: formattedVolume, unit: "kg vol")
                if summary.prsHit > 0 {
                    Rectangle().fill(Theme.border).frame(width: 1, height: 44)
                    statCell(icon: "trophy.fill", value: "\(summary.prsHit)", unit: "PRs")
                }
            }
            .padding(.vertical, 12)
            Rectangle().fill(Theme.border).frame(height: 1)

            // Exercise list
            VStack(spacing: 0) {
                ForEach(Array(summary.exercises.enumerated()), id: \.offset) { idx, ex in
                    HStack {
                        Text(ex.name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(ex.bestWeight.clean) x \(ex.bestReps)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.accent)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    if idx < summary.exercises.count - 1 {
                        Rectangle().fill(Theme.border.opacity(0.4))
                            .frame(height: 1)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 8)

            // Footer
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack {
                Text("\(summary.exercises.count) exercises")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.subtle)
                Text("·")
                    .foregroundColor(Theme.muted)
                Text("\(summary.totalSets) sets")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.subtle)
                Spacer()
                Text("WorkoutTracker")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Theme.accent.opacity(0.7))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func statCell(icon: String, value: String, unit: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(.white)
                Text(unit)
                    .font(.system(size: 10, weight: .bold))
                    .textCase(.uppercase)
                    .foregroundColor(Theme.subtle)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedVolume: String {
        summary.totalVolume >= 1000
            ? String(format: "%.1fk", summary.totalVolume / 1000)
            : "\(Int(summary.totalVolume))"
    }
}

// MARK: - UIImage conformance to Transferable for ShareLink

extension UIImage: @retroactive Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { image in
            guard let data = image.pngData() else {
                throw CocoaError(.fileWriteUnknown)
            }
            return data
        }
    }
}
