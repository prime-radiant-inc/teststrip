#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Teststrip}"
TARGET_ASSET="${2:-}"
TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-5}"

TESTSTRIP_AX_APP_NAME="$APP_NAME" \
TESTSTRIP_AX_TARGET_ASSET="$TARGET_ASSET" \
TESTSTRIP_AX_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let requestedTarget = ProcessInfo.processInfo.environment["TESTSTRIP_AX_TARGET_ASSET"] ?? ""
let timeout = TimeInterval(ProcessInfo.processInfo.environment["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "5") ?? 5

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
let imageExtensions: Set<String> = [
    "arw", "cr2", "cr3", "crw", "dng", "heic", "jpeg", "jpg",
    "nef", "orf", "png", "raf", "rwl", "rw2", "srw", "tif", "tiff", "x3f"
]

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    return result == .success ? value : nil
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    attribute(element, name) as? String
}

func children(of element: AXUIElement) -> [AXUIElement] {
    let directChildren = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    let navigationChildren = attribute(element, "AXChildrenInNavigationOrder") as? [AXUIElement] ?? []
    let visibleChildren = attribute(element, kAXVisibleChildrenAttribute) as? [AXUIElement] ?? []
    let windows = attribute(element, kAXWindowsAttribute) as? [AXUIElement] ?? []
    return directChildren + navigationChildren + visibleChildren + windows
}

func accessibleText(_ element: AXUIElement) -> String? {
    stringAttribute(element, kAXTitleAttribute)
        ?? stringAttribute(element, kAXDescriptionAttribute)
        ?? stringAttribute(element, kAXValueAttribute)
}

func isImageFilename(_ text: String) -> Bool {
    guard let fileExtension = text.split(separator: ".").last else { return false }
    return imageExtensions.contains(fileExtension.lowercased())
}

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Bool) -> AXUIElement? {
    var visited = Set<CFHashCode>()
    var stack = [element]
    while let current = stack.popLast() {
        let key = CFHash(current)
        guard visited.insert(key).inserted else { continue }
        if visit(current) {
            return current
        }
        stack.append(contentsOf: children(of: current).reversed())
    }
    return nil
}

let button = walk(root) { element in
    guard stringAttribute(element, kAXRoleAttribute) == kAXButtonRole,
          let text = accessibleText(element) else {
        return false
    }
    if requestedTarget.isEmpty {
        return isImageFilename(text)
    }
    return text == requestedTarget
}

guard let button, let selectedName = accessibleText(button) else {
    if requestedTarget.isEmpty {
        fputs("Could not find a visible image button in \(appName)\n", stderr)
    } else {
        fputs("Could not find a visible image button named \(requestedTarget) in \(appName)\n", stderr)
    }
    exit(1)
}

let pressResult = AXUIElementPerformAction(button, kAXPressAction as CFString)
guard pressResult == .success else {
    fputs("AXPress failed for \(selectedName): \(pressResult.rawValue)\n", stderr)
    exit(1)
}

let deadline = Date().addingTimeInterval(timeout)
while Date() < deadline {
    if walk(root, visit: { element in
        guard stringAttribute(element, kAXRoleAttribute) == kAXStaticTextRole,
              let text = accessibleText(element) else {
            return false
        }
        return text == selectedName
    }) != nil {
        print("selected \(selectedName)")
        exit(0)
    }
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

fputs("Pressed \(selectedName), but the inspector did not expose that selection within \(timeout)s\n", stderr)
exit(1)
'
