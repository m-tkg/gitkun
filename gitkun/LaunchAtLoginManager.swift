import Foundation
import ServiceManagement

final class LaunchAtLoginManager: ObservableObject {

    @Published var isEnabled: Bool = false

    init() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func toggle() {
        do {
            if isEnabled {
                try SMAppService.mainApp.unregister()
                isEnabled = false
            } else {
                try SMAppService.mainApp.register()
                isEnabled = true
            }
        } catch {
            // 失敗した場合は現在のステータスを再取得
            isEnabled = (SMAppService.mainApp.status == .enabled)
        }
    }
}
