import SwiftUI

/// ڕێکخستنەکان — سێنسیڤیتی، FPS، کوالیتی، کۆنترۆڵ
struct SettingsView: View {
    @EnvironmentObject var settings: GameSettings

    var body: some View {
        ZStack {
            GradientBackground()
            ScrollView {
                VStack(spacing: 16) {
                    // کۆنترۆڵ و سێنسیڤیتی
                    GlassCard {
                        VStack(spacing: 16) {
                            Label("کۆنترۆڵ و سێنسیڤیتی", systemImage: "hand.draw.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("سێنسیڤیتی ئامانجگرتن")
                                    Spacer()
                                    Text(String(format: "%.2f", settings.aimSensitivity))
                                }
                                Slider(value: $settings.aimSensitivity, in: 0.1...2.5, step: 0.05)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("سێنسیڤیتی سکۆپ (ADS)")
                                    Spacer()
                                    Text(String(format: "%.2f", settings.scopeSensitivity))
                                }
                                Slider(value: $settings.scopeSensitivity, in: 0.1...1.5, step: 0.05)
                            }

                            Toggle(isOn: $settings.invertY) {
                                Text("پێچەوانەکردنەوەی Y (سەر-خوار)")
                                    .foregroundStyle(.white)
                            }
                            Toggle(isOn: $settings.defaultTPP) {
                                Text("بینینی سێیەم کەس (TPP) وەک بنەڕەت")
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .frame(maxWidth: 460)

                    // وێنە و خێرایی
                    GlassCard {
                        VStack(spacing: 16) {
                            Label("وێنە و خێرایی", systemImage: "speedometer")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("کوالیتی وێنە")
                                    .foregroundStyle(.white.opacity(0.8))
                                Picker("", selection: $settings.quality) {
                                    ForEach(QualityLevel.allCases) { q in Text(q.rawValue).tag(q) }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("FPS")
                                    .foregroundStyle(.white.opacity(0.8))
                                Picker("", selection: $settings.fpsMode) {
                                    ForEach(FPSMode.allCases) { f in Text(f.rawValue).tag(f) }
                                }
                                .pickerStyle(.segmented)
                            }

                            Text("ئامێرەکەت: \(settings.deviceMaxFPS) FPS لە توانایدایە — 90/120 تەنها لە ئایفۆنە ProMotionـەکاندا کاردەکات. لە ئامێرە کۆنەکاندا خۆکارانە دادەبەزێت.")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: 460)

                    // دەنگ
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("دەنگ", systemImage: "speaker.wave.2.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Slider(value: $settings.volume, in: 0...1)
                        }
                    }
                    .frame(maxWidth: 460)

                    // ناو و دەربارە
                    GlassCard {
                        VStack(spacing: 12) {
                            HStack {
                                Text("ناوی یاریزانەکەت")
                                    .foregroundStyle(.white)
                                Spacer()
                                TextField("ناو", text: $settings.playerName)
                                    .multilineTextAlignment(.trailing)
                                    .foregroundStyle(.white)
                                    .frame(width: 150)
                            }
                            Divider().background(.white.opacity(0.2))
                            Text("دروستکراوە لەلایەن پەرەپێدەر — Telegram: lam_ham4")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: 460)
                }
                .padding()
            }
        }
        .navigationTitle("ڕێکخستنەکان")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
