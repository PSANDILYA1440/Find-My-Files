
import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.055, green: 0.065, blue: 0.09)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.38, blue: 0.42),
                                Color(red: 0.95, green: 0.20, blue: 0.32)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Find My Files")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Your files. Your space.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.65))

                Button(action: {}) {
                    Label("Open a Folder", systemImage: "folder.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.92, green: 0.24, blue: 0.36))
                .padding(.top, 8)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 480)
    }
}
