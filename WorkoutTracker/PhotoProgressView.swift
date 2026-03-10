import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

extension String: @retroactive Identifiable {
    public var id: String { self }
}

struct PickableImage: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickableImage(data: data)
        }
    }

    /// Extract EXIF DateTimeOriginal from image data
    var creationDate: Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let dateStr = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        return Self.exifFmt.date(from: dateStr)
    }

    private static let exifFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Camera picker wrapper

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            parent.image = info[.originalImage] as? UIImage
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photo Progress View

struct PhotoProgressView: View {
    @Environment(WorkoutStore.self) var store
    @Environment(PhotoStore.self) var photoStore

    @State private var showingCapture = false
    @State private var captureStep = 0  // 0=front, 1=side, 2=back
    @State private var capturedImages: [UIImage?] = [nil, nil, nil]
    @State private var showingPreview = false
    @State private var showingCamera = false
    @State private var currentWeight: Double?
    @State private var selectedDate: String? = nil
    @State private var editingSessionDate: Date = Date()
    @State private var showingDateEdit = false
    @State private var dateEditOriginal: String = ""
    @State private var showingLibraryPicker = false
    @State private var libraryStep = 0  // 0=front, 1=side, 2=back
    @State private var libraryPickerItems: [PhotosPickerItem] = []
    @State private var isLibraryImport = false
    @State private var importDate = Date()
    @State private var photoInsight: PhotoInsight?
    @State private var photoInsightLoading = false
    @State private var showPhotoInsight = false

    private let poses = ["front", "side", "back"]
    private let poseLabels = ["Front", "Side", "Back"]

