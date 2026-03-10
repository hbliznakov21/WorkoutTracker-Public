import SwiftUI

// MARK: - Image transform state for zoom/pan

struct ImageTransform: Equatable {
    var scale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastScale: CGFloat = 1.0
    var lastOffset: CGSize = .zero

    mutating func reset() {
        scale = 1.0; offset = .zero; lastScale = 1.0; lastOffset = .zero
    }
}

struct PhotoCompareView: View {
    @Environment(WorkoutStore.self) var store
    @Environment(PhotoStore.self) var photoStore

    @State private var fromDate: String = ""
    @State private var toDate: String = ""
    @State private var selectedPose = "front"
    @State private var dividerPosition: CGFloat = 0.5

    // Align / Compare mode
    enum Mode: String, CaseIterable { case align = "Align", compare = "Compare" }
    @State private var mode: Mode = .compare
    @State private var activeImage: Int = 0 // 0 = from (left), 1 = to (right)
    @State private var fromTransform = ImageTransform()
    @State private var toTransform = ImageTransform()
    @State private var bodyFatResult: BodyFatAnalysis?
    @State private var bodyFatLoading = false

    private let poses = ["front", "side", "back"]
    private let poseLabels = ["Front", "Side", "Back"]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    datePickers
                    posePicker
                    modePicker
                    if !fromDate.isEmpty && !toDate.isEmpty {
                        bodyFatSection
                        if mode == .align {
                            alignHint
                        }
                        comparisonSlider
                        if mode == .align {
                            resetButton
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.activeScreen = .photos } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .bold))
                        Text("Back")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
        .onAppear {
            let dates = photoStore.allDates
            if dates.count >= 2 {
                fromDate = dates.last ?? ""
                toDate = dates.first ?? ""
            } else if dates.count == 1 {
                fromDate = dates[0]
                toDate = dates[0]
            }
        }
        .onChange(of: fromDate) { _, _ in resetTransforms() }
        .onChange(of: toDate) { _, _ in resetTransforms() }
        .onChange(of: selectedPose) { _, _ in resetTransforms() }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .photos) }
    }

    private func resetTransforms() {
        fromTransform.reset()
        toTransform.reset()
    }

    // MARK: - Date pickers

    private var datePickers: some View {
        HStack(spacing: 12) {
            datePickerCard(label: "From", selection: $fromDate)
            datePickerCard(label: "To", selection: $toDate)
        }
        .padding(.horizontal, 16)
    }

    private func datePickerCard(label: String, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
            Menu {
                ForEach(photoStore.allDates, id: \.self) { date in
                    Button(formatDisplayDate(date)) {
                        selection.wrappedValue = date
                    }
                }
            } label: {
                HStack {
                    Text(selection.wrappedValue.isEmpty ? "Select" : formatDisplayDate(selection.wrappedValue))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
                .padding(12)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
            }
        }
    }

    // MARK: - Pose picker

    private var posePicker: some View {
        HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedPose = poses[i] }
                } label: {
                    Text(poseLabels[i])
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(selectedPose == poses[i] ? .black : Theme.subtle)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selectedPose == poses[i] ? Theme.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .padding(.horizontal, 16)
    }

    // MARK: - Mode picker (Align / Compare)

    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: m == .align ? "hand.pinch" : "slider.horizontal.below.rectangle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(m.rawValue)
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(mode == m ? .black : Theme.subtle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(mode == m ? Theme.accent : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(3)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
        .padding(.horizontal, 16)
    }

    // MARK: - Align hint

    private var alignHint: some View {
        HStack(spacing: 6) {
            Image(systemName: activeImage == 0 ? "arrow.left.circle.fill" : "arrow.right.circle.fill")
                .foregroundColor(Theme.accent)
            Text("Pinch & drag the **\(activeImage == 0 ? "left" : "right")** image to align")
                .font(.system(size: 12))
                .foregroundColor(Theme.subtle)
            Spacer()
            Button {
                activeImage = activeImage == 0 ? 1 : 0
            } label: {
                Text("Switch")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Reset button

    private var resetButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { resetTransforms() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .bold))
                Text("Reset Zoom")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(Theme.subtle)
        }
    }

    // MARK: - Comparison slider

    private var comparisonSlider: some View {
        let fromEntries = photoStore.entries(for: fromDate)
        let toEntries = photoStore.entries(for: toDate)
        let fromEntry = fromEntries.first(where: { $0.pose == selectedPose })
        let toEntry = toEntries.first(where: { $0.pose == selectedPose })

        return VStack(spacing: 8) {
            HStack {
                Text(formatDisplayDate(fromDate))
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(mode == .align && activeImage == 0 ? Theme.accent : Theme.subtle)
                Spacer()
                Text(formatDisplayDate(toDate))
                    .font(.caption).fontWeight(.bold)
                    .foregroundColor(mode == .align && activeImage == 1 ? Theme.accent : Theme.subtle)
            }
            .padding(.horizontal, 16)

            GeometryReader { geo in
                let width = geo.size.width
                let height = geo.size.height

                ZStack {
                    // "To" image (full, behind)
                    if let entry = toEntry, let img = photoStore.loadImage(for: entry) {
                        transformedImage(img, transform: toTransform, width: width, height: height)
                    } else {
                        placeholderImage
                    }

                    // "From" image (clipped by divider)
                    if let entry = fromEntry, let img = photoStore.loadImage(for: entry) {
                        transformedImage(img, transform: fromTransform, width: width, height: height)
                            .clipShape(HorizontalClip(rightEdge: dividerPosition * width))
                    }

                    // Center guideline in align mode
                    if mode == .align {
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1)
                            .position(x: width / 2, y: height / 2)
                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(height: 1)
                            .position(x: width / 2, y: height / 2)
                    }

                    // Divider line + handle (only interactive in compare mode)
                    let xPos = dividerPosition * width
                    Rectangle()
                        .fill(Theme.accent)
                        .frame(width: 2)
                        .position(x: xPos, y: height / 2)

                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: mode == .compare ? "arrow.left.and.right" : "lock.fill")
                                .font(.system(size: mode == .compare ? 12 : 10, weight: .bold))
                                .foregroundColor(.black)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        .position(x: xPos, y: height / 2)

                    // Gesture overlay
                    if mode == .compare {
                        // Slider drag gesture
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newPos = value.location.x / width
                                        dividerPosition = min(max(newPos, 0.05), 0.95)
                                    }
                            )
                    } else {
                        // Align mode: zoom/pan gestures on active image
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(alignDragGesture())
                            .gesture(alignMagnifyGesture())
                            .onTapGesture { location in
                                // Tap left/right half to switch active image
                                activeImage = location.x < width / 2 ? 0 : 1
                            }
                    }
                }
            }
            .aspectRatio(3/4, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Transformed image view

    private func transformedImage(_ img: UIImage, transform: ImageTransform, width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: img)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .scaleEffect(transform.scale)
            .offset(transform.offset)
            .clipped()
    }

    // MARK: - Align gestures

    private func alignDragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                var t = activeImage == 0 ? fromTransform : toTransform
                t.offset = CGSize(
                    width: t.lastOffset.width + value.translation.width,
                    height: t.lastOffset.height + value.translation.height
                )
                if activeImage == 0 { fromTransform = t } else { toTransform = t }
            }
            .onEnded { _ in
                if activeImage == 0 {
                    fromTransform.lastOffset = fromTransform.offset
                } else {
                    toTransform.lastOffset = toTransform.offset
                }
            }
    }

    private func alignMagnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                var t = activeImage == 0 ? fromTransform : toTransform
                t.scale = max(0.5, min(t.lastScale * value.magnification, 5.0))
                if activeImage == 0 { fromTransform = t } else { toTransform = t }
            }
            .onEnded { _ in
                if activeImage == 0 {
                    fromTransform.lastScale = fromTransform.scale
                } else {
                    toTransform.lastScale = toTransform.scale
                }
            }
    }

    private var placeholderImage: some View {
        Rectangle()
            .fill(Theme.surface)
            .overlay(
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.system(size: 30))
                    Text("No photo")
                        .font(.caption)
                }
                .foregroundColor(Color(hex: "475569"))
            )
    }

    // MARK: - Body Fat Analysis

    private var bodyFatSection: some View {
        VStack(spacing: 10) {
            if bodyFatLoading {
                HStack(spacing: 10) {
                    ProgressView().tint(Color(hex: "a855f7")).scaleEffect(0.8)
                    Text("Analyzing body composition...")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.subtle)
                    Spacer()
                }
                .padding(12)
                .background(Color(hex: "a855f7").opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.2)))
            } else if let result = bodyFatResult {
                bodyFatResultCard(result)
            } else {
                Button {
                    Task { await runBodyFatAnalysis() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "figure.stand")
                            .font(.system(size: 14, weight: .bold))
                        Text("Body Fat Analysis")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Color(hex: "a855f7").opacity(0.12))
                    .foregroundColor(Color(hex: "a855f7"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.3)))
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func bodyFatResultCard(_ result: BodyFatAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "figure.stand")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "a855f7"))
                Text("BODY FAT ANALYSIS")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
                Spacer()
                confidenceBadge(result.confidence)
                Button {
                    bodyFatResult = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
            }

            // Estimates
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(formatDisplayDate(fromDate))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.muted)
                    Text(result.fromEstimate)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Theme.muted)

                VStack(spacing: 4) {
                    Text(formatDisplayDate(toDate))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.muted)
                    Text(result.toEstimate)
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(Theme.accent)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 6)

            // Comparison
            Text(result.comparison)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "e2e8f0"))
                .fixedSize(horizontal: false, vertical: true)

            // Visual markers (evidence)
            if !result.visualMarkers.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    Text("VISUAL MARKERS")
                        .font(.system(size: 8, weight: .black)).tracking(1)
                        .foregroundColor(Theme.muted)
                    FlowLayout(spacing: 4) {
                        ForEach(result.visualMarkers, id: \.self) { marker in
                            Text(marker)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "e2e8f0"))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color(hex: "a855f7").opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }

            // Body area changes
            if !result.changes.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                ForEach(result.changes, id: \.area) { change in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(change.direction == "improved" ? Color(hex: "22c55e") :
                                  change.direction == "declined" ? Color(hex: "ef4444") :
                                  Color(hex: "94a3b8"))
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        Text(change.area.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 70, alignment: .leading)
                        Text(change.observation)
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // Muscle development
            if !result.muscleDevelopment.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "3b82f6"))
                    Text(result.muscleDevelopment)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "e2e8f0"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Stubborn fat
            if let stubborn = result.stubornFat, !stubborn.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "f59e0b"))
                    Text(stubborn)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "e2e8f0"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Actionable tip
            if !result.actionableTip.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "22c55e"))
                    Text(result.actionableTip)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "22c55e"))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(hex: "a855f7").opacity(0.06), Theme.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.3)))
    }

    private func confidenceBadge(_ confidence: String) -> some View {
        let (label, color): (String, String) = {
            switch confidence {
            case "high":   return ("HIGH", "22c55e")
            case "medium": return ("MED", "f59e0b")
            case "low":    return ("LOW", "ef4444")
            default:       return (confidence.uppercased(), "94a3b8")
            }
        }()
        return Text(label)
            .font(.system(size: 8, weight: .black)).tracking(0.5)
            .foregroundColor(Color(hex: color))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: color).opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func runBodyFatAnalysis() async {
        bodyFatLoading = true
        defer { bodyFatLoading = false }

        var images: [(Data, String)] = []

        // Collect photos from both dates
        let fromEntries = photoStore.entries(for: fromDate)
        let toEntries = photoStore.entries(for: toDate)

        for entry in fromEntries {
            if let img = photoStore.loadImage(for: entry),
               let data = img.jpegData(compressionQuality: 0.7) {
                images.append((data, "FROM (\(fromDate)) — \(entry.pose) pose"))
            }
        }
        for entry in toEntries {
            if let img = photoStore.loadImage(for: entry),
               let data = img.jpegData(compressionQuality: 0.7) {
                images.append((data, "TO (\(toDate)) — \(entry.pose) pose"))
            }
        }

        guard !images.isEmpty else { return }

        let systemPrompt = """
        You are an elite physique coach who has judged 500+ bodybuilding shows and assessed thousands of clients. You estimate body fat with clinical precision by reading visual markers — not guessing.

        You MUST respond with ONLY valid JSON, no markdown, no code fences, no extra text.
        Use this exact JSON structure:
        {
          "from_estimate": "16-18%",
          "to_estimate": "13-15%",
          "comparison": "2-3 sentences. Lead with the MOST visible change. Cite specific visual markers that changed (e.g. 'linea alba now visible', 'serratus emerging'). End with one clear statement on the rate of progress.",
          "confidence": "high|medium|low",
          "visual_markers": [
            "List every marker you used to arrive at the estimate, e.g. 'upper abs visible under direct light', 'no vascularity on forearms', 'oblique line faintly visible', 'love handles still present'"
          ],
          "muscle_development": "1 sentence on visible muscle changes between photos — size, density, separation. Cite specific muscles. E.g. 'Deltoid caps more pronounced, chest separation improved, lats visibly wider from back'",
          "changes": [
            {
              "area": "abs|obliques|chest|shoulders|arms|back|legs|face|vascularity|overall_leanness",
              "observation": "Specific observation citing what you SEE, not generic praise. E.g. 'Upper 4 abs visible, lower 2 still covered — subcutaneous fat remains below navel'",
              "direction": "improved|maintained|declined"
            }
          ],
          "stubborn_fat": "Where remaining fat sits and what it would take to lose it. E.g. 'Lower abs and love handles — last to go, typically requires 11-12% to fully reveal. Estimate 2-3 more weeks at current deficit.'",
          "actionable_tip": "ONE specific, practical recommendation. Not generic. E.g. 'Add 2 sets of hanging leg raises 3x/week to thicken the lower abs — they'll pop sooner when the fat comes off.'"
        }

        CRITICAL RULES — violating these makes the analysis useless:

        1. ESTIMATION METHOD (follow this decision tree):
           a. Check ab visibility: no abs = 20%+, faint upper abs = 16-18%, clear 4-pack = 14-16%, full 6-pack = 12-14%, deep ab separation + vascularity = 10-12%
           b. Check oblique lines: none = 18%+, faint = 15-17%, clear = 13-15%, deep cuts = 11-13%
           c. Check vascularity: none = 16%+, faint forearm veins = 14-16%, prominent forearm + bicep veins = 12-14%, road-map vascularity = <12%
           d. Check face: round jaw = 18%+, jawline visible = 15-17%, sharp jawline + hollow cheeks = 12-14%
           e. Check lower back: smooth = 18%+, some definition = 14-16%, Christmas tree emerging = 12-14%
           f. Cross-reference all markers. Your estimate range should be NO wider than 2-3%.

        2. HONESTY OVER ENCOURAGEMENT:
           - Do NOT round down to be nice. If someone is 16-18%, say 16-18%, not 14-16%.
           - If lighting is dramatically different between photos, flag it: "Confidence: medium — overhead lighting in TO photos may accentuate definition."
           - If the person hasn't changed much, say so. "Minimal visible change" is a valid and useful answer.

        3. VISUAL MARKERS (must list 4-6):
           - These are your EVIDENCE. List exactly what you see in each photo that justifies your estimate.
           - Example good markers: "serratus anterior visible", "lower ab veins emerging", "love handle crease still present", "deltoid striations under top lighting"
           - Example bad markers: "looks leaner" (too vague), "good muscle tone" (meaningless)

        4. CHANGES (include 4-6 body areas):
           - Each observation MUST describe what you literally see, not what you assume.
           - Compare the SAME body area across the two dates. If a pose is only available for one date, note it.
           - "maintained" is a valid and common direction — not everything changes in a few weeks.

        5. MUSCLE DEVELOPMENT:
           - This is separate from fat loss. Note any visible changes in muscle SIZE, DENSITY, or SEPARATION.
           - Cite specific muscles: "traps thicker", "lateral delt cap more rounded", "quads showing more sweep"
           - If no visible muscle change, say: "No significant muscle size changes visible — expected during a cut."

        6. STUBBORN FAT:
           - Identify WHERE remaining fat is concentrated (lower abs, love handles, lower back, inner thigh, chest).
           - Estimate what body fat % is needed to lose it from that specific area.
           - Be realistic about timelines.

        7. ACTIONABLE TIP:
           - ONE specific thing to do. Not "keep cutting" — that's obvious.
           - Could be: a training adjustment, a posing tip, a nutrition tweak, or a specific exercise to emphasize a muscle group.

        8. CONFIDENCE:
           - "high" = same lighting, same pose, clear visual markers in both photos
           - "medium" = different lighting/angles, or limited poses available
           - "low" = significantly different conditions making comparison unreliable
        """

        let userText = "Estimate my body fat percentage in the FROM photos (\(fromDate)) and TO photos (\(toDate)). Compare the two. Be brutally honest — I want accuracy, not encouragement."

        do {
            let response = try await ClaudeClient.shared.sendWithImages(
                systemPrompt: systemPrompt,
                userText: userText,
                images: images
            )
            bodyFatResult = parseBodyFatAnalysis(response)
        } catch {
            print("[AI] Body fat analysis error: \(error.localizedDescription)")
        }
    }

    private func parseBodyFatAnalysis(_ json: String) -> BodyFatAnalysis? {
        var cleaned = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") { cleaned = String(cleaned.dropFirst(7)) }
        else if cleaned.hasPrefix("```") { cleaned = String(cleaned.dropFirst(3)) }
        if cleaned.hasSuffix("```") { cleaned = String(cleaned.dropLast(3)) }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BodyFatAnalysis.self, from: data)
    }

    // MARK: - Helpers

    private static let isoDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let displayDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f
    }()

    private func formatDisplayDate(_ dateStr: String) -> String {
        guard let date = Self.isoDateFmt.date(from: dateStr) else { return dateStr }
        return Self.displayDateFmt.string(from: date)
    }
}

// MARK: - Clip shape for comparison slider

struct HorizontalClip: Shape {
    var rightEdge: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: rightEdge, height: rect.height))
    }
}

// MARK: - Body Fat Analysis Model

struct BodyFatAnalysis: Codable {
    let fromEstimate: String
    let toEstimate: String
    let comparison: String
    let confidence: String              // "high", "medium", "low"
    let visualMarkers: [String]         // what was used to estimate
    let muscleDevelopment: String       // 1 sentence on visible muscle changes
    let changes: [BodyFatChange]
    let stubornFat: String?             // where remaining fat sits
    let actionableTip: String           // 1 specific recommendation

    enum CodingKeys: String, CodingKey {
        case fromEstimate = "from_estimate"
        case toEstimate = "to_estimate"
        case comparison
        case confidence
        case visualMarkers = "visual_markers"
        case muscleDevelopment = "muscle_development"
        case changes
        case stubornFat = "stubborn_fat"
        case actionableTip = "actionable_tip"
    }

    struct BodyFatChange: Codable {
        let area: String
        let observation: String
        let direction: String
    }
}
