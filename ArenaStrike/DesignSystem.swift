import SwiftUI

/// سیستەمی دیزاینی Arena Strike — ڕەنگ و گرادینتەکان
enum AppTheme {
    static let backgroundTop = Color(red: 0.03, green: 0.05, blue: 0.12)
    static let backgroundBottom = Color(red: 0.10, green: 0.07, blue: 0.20)
    static let accentA = Color(red: 0.95, green: 0.42, blue: 0.18)   // نارنجیی تەقینەوە
    static let accentB = Color(red: 0.03, green: 0.71, blue: 0.85)   // سایان

    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentA, accentB],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct GradientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(RadialGradient(colors: [AppTheme.accentA.opacity(0.30), .clear],
                                     center: .topLeading, startRadius: 10, endRadius: 420))
                .frame(width: 600, height: 600)
                .offset(x: -160, y: -260)
            Circle()
                .fill(RadialGradient(colors: [AppTheme.accentB.opacity(0.20), .clear],
                                     center: .center, startRadius: 10, endRadius: 440))
                .frame(width: 620, height: 620)
                .offset(x: 210, y: 400)
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            )
    }
}

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
            .background(AppTheme.accentGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.accentA.opacity(0.45), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3), value: configuration.isPressed)
    }
}
