import SwiftUI
import AppKit

/// 設定画面（通知音・Launch at login・バージョン情報）。
/// `@AppStorage` のキーは `LocalStore` と共有しており、保存先は同じ UserDefaults。
struct SettingsView: View {

    @ObservedObject var appState: AppState
    @ObservedObject var launchManager: LaunchAtLoginManager

    @AppStorage("unreadSoundName") private var unreadSoundName = "Glass"
    @AppStorage("reviewSoundName") private var reviewSoundName = "Glass"
    @AppStorage("updateSoundName") private var updateSoundName = "Glass"
    @AppStorage("excludeWIP") private var excludeWIP = true

    /// 先頭に「鳴らさない」を表す N/A を置く
    private let soundNames = [SystemSounds.noSound] + SystemSounds.availableNames()

    var body: some View {
        Form {
            Picker("Unread notification sound:", selection: $unreadSoundName) {
                ForEach(soundNames, id: \.self) { Text($0) }
            }
            .onChange(of: unreadSoundName) { NSSound(named: $0)?.play() }

            Picker("Review request sound:", selection: $reviewSoundName) {
                ForEach(soundNames, id: \.self) { Text($0) }
            }
            .onChange(of: reviewSoundName) { NSSound(named: $0)?.play() }

            Picker("Update available sound:", selection: $updateSoundName) {
                ForEach(soundNames, id: \.self) { Text($0) }
            }
            .onChange(of: updateSoundName) { NSSound(named: $0)?.play() }

            Divider()

            Toggle("Exclude draft / WIP PRs from review requests", isOn: $excludeWIP)

            Toggle("Launch at login", isOn: Binding(
                get: { launchManager.isEnabled },
                set: { newValue in
                    guard newValue != launchManager.isEnabled else { return }
                    launchManager.toggle()
                }
            ))

            Divider()

            Text("Current version: \(appState.currentVersion)")
                .foregroundColor(.secondary)
            Text("Latest release: \(appState.latestReleaseTag ?? "—")")
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// macOS のシステムサウンド名を列挙する。
enum SystemSounds {

    /// 「音を鳴らさない」を表す選択肢。実在するサウンド名ではない。
    static let noSound = "N/A"

    static func availableNames() -> [String] {
        let dir = "/System/Library/Sounds"
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let names = files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
        return names.isEmpty ? ["Glass"] : names
    }
}
