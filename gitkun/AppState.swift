import Foundation
import Combine
import OSLog

private let logger = Logger(subsystem: "com.mtkg.gitkun", category: "AppState")

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published 状態

    @Published var notifications: [GitHubNotification] = []
    @Published var unreviewedPRs: [UnreviewedPR] = []
    @Published var myPRs: [AssignedItem] = []
    @Published var assignedIssues: [AssignedItem] = []
    @Published var status: AppStatus = .idle
    @Published var lastChecked: Date? = nil
    @Published var isFetching: Bool = false
    @Published var lastErrorDetail: String? = nil
    @Published var hasUnread: Bool = false
    @Published var hasUnreviewed: Bool = false
    /// 自分より新しいリリースが見つかったとき非 nil。
    @Published var availableUpdate: ReleaseInfo? = nil

    // MARK: - 依存オブジェクト

    let store = LocalStore.shared
    private let service = GitHubNotificationService()
    private var poller: Poller?
    /// 更新チェック用ポーラー（約1時間ごと）。
    private var updatePoller: Poller?
    let notifier = UserNotifier()
    let launchManager = LaunchAtLoginManager()
    private let selfUpdater: SelfUpdater

    private static let updateCheckInterval = 3600

    /// メニューに保持する通知・レビュー依頼の上限件数。
    private static let displayLimit = 20
    /// My PRs / Assigned Issues の保持上限件数。
    private static let itemLimit = 50

    /// 実行中アプリのバージョン（`CFBundleShortVersionString`）。
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - 初期化

    init() {
        self.selfUpdater = SelfUpdater(service: service)
    }

    /// 通知ポーリングと更新チェックを開始する。どちらも開始時に即時 1 回発火する。
    func startPolling() {
        let fetchPoller = Poller(interval: store.pollingInterval.rawValue) { [weak self] in
            Task { @MainActor in await self?.performFetch() }
        }
        poller = fetchPoller
        fetchPoller.start()

        let updateChecker = Poller(interval: Self.updateCheckInterval) { [weak self] in
            Task { @MainActor in await self?.checkForUpdate() }
        }
        updatePoller = updateChecker
        updateChecker.start()
    }

    // MARK: - 更新チェック

    /// 最新リリースを取得し、自バージョンより新しければ `availableUpdate` を更新する。
    /// 新バージョンを初めて検知したときだけバナー + 音を出す（同一バージョンでは再通知しない）。
    /// 補助機能のため、失敗時はログのみでステータスには影響させない。
    func checkForUpdate() async {
        do {
            let release = try await service.fetchLatestRelease()
            guard VersionComparator.isNewer(tag: release.tagName, than: currentVersion) else {
                availableUpdate = nil
                return
            }
            availableUpdate = release
            logger.info("Update available: \(release.tagName, privacy: .public) (current \(self.currentVersion, privacy: .public))")

            guard store.lastNotifiedReleaseTag != release.tagName else { return }
            store.lastNotifiedReleaseTag = release.tagName
            let url = URL(string: release.htmlUrl) ?? URL(string: "https://github.com")!
            notifier.send(title: "gitkun Update Available",
                          body: "\(release.tagName) is available (current \(currentVersion))",
                          url: url)
            if store.soundEnabled {
                notifier.playSound()
            }
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// 現在表示中の更新を適用する。成功時はアプリが終了するため戻らない。失敗時は throw。
    func performUpdate() async throws {
        guard let release = availableUpdate else { return }
        logger.info("Starting self-update to \(release.tagName, privacy: .public)")
        try await selfUpdater.performUpdate(to: release)
    }

    // MARK: - 削除

    func remove(notification: GitHubNotification) {
        notifications.removeAll { $0.id == notification.id }
        hasUnread = !notifications.isEmpty
    }

    func remove(unreviewedPR: UnreviewedPR) {
        unreviewedPRs.removeAll { $0.id == unreviewedPR.id }
        hasUnreviewed = !unreviewedPRs.isEmpty
    }

    func remove(assignedItem: AssignedItem) {
        myPRs.removeAll { $0.id == assignedItem.id }
        assignedIssues.removeAll { $0.id == assignedItem.id }
    }

    // MARK: - フェッチ

    func fetchNow() {
        Task { await performFetch() }
    }

    func performFetch() async {
        guard !isFetching else { return }
        isFetching = true
        status = .loading

        async let notifTask      = run { try await self.service.fetchNotifications() }
        async let prTask         = run { try await self.service.fetchUnreviewedPRs() }
        async let assignedTask   = run { try await self.service.fetchAssignedItems() }
        async let authoredTask   = run { try await self.service.fetchAuthoredPRs() }
        let (notifResult, prResult, assignedResult, authoredResult) =
            await (notifTask, prTask, assignedTask, authoredTask)

        let isFirst = store.isFirstFetch
        var errors = FetchErrors()

        if let fetched = errors.unwrap(notifResult) {
            handleFetchedNotifications(fetched, isFirstFetch: isFirst)
        }
        if let fetched = errors.unwrap(prResult) {
            handleFetchedUnreviewedPRs(fetched, isFirstFetch: isFirst)
        }
        let assignedFetched = errors.unwrap(assignedResult)
        let authoredFetched = errors.unwrap(authoredResult)
        if assignedFetched != nil || authoredFetched != nil {
            handleFetchedMyItems(assigned: assignedFetched, authoredPRs: authoredFetched)
        }

        if isFirst {
            store.isFirstFetch = false
        }

        if errors.isEmpty {
            status = .ok
            lastErrorDetail = nil
        } else {
            status = .error(errors.statusLabel)
            lastErrorDetail = errors.detail
        }
        lastChecked = Date()
        isFetching = false
    }

    /// throws を AppError 付きの Result に正規化する。
    private func run<T>(_ operation: @Sendable () async throws -> T) async -> Result<T, AppError> {
        do {
            return .success(try await operation())
        } catch let error as AppError {
            return .failure(error)
        } catch {
            return .failure(.fetchFailed(error.localizedDescription))
        }
    }

    // MARK: - 差分判定と通知

    private func handleFetchedNotifications(_ fetched: [GitHubNotification], isFirstFetch: Bool) {
        let (newOnes, nextKnown) = FetchDiff.newItems(fetched: fetched, known: store.knownIDs)
        store.knownIDs = nextKnown

        notifications = Array(fetched.prefix(Self.displayLimit))
        hasUnread = !notifications.isEmpty

        if isFirstFetch { return }
        notifyIfNew(newOnes, title: "GitHub Notifications")
    }

    private func handleFetchedUnreviewedPRs(_ fetched: [UnreviewedPR], isFirstFetch: Bool) {
        let (newOnes, nextKnown) = FetchDiff.newItems(fetched: fetched, known: store.knownUnreviewedIDs)
        store.knownUnreviewedIDs = nextKnown

        unreviewedPRs = Array(fetched.prefix(Self.displayLimit))
        hasUnreviewed = !unreviewedPRs.isEmpty

        if isFirstFetch { return }
        notifyIfNew(newOnes, title: "GitHub Review Requests")
    }

    private func handleFetchedMyItems(assigned: [AssignedItem]?, authoredPRs: [AssignedItem]?) {
        myPRs = FetchDiff.mergeMyPRs(assigned: assigned, authored: authoredPRs, limit: Self.itemLimit)

        // Issues: assigned 側のみ。assigned が失敗した場合は前回値を据え置き。
        if let assigned {
            assignedIssues = Array(assigned.filter { !$0.isPullRequest }.prefix(Self.itemLimit))
        }
    }

    /// 新規が 1 件以上あれば通知バナー + 音を出す。
    private func notifyIfNew<T: MenuRowDisplayable>(_ newOnes: [T], title: String) {
        guard let first = newOnes.first else { return }
        let extra = newOnes.count - 1
        let body = extra > 0 ? "\(first.displayTitle) (+\(extra) more)" : first.displayTitle
        notifier.send(title: title, body: body, url: first.webURL)
        if store.soundEnabled {
            notifier.playSound()
        }
    }
}

// MARK: - エラー集約

private struct FetchErrors {
    private(set) var details: [String] = []
    private(set) var labels: [String] = []

    var isEmpty: Bool { details.isEmpty }
    var detail: String { details.joined(separator: "\n") }
    var statusLabel: String { labels.joined(separator: ", ") }

    /// `Result` を unwrap し、失敗時は内部にエラーを蓄積して `nil` を返す。
    mutating func unwrap<T>(_ result: Result<T, AppError>) -> T? {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            details.append(error.errorDescription ?? "\(error)")
            labels.append(error.statusLabel)
            return nil
        }
    }
}
