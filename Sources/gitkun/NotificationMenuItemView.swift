import AppKit
import gitkunCore

final class NotificationMenuItemView: NSView {

    private static let itemWidth: CGFloat = 400
    private static let itemHeight: CGFloat = 52

    private let repoFullName: String
    private let detail: String?
    private let title: String
    private let updatedAt: String
    private let dotColor: NSColor
    private let onOpen: () -> Void
    private var trackingArea: NSTrackingArea?

    init(repoFullName: String,
         title: String,
         updatedAt: String,
         dotColor: NSColor = .systemGreen,
         detail: String? = nil,
         onOpen: @escaping () -> Void) {
        self.repoFullName = repoFullName
        self.detail = detail
        self.title = title
        self.updatedAt = updatedAt
        self.dotColor = dotColor
        self.onOpen = onOpen
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: Self.itemWidth,
                                 height: Self.itemHeight))
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - セットアップ（フレームベース）

    private func setup() {
        wantsLayer = true

        let pad: CGFloat = 14
        let dotSize: CGFloat = 8
        let h = Self.itemHeight

        // ドット
        let dot = NSView(frame: NSRect(x: pad, y: (h - dotSize) / 2,
                                      width: dotSize, height: dotSize))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = dotColor.cgColor
        dot.layer?.cornerRadius = dotSize / 2
        addSubview(dot)

        let textX = pad + dotSize + 8
        let textW = Self.itemWidth - textX - pad

        // リポジトリ名（上段）。種別があれば "owner/repo · Pull Request" の形で添える。
        let repoText = detail.map { "\(repoFullName) · \($0)" } ?? repoFullName
        let repo = makeLabel(repoText,
                             size: 11, color: .secondaryLabelColor)
        repo.lineBreakMode = .byTruncatingTail
        repo.frame = NSRect(x: textX, y: 32, width: textW, height: 14)
        addSubview(repo)

        // タイトル（中段）
        let titleLabel = makeLabel(title,
                                   size: 13, color: .labelColor)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: textX, y: 14, width: textW, height: 17)
        addSubview(titleLabel)

        // 相対時刻（下段）
        let time = makeLabel(relativeTime, size: 10, color: .tertiaryLabelColor)
        time.frame = NSRect(x: textX, y: 2, width: textW, height: 12)
        addSubview(time)
    }

    private func makeLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let f = NSTextField(labelWithString: text)
        f.font = .systemFont(ofSize: size)
        f.textColor = color
        f.maximumNumberOfLines = 1
        return f
    }

    private var relativeTime: String {
        RelativeTime.format(iso: updatedAt)
    }

    // MARK: - ホバーハイライト

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseEnteredAndExited, .activeAlways],
                                owner: self)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.selectedContentBackgroundColor.withAlphaComponent(0.8).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = nil
    }

    // MARK: - クリック

    override func mouseUp(with event: NSEvent) {
        onOpen()
        enclosingMenuItem?.menu?.cancelTracking()
    }
}
