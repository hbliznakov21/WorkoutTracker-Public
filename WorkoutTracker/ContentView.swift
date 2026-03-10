import SwiftUI

// RootView handles top-level navigation between screens
struct RootView: View {
    @Environment(WorkoutStore.self) var store

    private var showError: Bool {
        store.errorMessage != nil
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                switch store.activeScreen {
                case .home:
                    HomeView()
                case .choose:
                    ChooseRoutineView()
                case .workout:
                    ActiveWorkoutView()
                case .cardio:
                    ActiveCardioView()
                case .history:
                    HistoryView()
                case .detail(let id):
                    WorkoutDetailView(workoutId: id)
                case .prs:
                    PRsView()
                case .week:
                    WeeklyView()
                case .body:
                    BodyView()
                case .progress(let name):
                    ExerciseProgressView(exerciseName: name)
                case .editRoutine(let id):
                    RoutineEditorView(routineId: id)
                case .exercises:
                    ExerciseListView()
                case .scheduleEditor:
                    ScheduleEditorView()
                case .photos:
                    PhotoProgressView()
                case .photoCompare:
                    PhotoCompareView()
                case .muscleBalance:
                    MuscleBalanceView()
                case .overloadTracker:
                    OverloadTrackerView()
                case .prTimeline:
                    PRTimelineView()
                case .durationAnalytics:
                    DurationAnalyticsView()
                case .exerciseSubstitutions:
                    SubstitutionView()
                case .muscleVolume:
                    MuscleVolumeView()
                case .bodyComposition:
                    BodyCompositionView()
                case .reports:
                    ReportsView()
                }
            }
        }
        .alert("Error", isPresented: Binding(get: { showError }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .fullScreenCover(isPresented: $store.showPostWorkoutAnalysis) {
            if let wkId = store.analysisWorkoutId {
                PostWorkoutAnalysisView(
                    workoutId: wkId,
                    routineName: store.analysisRoutineName,
                    sets: store.analysisSets,
                    onDismiss: {
                        store.showPostWorkoutAnalysis = false
                        store.analysisWorkoutId = nil
                        store.analysisSets = []
                    }
                )
                .environment(store)
            }
        }
    }
}
