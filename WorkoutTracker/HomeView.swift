import SwiftUI
import UIKit

var statusBarHeight: CGFloat {
    UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first?.statusBarManager?.statusBarFrame.height ?? 44
}

struct HomeView: View {
    @Environment(WorkoutStore.self) var store
    @Environment(PhotoStore.self) var photoStore

    @State private var dashLoaded:    Bool   = false
    @State private var isRestDay:     Bool   = false
    @State private var showSummarySheet: Bool = false
    @State private var showQuickCamera: Bool  = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg
            ScrollView {
                VStack(spacing: 0) {
                    HomeHeroSection(
                        isRestDay: $isRestDay,
                        onStreakRecalc: { await store.computeStreak() },
                        showSummarySheet: $showSummarySheet
                    )
                    HomeStatsSection(
                        showQuickCamera: $showQuickCamera
                    )
                }
                .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            store.checkAndIncrementDeloadWeek()

            await store.loadRoutines()

            async let bw: () = store.loadBodyWeight()
            async let rd: () = store.loadRestDays()
            async let lp: () = store.loadLastPerformed()
            async let tc: () = store.checkTodayRoutineCompleted()
            #if !SONYA
            async let cw: () = store.loadCardioThisWeek()
            #endif

            #if SONYA
            let _ = await (bw, rd, lp, tc)
            #else
            let _ = await (bw, rd, lp, tc, cw)
            #endif

            isRestDay  = store.restDays.contains(Calendar.current.startOfDay(for: Date()))
            dashLoaded = true
        }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .home) }
        .sheet(isPresented: $showSummarySheet) {
            if let summary = store.lastFinishedSummary {
                WorkoutSummaryShareView(summary: summary) {
                    showSummarySheet = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: store.lastFinishedSummary) { _, newVal in
            if newVal != nil {
                showSummarySheet = true
            }
        }
        .fullScreenCover(isPresented: $showQuickCamera) {
            QuickPhotoCaptureView(photoStore: photoStore)
        }
    }

}

// MARK: - Quick Photo Capture (launched from Home card)

struct QuickPhotoCaptureView: View {
    let photoStore: PhotoStore
    @Environment(\.dismiss) var dismiss
    @State private var capturedImage: UIImage?
    @State private var selectedPose = "front"
    @State private var showCamera = false
    @State private var hasAppeared = false

    private let poses = ["front", "side", "back"]
    private let poseLabels = ["Front", "Side", "Back"]

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let img = capturedImage {
                VStack(spacing: 16) {
                    HStack {
                        Button { dismiss() } label: {
                            Text("Cancel")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Theme.subtle)
                        }
                        Spacer()
                        Text("Quick Photo")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                        Button {
                            let today = Self.isoFmt.string(from: Date())
                            photoStore.savePhoto(image: img, pose: selectedPose, date: today)
                            dismiss()
                        } label: {
                            Text("Save")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)

                    VStack(spacing: 8) {
                        Text("Pose")
                            .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                            .foregroundColor(Theme.subtle)
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
                    }
                    .padding(.horizontal, 16)

                    Button {
                        capturedImage = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(300))
                            showCamera = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text("Retake")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(Theme.subtle)
                    }
                    .padding(.top, 4)

                    Spacer()
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(Theme.accent)
                    Text("Opening camera...")
                        .font(.caption)
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .sheet(isPresented: $showCamera, onDismiss: {
            if capturedImage == nil {
                dismiss()
            }
        }) {
            CameraPicker(image: $capturedImage)
                .ignoresSafeArea()
        }
        .onAppear {
            guard !hasAppeared else { return }
            hasAppeared = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                showCamera = true
            }
        }
    }
}
