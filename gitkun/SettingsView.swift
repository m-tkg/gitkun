import SwiftUI
import AppKit

/// 設定画面（通知音・Launch at login）。
/// `@AppStorage` のキーは `LocalStore` と共有しており、保存先は同じ UserDefaults。
struct SettingsView: View {

    @ObservedObject var launchManager: LaunchAtLoginManager

    @AppStorage("unreadSoundName") private var unreadSoundName = "Glass"
    @AppStorage("reviewSoundName") private var reviewSoundName = "Glass"
    @AppStorage("updateSoundName") private var updateSoundName = "Glass"

    private let soundNames = SystemSounds.availableNames()

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

            Toggle("Launch at login", isOn: Binding(
                get: { launchManager.isEnabled },
                set: { newValue in
                    guard newValue != launchManager.isEnabled else { return }
                    launchManager.toggle()
                }
            ))
        }
        .padding(20)
        .frame(width: 360)
    }
}

/// macOS のシステムサウンド名を列挙する。
enum SystemSounds {
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
