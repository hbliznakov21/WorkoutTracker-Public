import SwiftUI

enum AppTab {
    case home, history, prs, body, photos, reports
}

struct AppTabBar: View {
    @Environment(WorkoutStore.self) var store
    let active: AppTab

    var body: some View {
        HStack(spacing: 0) {
            tabBtn("house.fill",   "Home",    .home)    { store.activeScreen = .home }
            tabBtn("list.bullet",  "History", .history) { store.activeScreen = .history }
            tabBtn("trophy",       "PRs",     .prs)     { store.activeScreen = .prs }
            tabBtn("figure.stand", "Body",    .body)    { store.activeScreen = .body }
            tabBtn("camera.fill",  "Photos",  .photos)  { store.activeScreen = .photos }
            #if !SONYA
            tabBtn("chart.bar.fill", "Reports", .reports) { store.activeScreen = .reports }
            #endif
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(Divider().frame(maxWidth: .infinity), alignment: .top)
    }

    private func tabBtn(_ icon: String, _ label: String, _ tab: AppTab,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 20))
                Text(label).font(.system(size: 9, weight: .bold)).textCase(.uppercase)
            }
            .foregroundColor(tab == active ? Theme.accent : Theme.subtle)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(tab == active ? .isSelected : [])
    }
}
