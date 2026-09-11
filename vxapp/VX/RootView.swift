import SwiftUI

struct RootView: View {

    @StateObject private var model = WebModel()

    var body: some View {
        ZStack {
            Color(UIColor(hex: AppConfig.backgroundHex))
                .ignoresSafeArea()

            WebViewContainer(model: model)
                .opacity(model.didFinishFirstLoad ? 1 : 0)
                .animation(.easeIn(duration: 0.25), value: model.didFinishFirstLoad)

            // ---- شاشەی بارکردنی یەکەم ----
            if !model.didFinishFirstLoad && model.errorMessage == nil {
                SplashView(progress: model.progress)
                    .transition(.opacity)
            }

            // ---- شاشەی هەڵە ----
            if let message = model.errorMessage {
                ErrorView(message: message) {
                    model.reload()
                }
            }

            // ---- هێڵی پێشکەوتن لە سەرەوە ----
            if model.isLoading && model.didFinishFirstLoad {
                VStack {
                    ProgressBar(value: model.progress)
                        .frame(height: 2.5)
                    Spacer()
                }
                .ignoresSafeArea(edges: .horizontal)
            }
        }
        .statusBarHidden(false)
    }
}

// MARK: - شاشەی دەستپێک

private struct SplashView: View {
    let progress: Double
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.07, blue: 0.11),
                         Color(red: 0.13, green: 0.09, blue: 0.24)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 26) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.purple.opacity(0.45), .clear],
                                center: .center, startRadius: 4, endRadius: 90)
                        )
                        .frame(width: 180, height: 180)
                        .scaleEffect(pulse ? 1.08 : 0.92)

                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, Color(red: 0.65, green: 0.8, blue: 1.0)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                }

                Text("VX Chat")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                ProgressBar(value: max(progress, 0.06))
                    .frame(width: 170, height: 4)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - هێڵی پێشکەوتن

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(
                        colors: [Color(red: 0.45, green: 0.6, blue: 1.0),
                                 Color(red: 0.75, green: 0.45, blue: 1.0)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, min(1, value)) * geo.size.width)
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .clipShape(Capsule())
    }
}

// MARK: - شاشەی هەڵە

private struct ErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ZStack {
            Color(UIColor(hex: AppConfig.backgroundHex)).ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))

                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 36)
                    .environment(\.layoutDirection, .rightToLeft)

                Button(action: retry) {
                    Text("دووبارە هەوڵ بدەرەوە")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color(red: 0.45, green: 0.6, blue: 1.0),
                                             Color(red: 0.72, green: 0.42, blue: 1.0)],
                                    startPoint: .leading, endPoint: .trailing))
                        )
                }
                .padding(.top, 4)
            }
        }
    }
}
