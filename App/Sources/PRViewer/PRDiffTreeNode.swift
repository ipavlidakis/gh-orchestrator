import Foundation

struct PRDiffTreeNode: Identifiable, Equatable {
    let id: String
    let name: String
    let children: [Self]?

    var filePaths: [String] { children?.flatMap(\.filePaths) ?? [id] }

    static func nodes(paths: [String], parent: String = "") -> [Self] {
        Dictionary(grouping: paths, by: { String($0.prefix { $0 != "/" }) }).map { name, paths in
            let nested = paths.filter { $0 != name }.map { String($0.dropFirst(name.count + 1)) }
            var children = nested.isEmpty ? nil : nodes(paths: nested, parent: parent + name + "/")
            var label = name, id = parent + name
            while let folders = children, folders.count == 1, let descendants = folders[0].children {
                label += "/" + folders[0].name; id = folders[0].id; children = descendants
            }
            return Self(id: id, name: label, children: children)
        }.sorted {
            if ($0.children != nil) != ($1.children != nil) { return $0.children != nil }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
