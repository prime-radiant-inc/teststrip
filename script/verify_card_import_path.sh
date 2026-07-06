#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Teststrip}"
TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-15}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CARD_SOURCE_DIR="${TESTSTRIP_AX_CARD_SOURCE_DIR:-}"
CARD_DESTINATION_DIR="${TESTSTRIP_AX_CARD_DESTINATION_DIR:-}"
CARD_IMPORT_COUNT="${TESTSTRIP_AX_CARD_IMPORT_COUNT:-1}"

source "$SCRIPT_DIR/import_verifier_metrics.sh"

if [[ -n "$CARD_SOURCE_DIR" ]]; then
  if [[ ! -d "$CARD_SOURCE_DIR" ]]; then
    echo "TESTSTRIP_AX_CARD_SOURCE_DIR must be a directory" >&2
    exit 2
  fi
  SOURCE_DIR="$(cd "$CARD_SOURCE_DIR" && pwd)"
  card_files=()
  while IFS= read -r card_file; do
    card_files+=("$card_file")
  done < <(find "$SOURCE_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.tif' -o -iname '*.tiff' \) | sort)
  if [[ "${#card_files[@]}" -lt 1 ]]; then
    echo "TESTSTRIP_AX_CARD_SOURCE_DIR contains no supported image files" >&2
    exit 2
  fi
  ASSET_NAME="${TESTSTRIP_AX_TARGET_ASSET:-$(basename "${card_files[0]}")}"
else
  if [[ ! "$CARD_IMPORT_COUNT" =~ ^[0-9]+$ ]] || [[ "$CARD_IMPORT_COUNT" -lt 1 ]]; then
    echo "TESTSTRIP_AX_CARD_IMPORT_COUNT must be a positive integer" >&2
    exit 2
  fi
  SOURCE_DIR="$(mktemp -d /tmp/teststrip-card-source.XXXXXX)"
  PNG_BYTES='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII='
  if [[ "$CARD_IMPORT_COUNT" -eq 1 ]]; then
    ASSET_NAME="ax-card-import-$$.png"
    printf '%s' "$PNG_BYTES" | base64 -D > "$SOURCE_DIR/$ASSET_NAME"
  else
    for ((index = 0; index < CARD_IMPORT_COUNT; index++)); do
      asset_name="$(printf 'ax-card-import-%04d.png' "$index")"
      printf '%s' "$PNG_BYTES" | base64 -D > "$SOURCE_DIR/$asset_name"
    done
    ASSET_NAME="ax-card-import-0000.png"
  fi
fi

if [[ -n "$CARD_DESTINATION_DIR" ]]; then
  mkdir -p "$CARD_DESTINATION_DIR"
  DESTINATION_DIR="$(cd "$CARD_DESTINATION_DIR" && pwd)"
else
  DESTINATION_DIR="$(mktemp -d /tmp/teststrip-card-destination.XXXXXX)"
fi

"$SCRIPT_DIR/activate_app.sh" "$APP_NAME"

card_started_ms="$(metric_now_ms)"
card_output="$(
TESTSTRIP_AX_APP_NAME="$APP_NAME" \
TESTSTRIP_AX_CARD_SOURCE_DIR="$SOURCE_DIR" \
TESTSTRIP_AX_CARD_DESTINATION_DIR="$DESTINATION_DIR" \
TESTSTRIP_AX_TARGET_ASSET="$ASSET_NAME" \
TESTSTRIP_AX_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let sourcePath = ProcessInfo.processInfo.environment["TESTSTRIP_AX_CARD_SOURCE_DIR"]!
let destinationPath = ProcessInfo.processInfo.environment["TESTSTRIP_AX_CARD_DESTINATION_DIR"]!
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
    var seen = Set<ObjectIdentifier>()
    var uniqueChildren: [AXUIElement] = []
    for child in directChildren + navigationChildren + visibleChildren + windows {
        let key = ObjectIdentifier(child)
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

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Bool) -> AXUIElement? {
    var visited = Set<ObjectIdentifier>()
    var stack = [element]
    while let current = stack.popLast() {
        let key = ObjectIdentifier(current)
        guard visited.insert(key).inserted else { continue }
        if visit(current) {
            return current
        }
        stack.append(contentsOf: children(of: current).reversed())
    }
    return nil
}

func waitFor(timeout seconds: TimeInterval = timeout, _ predicate: @escaping () -> Bool) -> Bool {
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

func sheetTextFields() -> [AXUIElement] {
    var fields: [AXUIElement] = []
    _ = walk(root) { element in
        if stringAttribute(element, kAXRoleAttribute) == kAXTextFieldRole,
           hasAncestor(element, role: kAXSheetRole) {
            fields.append(element)
        }
        return false
    }
    return fields
}

func importedTargetIsVisible() -> Bool {
    walk(root) { element in
        stringAttribute(element, kAXRoleAttribute) == kAXButtonRole
            && accessibleText(element) == targetAsset
    } != nil
}

if sheetTextFields().count < 2 {
    guard waitFor({ button(named: "Import Card", insideSheet: false) != nil }),
          let importCardButton = button(named: "Import Card", insideSheet: false) else {
        fputs("Import Card button not found in \(appName) within \(timeout)s\n", stderr)
        exit(1)
    }
    let pressResult = AXUIElementPerformAction(importCardButton, kAXPressAction as CFString)
    guard pressResult == .success else {
        fputs("AXPress failed for Import Card: \(pressResult.rawValue)\n", stderr)
        exit(1)
    }
}

guard waitFor({ sheetTextFields().count >= 2 }) else {
    fputs("Import Card Paths sheet text fields did not appear within \(timeout)s\n", stderr)
    exit(1)
}
let fields = sheetTextFields()
let sourceResult = AXUIElementSetAttributeValue(fields[0], kAXValueAttribute as CFString, sourcePath as CFTypeRef)
let destinationResult = AXUIElementSetAttributeValue(fields[1], kAXValueAttribute as CFString, destinationPath as CFTypeRef)
guard sourceResult == .success, destinationResult == .success else {
    fputs("Could not set card import path fields: \(sourceResult.rawValue), \(destinationResult.rawValue)\n", stderr)
    exit(1)
}

guard let reviewButton = button(named: "Review Card Import", insideSheet: true) else {
    fputs("Review Card Import button not found in card path sheet\n", stderr)
    exit(1)
}
let reviewResult = AXUIElementPerformAction(reviewButton, kAXPressAction as CFString)
guard reviewResult == .success else {
    fputs("AXPress failed for Review Card Import: \(reviewResult.rawValue)\n", stderr)
    exit(1)
}

guard waitFor({ button(named: "Start Card Import", insideSheet: true) != nil }),
      let startButton = button(named: "Start Card Import", insideSheet: true) else {
    fputs("Start Card Import button not found in confirmation sheet\n", stderr)
    exit(1)
}
let startResult = AXUIElementPerformAction(startButton, kAXPressAction as CFString)
guard startResult == .success else {
    fputs("AXPress failed for Start Card Import: \(startResult.rawValue)\n", stderr)
    exit(1)
}

guard waitFor({ importedTargetIsVisible() }) else {
    fputs("Imported card image \(targetAsset) did not become visible within \(timeout)s\n", stderr)
    exit(1)
}

print("imported card \(targetAsset) from \(sourcePath) to \(destinationPath)")
'
)"
card_completed_ms="$(metric_now_ms)"
printf '%s\n' "$card_output"
emit_import_metric "card_target_visible_seconds" "$(elapsed_seconds_from_ms "$card_started_ms" "$card_completed_ms")"
emit_import_metric "card_import_count" "$CARD_IMPORT_COUNT"

app_pid="$(pgrep -n -x "$APP_NAME" || true)"
worker_listings="$(pgrep -fl "[T]eststripWorker" || true)"
worker_listing="$(select_latest_helper_worker_listing "$worker_listings")"
catalog_path="$(extract_worker_catalog_path "$worker_listing")"
if [[ -z "$catalog_path" ]]; then
  app_command="$(/bin/ps eww -p "$app_pid" -o command= 2>/dev/null || true)"
  app_support_directory="$(extract_app_support_directory "$app_command")"
  if [[ -n "$app_support_directory" ]]; then
    catalog_path="$(catalog_path_for_app_support_directory "$app_support_directory")"
  fi
fi

if [[ -n "$catalog_path" && -f "$catalog_path" ]]; then
  if ! wait_until_import_finished "$catalog_path" "${TESTSTRIP_CARD_IMPORT_COMPLETION_TIMEOUT_SECONDS:-30}" "0.25"; then
    echo "Card import did not finish within timeout" >&2
    exit 1
  fi
  escaped_asset="${ASSET_NAME//\'/\'\'}"
  cataloged_path="$(/usr/bin/sqlite3 "$catalog_path" "select original_path from assets where original_path like '%/$escaped_asset' order by rowid desc limit 1;" 2>/dev/null || true)"
  if [[ -z "$cataloged_path" ]]; then
    echo "Could not find card-imported asset $ASSET_NAME in catalog" >&2
    exit 1
  fi
  case "$cataloged_path" in
    "$DESTINATION_DIR"/*)
      ;;
    *)
      echo "Card-imported asset was not cataloged under destination: $cataloged_path" >&2
      exit 1
      ;;
  esac
  emit_import_metric "card_catalog_destination_verified" "true"
else
  emit_import_metric "card_catalog_destination_verified" "unknown"
fi
