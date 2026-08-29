import Foundation

struct CopyPasteConfig: Codable {
    var showList: Shortcut
    var search: Shortcut
    var maxHistory: Int

    static let `default` = CopyPasteConfig(
        showList: Shortcut(key: "L", modifiers: ["cmd"]),
        search: Shortcut(key: "F", modifiers: ["cmd"]),
        maxHistory: 200
    )
}
