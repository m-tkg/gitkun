import Foundation

/// システムサウンドのファイル名一覧から表示名一覧を作る純粋ロジック。
/// ディレクトリ列挙（IO）は呼び出し側（アプリ側）の責務。
public enum SystemSoundNames {

    /// `.aiff` のみを抽出し、拡張子を除いてソートする。空なら `["Glass"]` にフォールバックする。
    public static func names(fromFiles files: [String]) -> [String] {
        let names = files
            .filter { $0.hasSuffix(".aiff") }
            .map { ($0 as NSString).deletingPathExtension }
            .sorted()
        return names.isEmpty ? ["Glass"] : names
    }
}