    private static let isoDateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let displayDateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"; return f
    }()

    private var todayDate: String {
        Self.isoDateFmt.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 16) {
                    newSessionButton
                    if photoStore.allDates.count >= 2 {
                        aiCompareButton
                    }
                    if !photoStore.allDates.isEmpty {
                        gallerySection
                    } else {
                        emptyState
                    }
                }
                .padding(.bottom, 32)
            }
            .background(Theme.bg)
        }
        .background(Theme.surface)
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showingCamera) {
            TimerCameraView(
                image: $capturedImages[captureStep],
                poseLabel: poseLabels[captureStep]
            )
            .ignoresSafeArea()
            .onDisappear {
                if capturedImages[captureStep] != nil {
                    if captureStep < 2 {
                        captureStep += 1
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            showingCamera = true
                        }
                    } else {
                        showingPreview = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingPreview) {
            previewSheet
        }
        .sheet(item: $selectedDate) { date in
            dateDetailSheet(date: date)
        }
        .sheet(isPresented: $showingLibraryPicker) {
            libraryPickerSheet
        }
        .sheet(isPresented: $showPhotoInsight) {
            if let insight = photoInsight {
                photoInsightSheet(insight)
            }
        }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .photos) }
        .task { await loadCachedPhotoInsight() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Progress Photos")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(.white)
            Text("\(photoStore.allDates.count) session\(photoStore.allDates.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundColor(Theme.subtle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, statusBarHeight + 16)
        .padding(.bottom, 12)
        .overlay(Divider().frame(maxWidth: .infinity).background(Theme.border), alignment: .bottom)
    }

    // MARK: - New Session Buttons

    private var newSessionButton: some View {
        HStack(spacing: 10) {
            Button {
                captureStep = 0
                capturedImages = [nil, nil, nil]
                isLibraryImport = false
                showingCamera = true
                Task { currentWeight = await photoStore.latestWeight() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Camera")
                        .font(.headline).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.accent)
                .foregroundColor(.black)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Button {
                captureStep = 0
                capturedImages = [nil, nil, nil]
                libraryStep = 0
                isLibraryImport = true
                importDate = Date()
                showingLibraryPicker = true
                Task { currentWeight = await photoStore.latestWeight() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 16, weight: .bold))
                    Text("Library")
                        .font(.headline).fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .foregroundColor(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.accent))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Gallery

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gallery")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
                Spacer()
                if photoStore.allDates.count >= 2 {
                    Button { store.activeScreen = .photoCompare } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Compare")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 16)

            ForEach(photoStore.allDates, id: \.self) { date in
                dateCard(date: date)
            }
        }
    }

    private func dateCard(date: String) -> some View {
        let dateEntries = photoStore.entries(for: date)
        let weight = dateEntries.first?.weightKg

        return Button {
            selectedDate = date
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(formatDisplayDate(date))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if let w = weight {
                        Text(String(format: "%.1f kg", w))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    ForEach(poses, id: \.self) { pose in
                        if let entry = dateEntries.first(where: { $0.pose == pose }),
                           let img = photoStore.loadImage(for: entry) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Theme.border)
                                .frame(height: 100)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(Theme.muted)
                                )
                        }
                    }
                }
            }
            .padding(14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 40))
                .foregroundColor(Theme.border)
            Text("No photos yet")
                .font(.headline)
                .foregroundColor(Theme.muted)
            Text("Tap New Session to capture\nfront, side & back poses")
                .font(.caption)
                .foregroundColor(Color(hex: "475569"))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    // MARK: - Preview Sheet

    private var saveDate: String {
        isLibraryImport ? Self.isoDateFmt.string(from: importDate) : todayDate
    }

    private var previewSheet: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if isLibraryImport {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("DATE")
                                    .font(.system(size: 10, weight: .bold)).tracking(1.5)
                                    .foregroundColor(Theme.subtle)
                                DatePicker("", selection: $importDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(Theme.accent)
                            }
                            .padding(.horizontal, 16)
                        }

                        HStack {
                            Text(formatDisplayDate(saveDate))
                                .font(.headline).foregroundColor(.white)
                            Spacer()
                            if let w = currentWeight {
                                Text(String(format: "%.1f kg", w))
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 16)

                        ForEach(0..<3, id: \.self) { i in
                            if let img = capturedImages[i] {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(poseLabels[i])
                                        .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                                        .foregroundColor(Theme.subtle)
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { showingPreview = false }
                        .foregroundColor(Color(hex: "f87171"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var images: [(UIImage, String)] = []
                        for i in 0..<3 {
                            if let img = capturedImages[i] {
                                images.append((img, poses[i]))
                            }
                        }
                        photoStore.saveSession(images: images, date: saveDate, weightKg: currentWeight)
                        showingPreview = false
                    }
                    .fontWeight(.bold)
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Date detail sheet

    private func dateDetailSheet(date: String) -> some View {
        let dateEntries = photoStore.entries(for: date)
        return NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        HStack {
                            if showingDateEdit {
                                DatePicker("", selection: $editingSessionDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .tint(Theme.accent)
                                Spacer()
                                Button("Save") {
                                    let newDate = Self.isoDateFmt.string(from: editingSessionDate)
                                    photoStore.reassignSessionDate(from: date, to: newDate)
                                    selectedDate = nil
                                    showingDateEdit = false
                                }
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.accent)
                            } else {
                                Text(formatDisplayDate(date))
                                    .font(.headline).foregroundColor(.white)
                                Button {
                                    editingSessionDate = Self.isoDateFmt.date(from: date) ?? Date()
                                    dateEditOriginal = date
                                    showingDateEdit = true
                                } label: {
                                    Image(systemName: "calendar.badge.clock")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.accent)
                                }
                                Spacer()
                                if let w = dateEntries.first?.weightKg {
                                    Text(String(format: "%.1f kg", w))
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(Theme.accent)
                                }
                            }
                        }
                        .padding(.horizontal, 16)

                        ForEach(dateEntries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(entry.pose.capitalized)
                                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                                    .foregroundColor(Theme.subtle)
                                if let img = photoStore.loadImage(for: entry) {
                                    Image(uiImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        selectedDate = nil
                        showingDateEdit = false
                    }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button {
                        photoStore.deleteSession(date: date)
                        selectedDate = nil
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(Color(hex: "f87171"))
                    }
                }
            }
        }
    }


    // MARK: - AI Compare

    private var aiCompareButton: some View {
        Button {
            if photoInsight != nil {
                showPhotoInsight = true
            } else {
                Task { await requestPhotoComparison() }
            }
        } label: {
            HStack(spacing: 10) {
                if photoInsightLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    if photoInsightLoading {
                        Text("Analyzing photos...")
                            .font(.system(size: 15, weight: .bold))
                    } else if photoInsight != nil {
                        Text("View AI Analysis")
                            .font(.system(size: 15, weight: .bold))
                        Text("Tap to see results")
                            .font(.system(size: 11))
                            .opacity(0.7)
                    } else {
                        Text("AI Progress Analysis")
                            .font(.system(size: 15, weight: .bold))
                        Text("Compare latest vs previous session")
                            .font(.system(size: 11))
                            .opacity(0.7)
                    }
                }
                Spacer()
                if !photoInsightLoading {
                    if photoInsight != nil {
                        // "New" button to force re-analyze
                        Button {
                            Task { await requestPhotoComparison(forceRefresh: true) }
                        } label: {
                            Text("New")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: photoInsight != nil
                        ? [Color(hex: "22c55e"), Color(hex: "16a34a")]
                        : [Color(hex: "8b5cf6"), Color(hex: "6366f1")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(photoInsightLoading)
        .padding(.horizontal, 16)
    }

    private func loadCachedPhotoInsight() async {
        let dates = photoStore.allDates
        guard dates.count >= 2 else { return }
        let latestDate = dates[0]
        if let cached = await store.loadCachedPhotoInsight(latestDate: latestDate) {
            photoInsight = cached
        }
    }

    private func requestPhotoComparison(forceRefresh: Bool = false) async {
        let dates = photoStore.allDates
        guard dates.count >= 2 else { return }
        let latestDate = dates[0]
        let previousDate = dates[1]

        // Delete old cache if forcing refresh
        if forceRefresh {
            photoInsight = nil
            let cacheKey = "photo_insight_\(latestDate)"
            let encoded = cacheKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cacheKey
            try? await store.sb.delete("session_goals?routine_name=eq.\(encoded)")
        }

        photoInsightLoading = true
        defer { photoInsightLoading = false }

        let latestEntries = photoStore.entries(for: latestDate)
        let previousEntries = photoStore.entries(for: previousDate)

        // Load images as JPEG data (smaller for API)
        var latestImages: [(Data, String)] = []
        var previousImages: [(Data, String)] = []

        for entry in latestEntries {
            if let img = photoStore.loadImage(for: entry),
               let data = img.jpegData(compressionQuality: 0.5) {
                latestImages.append((data, entry.pose))
            }
        }
        for entry in previousEntries {
            if let img = photoStore.loadImage(for: entry),
               let data = img.jpegData(compressionQuality: 0.5) {
                previousImages.append((data, entry.pose))
            }
        }

        guard !latestImages.isEmpty, !previousImages.isEmpty else { return }

        if let result = await store.generatePhotoComparison(
            latestImages: latestImages,
            previousImages: previousImages,
            latestDate: latestDate,
            previousDate: previousDate
        ) {
            photoInsight = result
            showPhotoInsight = true
        }
    }

    private func photoInsightSheet(_ insight: PhotoInsight) -> some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        // Progress badge
                        HStack {
                            Text(insight.progressLabel)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: insight.progressColor))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(hex: insight.progressColor).opacity(0.15))
                                .clipShape(Capsule())
                            Spacer()
                        }
                        .padding(.horizontal, 16)

                        // Summary
                        Text(insight.summary)
                            .font(.system(size: 15))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)

                        // Changes
                        VStack(spacing: 0) {
                            ForEach(insight.changes) { change in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: directionIcon(change.direction))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(directionColor(change.direction))
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(change.area.capitalized)
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundColor(.white)
                                        Text(change.observation)
                                            .font(.system(size: 13))
                                            .foregroundColor(Theme.subtle)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 14)

                                if change.id != insight.changes.last?.id {
                                    Divider().background(Theme.border)
                                        .padding(.leading, 50)
                                }
                            }
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .padding(.horizontal, 16)

                        // Encouragement
                        Text(insight.encouragement)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "a78bfa"))
                            .italic()
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("AI Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showPhotoInsight = false }
                        .fontWeight(.bold)
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func directionIcon(_ direction: String) -> String {
        switch direction {
        case "improved": return "arrow.up.circle.fill"
        case "declined": return "arrow.down.circle.fill"
        default:         return "equal.circle.fill"
        }
    }

    private func directionColor(_ direction: String) -> Color {
        switch direction {
        case "improved": return Color(hex: "22c55e")
        case "declined": return Color(hex: "ef4444")
        default:         return Color(hex: "f59e0b")
        }
    }

    // MARK: - Library Picker Sheet

    private var libraryPickerSheet: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 20) {
                    Text("Select \(poseLabels[libraryStep]) Photo")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text("Step \(libraryStep + 1) of 3")
                        .font(.subheadline)
                        .foregroundColor(Theme.subtle)

                    PhotosPicker(
                        selection: Binding(
                            get: { libraryPickerItems },
                            set: { newItems in
                                libraryPickerItems = newItems
                                guard let item = newItems.first else { return }
                                Task {
                                    if let picked = try? await item.loadTransferable(type: PickableImage.self),
                                       let img = UIImage(data: picked.data) {
                                        // Extract EXIF date from first photo
                                        if libraryStep == 0, let created = picked.creationDate {
                                            importDate = created
                                        }
                                        capturedImages[libraryStep] = img
                                        if libraryStep < 2 {
                                            libraryStep += 1
                                            libraryPickerItems = []
                                        } else {
                                            showingLibraryPicker = false
                                            libraryPickerItems = []
                                            showingPreview = true
                                        }
                                    }
                                }
                            }
                        ),
                        maxSelectionCount: 1,
                        matching: .images
                    ) {
                        HStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 16, weight: .bold))
                            Text("Choose \(poseLabels[libraryStep])")
                                .font(.headline).fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 16)

                    // Show already picked poses
                    if libraryStep > 0 {
                        VStack(spacing: 8) {
                            ForEach(0..<libraryStep, id: \.self) { i in
                                if let img = capturedImages[i] {
                                    HStack(spacing: 12) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 50, height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        Text(poseLabels[i])
                                            .font(.subheadline).fontWeight(.semibold)
                                            .foregroundColor(.white)
                                        Spacer()
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(Theme.accent)
                                    }
                                    .padding(10)
                                    .background(Theme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    Spacer()

                    if libraryStep > 0 {
                        Button {
                            // Skip remaining poses and go to preview
                            showingLibraryPicker = false
                            libraryPickerItems = []
                            showingPreview = true
                        } label: {
                            Text("Skip remaining — save \(libraryStep) photo\(libraryStep == 1 ? "" : "s")")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(Theme.subtle)
                        }
                        .padding(.bottom, 16)
                    }
                }
                .padding(.top, 24)
            }
            .navigationTitle("Import from Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingLibraryPicker = false
                        libraryPickerItems = []
                    }
                    .foregroundColor(Theme.subtle)
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDisplayDate(_ dateStr: String) -> String {
        guard let date = Self.isoDateFmt.date(from: dateStr) else { return dateStr }
        return Self.displayDateFmt.string(from: date)
    }
}
