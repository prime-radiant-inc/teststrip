#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Teststrip}"
IMPORT_DIR="${2:-}"

if [[ -z "$IMPORT_DIR" || ! -d "$IMPORT_DIR" ]]; then
  echo "usage: $0 [APP_NAME] IMPORT_DIR" >&2
  exit 2
fi

IMPORT_DIR="$(cd "$IMPORT_DIR" && pwd)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/activate_app.sh" "$APP_NAME"

TESTSTRIP_AX_APP_NAME="$APP_NAME" \
TESTSTRIP_AX_IMPORT_DIR="$IMPORT_DIR" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let importPath = ProcessInfo.processInfo.environment["TESTSTRIP_AX_IMPORT_DIR"]!

guard AXIsProcessTrusted() else {
    fputs("Accessibility is not trusted for this process\n", stderr)
    exit(2)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    fputs("No running app named \(appName)\n", stderr)
    exit(1)
}
_ = app.activate(options: [.activateAllWindows])
RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))

let root = AXUIElementCreateApplication(app.processIdentifier)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return result == .success ? value : nil
}

func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
    guard let value = attribute(element, name) else { return nil }
    return (value as! AXUIElement)
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func children(of element: AXUIElement) -> [AXUIElement] {
    let directChildren = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let navigationChildren = attribute(element, "AXChildrenInNavigationOrder") as? [AXUIElement] ?? []
    let visibleChildren = attribute(element, kAXVisibleChildrenAttribute) as? [AXUIElement] ?? []
    let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    var seen = Set<AXElementKey>()
    var uniqueChildren: [AXUIElement] = []
    for child in directChildren + navigationChildren + visibleChildren + windows {
        let key = AXElementKey(element: child)
        guard seen.insert(key).inserted else { continue }
        uniqueChildren.append(child)
    }
    return uniqueChildren
}

func accessibleText(_ element: AXUIElement) -> String? {
    stringAttribute(element, kAXTitleAttribute)
        ?? stringAttribute(element, kAXDescriptionAttribute)
        ?? stringAttribute(element, kAXValueAttribute)
}

// AXUIElement wrappers are fresh objects on every attribute copy, and freed
// wrapper addresses get recycled, so ObjectIdentifier both misses real
// duplicates and falsely marks unvisited elements as seen. Identity must
// come from CFEqual/CFHash on the underlying accessibility element.
struct AXElementKey: Hashable {
    let element: AXUIElement
    static func == (lhs: AXElementKey, rhs: AXElementKey) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Bool) -> AXUIElement? {
    var visited = Set<AXElementKey>()
    var stack = [element]
    while let current = stack.popLast() {
        let key = AXElementKey(element: current)
        guard visited.insert(key).inserted else { continue }
        if visit(current) {
            return current
        }
        stack.append(contentsOf: children(of: current).reversed())
    }
    return nil
}

func waitFor(timeout seconds: TimeInterval = 15, _ predicate: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if predicate() {
            return true
        }
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return false
}

func hasAncestor(_ element: AXUIElement, role targetRole: String) -> Bool {
    var current = elementAttribute(element, kAXParentAttribute)
    while let element = current {
        if stringAttribute(element, kAXRoleAttribute) == targetRole {
            return true
        }
        current = elementAttribute(element, kAXParentAttribute)
    }
    return false
}

func button(named label: String, insideSheet: Bool? = nil) -> AXUIElement? {
    walk(root) { element in
        guard stringAttribute(element, kAXRoleAttribute) == kAXButtonRole,
              accessibleText(element) == label else {
            return false
        }
        if let insideSheet {
            return hasAncestor(element, role: kAXSheetRole) == insideSheet
        }
        return true
    }
}

// The confirmation sheet's primary button now bakes the scanned count into
// its label ("Import N Photos", per spec §2c's verb+object+count rule), so
// it can't be matched by an exact title.
func button(titlePrefix prefix: String, insideSheet: Bool? = nil) -> AXUIElement? {
    walk(root) { element in
        guard stringAttribute(element, kAXRoleAttribute) == kAXButtonRole,
              let text = accessibleText(element), text.hasPrefix(prefix) else {
            return false
        }
        if let insideSheet {
            return hasAncestor(element, role: kAXSheetRole) == insideSheet
        }
        return true
    }
}

func focusedSheetTextField() -> AXUIElement? {
    guard let focused = elementAttribute(root, kAXFocusedUIElementAttribute),
          stringAttribute(focused, kAXRoleAttribute) == kAXTextFieldRole,
          hasAncestor(focused, role: kAXSheetRole) else {
        return nil
    }
    return focused
}

if focusedSheetTextField() == nil {
    guard waitFor({ button(named: "Import Path", insideSheet: false) != nil }),
          let importPathButton = button(named: "Import Path", insideSheet: false) else {
        fputs("Import Path button not found in \(appName)\n", stderr)
        exit(1)
    }
    let pressResult = AXUIElementPerformAction(importPathButton, kAXPressAction as CFString)
    guard pressResult == .success else {
        fputs("AXPress failed for Import Path: \(pressResult.rawValue)\n", stderr)
        exit(1)
    }
}

guard waitFor({ focusedSheetTextField() != nil }),
      let pathField = focusedSheetTextField() else {
    fputs("Import Path sheet text field did not focus\n", stderr)
    exit(1)
}

let setResult = AXUIElementSetAttributeValue(pathField, kAXValueAttribute as CFString, importPath as CFTypeRef)
guard setResult == .success else {
    fputs("Could not set import path field: \(setResult.rawValue)\n", stderr)
    exit(1)
}

guard let reviewImportButton = button(named: "Review Import", insideSheet: true) else {
    fputs("Review Import button not found in Import Path sheet\n", stderr)
    exit(1)
}

let reviewImportResult = AXUIElementPerformAction(reviewImportButton, kAXPressAction as CFString)
guard reviewImportResult == .success else {
    fputs("AXPress failed for Review Import: \(reviewImportResult.rawValue)\n", stderr)
    exit(1)
}

guard waitFor({ button(titlePrefix: "Import ", insideSheet: true) != nil }),
      let startImportButton = button(titlePrefix: "Import ", insideSheet: true) else {
    fputs("\"Import N Photos\" button not found in confirmation sheet\n", stderr)
    exit(1)
}

let startImportResult = AXUIElementPerformAction(startImportButton, kAXPressAction as CFString)
guard startImportResult == .success else {
    fputs("AXPress failed for \"Import N Photos\": \(startImportResult.rawValue)\n", stderr)
    exit(1)
}

print("submitted_import_path=\(importPath)")
'
