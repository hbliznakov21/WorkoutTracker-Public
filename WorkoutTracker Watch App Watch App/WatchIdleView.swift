import SwiftUI

struct WatchIdleView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("⚡️")
                .font(.system(size: 40))
            Text("WorkoutTracker")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
            Text("Open iPhone\nto start")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
