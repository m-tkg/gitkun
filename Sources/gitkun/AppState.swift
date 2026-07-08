import Foundation
import gitkunCore
import Combine
import KunAppKit
import KunUpdateKit
import OSLog

private let logger = Logger(subsystem: logSubsystem, category: "AppState")

@MainActor
final class AppState: ObservableObject {

    // MARK: - Published 状態

    @Published var notifications: [GitHubNotification] = []
    @Published var unreviewedPRs: [UnreviewedPR] = []
    /// 現在レビュー依頼中の PR キー集合（`owner/repo#n`、WIP フィルタ前の生 search 結果由来）。
    /// `review_requested` 通知の再分類に使う。未取得・取得失敗時は nil（補正しない）。
    @Published var activeReviewKeys: Set<String>? = nil
    @Published var myPRs: [AssignedItem] = []
    @Published var assignedIssues: [AssignedItem] = []
    @Published var status: AppStatus = .idle
    @Published var lastChecked: Date? = nil
    @Published var isFetching: Bool = false
    @Published var lastErrorDetail: String? = nil
    /// 自分より新しいリリースが見つかったとき非 nil。
    @Published var availableUpdate: ReleaseInfo? = nil
    /// 最後に取得した最新リリースのタグ（新旧問わず）。設定画面の表示用。
    @Published var latestReleaseTag: String? = nil

    // MARK: - 依存オブジェクト

    let store = LocalStore.shared
    private let service = GitHubNotificationService()
    private var poller: Poller?
    /// 更新チェック用ポーラー（約1時間ごと）。
    private var updatePoller: Poller?
    let notifier = UserNotifier()
    let launchManager = LaunchAtLoginManager()
    private let selfUpdater: SelfUpdater

    /// 定期更新チェックの間隔（秒）。kunkit の共通スケジュール（6時間）に従う。
    /// `Poller` は Int 秒で受けるため TimeInterval を丸める。
    private static var updateCheckInterval: Int { Int(KunUpdateSchedule.checkInterval) }

    /// メニューに保持する通知・レビュー依頼の上限件数。
    static let displayLimit = 20
    /// My PRs / Assigned Issues の保持上限件数。
    private static let itemLimit = 50

    /// 実行中アプリのバージョン（`CFBundleShortVersionString`）。
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - 初期化

    init() {
        // 更新の DL・展開・入替・再起動は kunkit の共通実装（URLSession で公開アセットを DL）。
        self.selfUpdater = SelfUpdater(appName: "gitkun")
    }

    /// 通知ポーリングと更新チェックを開始する。どちらも開始時に即時 1 回発火する。
    func startPolling() {
        let fetchPoller = Poller(interval: store.pollingInterval) { [weak self] in
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

    /// 手動「Check for Updates…」の結果。バナーを出さず呼び出し側でダイアログ提示するために使う。
    enum UpdateCheckOutcome {
        case upToDate
        case available(ReleaseInfo)
        case failed(Error)
    }

    /// 最新リリースを取得し、自バージョンより新しければ `availableUpdate` を更新する。
    /// 更新があってもバナー通知は出さない（メニューの `⬆ Update to …` 項目で知らせる）。
    /// 補助機能のため、失敗時はログのみでステータスには影響させない。
    @discardableResult
    func checkForUpdate() async -> UpdateCheckOutcome {
        do {
            let release = try await service.fetchLatestRelease()
            latestReleaseTag = release.tagName
            guard VersionComparator.isNewer(tag: release.tagName, than: currentVersion) else {
                availableUpdate = nil
                return .upToDate
            }
            availableUpdate = release
            logger.info("Update available: \(release.tagName, privacy: .public) (current \(self.currentVersion, privacy: .public))")
            return .available(release)
        } catch {
            logger.error("Update check failed: \(error.localizedDescription, privacy: .public)")
            return .failed(error)
        }
    }

    /// 現在表示中の更新を適用する。成功時はアプリが終了するため戻らない。失敗時は throw。
    func performUpdate() async throws {
        guard let release = availableUpdate else { return }
        logger.info("Starting self-update to \(release.tagName, privacy: .public)")
        try await selfUpdater.performUpdate(to: release)
    }

    // MARK: - フェッチ

    /// 手動 Refresh。通常のフェッチに加えて最新リリースの確認も行う。
    func fetchNow() {
        Task {
            await performFetch()
            await checkForUpdate()
        }
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

        if isFirstFetch { return }
        notifyIfNew(newOnes, title: "GitHub Notifications", soundName: store.unreadSoundName)
    }

    private func handleFetchedUnreviewedPRs(_ fetched: [UnreviewedPR], isFirstFetch: Bool) {
        // 通知の review_requested 再分類用に、フィルタ前の全件からキー集合を作る
        // （WIP・上限の影響を受けない「現在依頼中」の正確な集合）。
        activeReviewKeys = Set(fetched.map(\.prKey))

        // draft / タイトル先頭 [WIP] / wip ラベルの除外（設定で ON/OFF、デフォルト ON）
        let filtered = store.excludeWIP ? fetched.filter(\.isReviewWaiting) : fetched
        let (newOnes, nextKnown) = FetchDiff.newItems(fetched: filtered, known: store.knownUnreviewedIDs)
        store.knownUnreviewedIDs = nextKnown

        // 上の filtered は既に WIP フィルタ済みなので、ここでは prefix のみ適用（excludeWIP: false）。
        unreviewedPRs = FetchDiff.reviewRequests(fetched: filtered, excludeWIP: false, limit: Self.displayLimit)

        if isFirstFetch { return }
        notifyIfNew(newOnes, title: "GitHub Review Requests", soundName: store.reviewSoundName)
    }

    private func handleFetchedMyItems(assigned: [AssignedItem]?, authoredPRs: [AssignedItem]?) {
        myPRs = FetchDiff.mergeMyPRs(assigned: assigned, authored: authoredPRs, limit: Self.itemLimit)

        // Issues: assigned 側のみ。assigned が失敗した場合は前回値を据え置き。
        if let assigned {
            assignedIssues = FetchDiff.assignedIssues(from: assigned, limit: Self.itemLimit)
        }
    }

    /// 新規が 1 件以上あれば通知バナー + 音を出す。
    private func notifyIfNew<T: MenuRowDisplayable>(_ newOnes: [T], title: String, soundName: String) {
        guard let first = newOnes.first else { return }
        guard let body = NotificationBanner.body(for: newOnes as [any MenuRowDisplayable]) else { return }
        notifier.send(title: title, body: body, url: first.webURL)
        notifier.playSound(named: soundName)
    }
}
