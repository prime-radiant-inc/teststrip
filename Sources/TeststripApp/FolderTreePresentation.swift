import TeststripCore

/// A row in the hierarchical Folders sidebar tree, built entirely in memory
/// from the catalog's already-cached flat leaf-folder listing
/// (`CatalogRepository.folders()` / `AppModel.catalogFolders`). No catalog
/// queries happen here, so rebuilding the tree on every sidebar render is
/// safe - see `AppModel.folderTreeSidebarRows`.
///
/// Chains of directories that hold no photos of their own and have exactly
/// one child (e.g. a shared "/Volumes/NAS" mount prefix, or the path down to
/// a lone dated import folder) are collapsed into a single row, so the tree
/// starts at the first folder that's actually worth picking: a branch
/// point, or a folder that directly holds photos.
struct FolderTreeNode: Identifiable, Equatable {
    var fullPath: String
    var title: String
    var assetCount: Int
    var children: [FolderTreeNode]

    var id: String { fullPath }
    var hasChildren: Bool { !children.isEmpty }
}

enum FolderTreePresentation {
    /// Caps the number of sibling rows shown at any one level (top-level
    /// roots, or the children of an expanded folder) so a folder with an
    /// unusually large number of direct subfolders can't flood the sidebar.
    /// Combined with expand-on-demand flattening, this keeps the rendered
    /// tree bounded regardless of catalog size.
    static let maxRowsPerLevel = 100

    static func build(from folders: [CatalogFolder]) -> [FolderTreeNode] {
        let root = TrieNode()
        for folder in folders {
            let components = folder.path.split(separator: "/").map(String.init)
            guard !components.isEmpty else { continue }
            var node = root
            for component in components {
                if let existing = node.children[component] {
                    node = existing
                } else {
                    let child = TrieNode()
                    node.children[component] = child
                    node = child
                }
            }
            node.ownAssetCount += folder.assetCount
        }
        return sortedEntries(root.children).map { name, node in
            buildNode(name: name, node: node, ancestorComponents: [])
        }
    }

    private static func buildNode(
        name: String,
        node: TrieNode,
        ancestorComponents: [String]
    ) -> FolderTreeNode {
        var mergedComponents = [name]
        var currentNode = node
        while currentNode.ownAssetCount == 0,
              currentNode.children.count == 1,
              let onlyChild = currentNode.children.first {
            mergedComponents.append(onlyChild.key)
            currentNode = onlyChild.value
        }
        let allComponents = ancestorComponents + mergedComponents
        let children = sortedEntries(currentNode.children).map { childName, childNode in
            buildNode(name: childName, node: childNode, ancestorComponents: allComponents)
        }
        return FolderTreeNode(
            fullPath: "/" + allComponents.joined(separator: "/") + "/",
            title: mergedComponents[mergedComponents.count - 1],
            assetCount: totalAssetCount(currentNode),
            children: children
        )
    }

    private static func totalAssetCount(_ node: TrieNode) -> Int {
        node.ownAssetCount + node.children.values.reduce(0) { $0 + totalAssetCount($1) }
    }

    private static func sortedEntries(_ children: [String: TrieNode]) -> [(key: String, value: TrieNode)] {
        Array(
            children
                .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
                .prefix(maxRowsPerLevel)
        )
    }

    private final class TrieNode {
        var children: [String: TrieNode] = [:]
        var ownAssetCount = 0
    }
}
