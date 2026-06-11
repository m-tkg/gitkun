import SwiftUI
import AppKit

/// 通知音の設定画面（Settings シーン）。
/// `@AppStorage` のキーは `LocalStore` と共有しており、保存先は同じ UserDefaults。
struct SettingsView: View {

    @AppStorage("unreadSoundName") private var unreadSoundName = "Glass"
    @AppStorage("reviewSoundName") private var reviewSoundName = "Glass"

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
