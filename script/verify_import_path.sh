#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Teststrip}"
TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-15}"
IMPORT_COUNT="${TESTSTRIP_AX_IMPORT_COUNT:-1}"
IMPORT_DIR="$(mktemp -d /tmp/teststrip-import-path-smoke.XXXXXX)"
ASSET_NAME="ax-import-$$.png"

if [[ ! "$IMPORT_COUNT" =~ ^[0-9]+$ ]] || [[ "$IMPORT_COUNT" -lt 1 ]]; then
  echo "TESTSTRIP_AX_IMPORT_COUNT must be a positive integer" >&2
  exit 2
fi

PNG_BYTES='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII='
if [[ "$IMPORT_COUNT" -eq 1 ]]; then
  printf '%s' "$PNG_BYTES" | base64 -D > "$IMPORT_DIR/$ASSET_NAME"
else
  for ((index = 0; index < IMPORT_COUNT; index++)); do
    asset_name="$(printf 'ax-import-%04d.png' "$index")"
    printf '%s' "$PNG_BYTES" | base64 -D > "$IMPORT_DIR/$asset_name"
  done
  ASSET_NAME="ax-import-0000.png"
fi

TESTSTRIP_AX_APP_NAME="$APP_NAME" \
TESTSTRIP_AX_IMPORT_DIR="$IMPORT_DIR" \
TESTSTRIP_AX_TARGET_ASSET="$ASSET_NAME" \
TESTSTRIP_AX_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let importPath = ProcessInfo.processInfo.environment["TESTSTRIP_AX_IMPORT_DIR"]!
let targetAsset = ProcessInfo.processInfo.environment["TESTSTRIP_AX_TARGET_ASSET"]!
let timeout = TimeInterval(ProcessInfo.processInfo.environment["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "15") ?? 15

guard AXIsProcessTrusted() else {
    fputs("Accessibility is not trusted for this process\n", stderr)
    exit(2)
}

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == appName }) else {
    fputs("No running app named \(appName)\n", stderr)
    exit(1)
}

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
    attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

func accessibleText(_ element: AXUIElement) -> String? {
    stringAttribute(element, kAXTitleAttribute)
        ?? stringAttribute(element, kAXDescriptionAttribute)
        ?? stringAttribute(element, kAXValueAttribute)
}

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Bool) -> AXUIElement? {
    if visit(element) {
        return element
    }
    for child in children(of: element) {
        if let found = walk(child, visit: visit) {
            return found
        }
    }
    return nil
}

func waitFor(_ predicate: @escaping () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
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

func focusedSheetTextField() -> AXUIElement? {
    guard let focused = elementAttribute(root, kAXFocusedUIElementAttribute),
          stringAttribute(focused, kAXRoleAttribute) == kAXTextFieldRole,
          hasAncestor(focused, role: kAXSheetRole) else {
        return nil
    }
    return focused
}

if focusedSheetTextField() == nil {
    guard let importPathButton = button(named: "Import Path", insideSheet: false) else {
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
    fputs("Import Path sheet text field did not focus within \(timeout)s\n", stderr)
    exit(1)
}

let setResult = AXUIElementSetAttributeValue(pathField, kAXValueAttribute as CFString, importPath as CFTypeRef)
guard setResult == .success else {
    fputs("Could not set import path field: \(setResult.rawValue)\n", stderr)
    exit(1)
}

guard let importButton = button(named: "Import", insideSheet: true) else {
    fputs("Import button not found in Import Path sheet\n", stderr)
    exit(1)
}

let importResult = AXUIElementPerformAction(importButton, kAXPressAction as CFString)
guard importResult == .success else {
    fputs("AXPress failed for Import: \(importResult.rawValue)\n", stderr)
    exit(1)
}

guard waitFor({
    walk(root) { element in
        stringAttribute(element, kAXRoleAttribute) == kAXButtonRole
            && accessibleText(element) == targetAsset
    } != nil
}) else {
    fputs("Imported image \(targetAsset) did not become visible within \(timeout)s\n", stderr)
    exit(1)
}

print("imported \(targetAsset) from \(importPath)")
'
