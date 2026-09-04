import SwiftUI

/// مینیوی سەرەکی
struct MenuView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                VStack(spacing: 22) {
                    Spacer()
                    Image(systemName: "scope")
                        .font(.system(size: 64))
                        .foregroundStyle(AppTheme.accentGradient)
                    Text("Arena Strike")
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("١ڤ١ یان ١ڤ٤ — شەڕ لە ئەرێنای بچووکدا")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))

                    VStack(spacing: 14) {
                        NavigationLink {
                            SoloSetupView()
                        } label: {
                            MenuButtonLabel(icon: "person.fill",
                                            title: "تاکە یاری — ١ڤ٤ بۆت",
                                            subtitle: "تۆ بەرامبەر ٤ بۆت — ٤ ئاست")
                        }

                        NavigationLink {
                            LANLobbyView(mode: .host)
                        } label: {
                            MenuButtonLabel(icon: "antenna.radiowaves.left.and.right",
                                            title: "١ڤ١ — خانەخوێ (هەمان وایفای)",
                                            subtitle: "هاوڕێکەت دەبێتە میوان")
                        }

                        NavigationLink {
                            LANLobbyView(mode: .guest)
                        } label: {
                            MenuButtonLabel(icon: "person.2.fill",
                                            title: "١ڤ١ — میوان (بەشداری)",
                                            subtitle: "پەیوەندیکردن بە خانەخوێ")
                        }

                        NavigationLink {
                            SettingsView()
                        } label: {
                            MenuButtonLabel(icon: "gearshape.fill",
                                            title: "ڕێکخستنەکان",
                                            subtitle: "سێنسیڤیتی • FPS • کوالیتی")
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: 480)

                    Spacer()
                    Text("دروستکراوە لەلایەن پەرەپێدەر — Telegram: lam_ham4")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.bottom, 12)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

struct MenuButtonLabel: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(AppTheme.accentGradient)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
            Image(systemName: "chevron.left")
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

/// هەڵبژاردنی یاری تاکە — پێش دەستپێکردن
struct SoloSetupView: View {
    @EnvironmentObject var settings: GameSettings
    @State private var start = false

    var body: some View {
        ZStack {
            GradientBackground()
            ScrollView {
                VStack(spacing: 18) {
                    Text("تاکە یاری — ١ڤ٤")
                        .font(.title2.bold())
                        .foregroundStyle(.white)

                    GlassCard {
                        VStack(spacing: 14) {
                            Text("ئاستی بۆتەکان")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(BotLevel.allCases) { level in
                                Button {
                                    settings.botLevel = level
                                } label: {
                                    HStack {
                                        Text(level.title)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        if settings.botLevel == level {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(AppTheme.accentB)
                                        }
                                    }
                                    .padding(12)
                                    .background(settings.botLevel == level ? .white.opacity(0.15) : .white.opacity(0.05),
                                                in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 460)

                    GlassCard {
                        VStack(spacing: 14) {
                            HStack {
                                Text("قەبارەی ئەرێنا")
                                Spacer()
                                Picker("", selection: $settings.arenaSize) {
                                    ForEach(ArenaSize.allCases) { s in Text(s.rawValue).tag(s) }
                                }
                                .pickerStyle(.menu)
                            }
                            HStack {
                                Text("کاتی یاری: \(settings.matchMinutes) خولەک")
                                Spacer()
                                Stepper("", value: $settings.matchMinutes, in: 1...10).labelsHidden()
                            }
                            HStack {
                                Text("چەکی سەرەتایی")
                                Spacer()
                                Picker("", selection: $settings.defaultWeapon) {
                                    Text("M416").tag("M416")
                                    Text("AKM").tag("AKM")
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 160)
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .frame(maxWidth: 460)

                    Button {
                        start = true
                    } label: {
                        Label("دەستپێکردنی شەڕ 🎮", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(AppTheme.accentGradient, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 6)
                }
                .padding()
            }
        }
        .navigationTitle("تاکە یاری")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $start) {
            GameView(settings: settings, netSession: nil, netCfg: nil)
        }
    }
}
