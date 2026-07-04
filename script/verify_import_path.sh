#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${1:-Teststrip}"
TIMEOUT_SECONDS="${TESTSTRIP_AX_TIMEOUT_SECONDS:-15}"
FEEDBACK_TIMEOUT_SECONDS="${TESTSTRIP_AX_FEEDBACK_TIMEOUT_SECONDS:-1.5}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRIC_PREVIEW_SAMPLE_SECONDS="${TESTSTRIP_IMPORT_METRIC_PREVIEW_SAMPLE_SECONDS:-2}"
METRIC_PREVIEW_DRAIN_TIMEOUT_SECONDS="${TESTSTRIP_IMPORT_METRIC_PREVIEW_DRAIN_TIMEOUT_SECONDS:-30}"
METRIC_PREVIEW_DRAIN_POLL_SECONDS="${TESTSTRIP_IMPORT_METRIC_PREVIEW_DRAIN_POLL_SECONDS:-0.25}"
IMPORT_SOURCE_DIR="${TESTSTRIP_AX_IMPORT_SOURCE_DIR:-}"

source "$SCRIPT_DIR/import_verifier_metrics.sh"

if [[ -n "$IMPORT_SOURCE_DIR" ]]; then
  if [[ ! -d "$IMPORT_SOURCE_DIR" ]]; then
    echo "TESTSTRIP_AX_IMPORT_SOURCE_DIR must be a directory" >&2
    exit 2
  fi

  IMPORT_DIR="$(cd "$IMPORT_SOURCE_DIR" && pwd)"
  import_files=()
  while IFS= read -r import_file; do
    import_files+=("$import_file")
  done < <(find "$IMPORT_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.tif' -o -iname '*.tiff' \) | sort)

  if [[ "${#import_files[@]}" -lt 1 ]]; then
    echo "TESTSTRIP_AX_IMPORT_SOURCE_DIR contains no supported image files" >&2
    exit 2
  fi

  IMPORT_COUNT="${#import_files[@]}"
  ASSET_NAME="${TESTSTRIP_AX_TARGET_ASSET:-$(basename "${import_files[0]}")}"
else
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
fi

import_started_ms="$(metric_now_ms)"
import_output="$(
TESTSTRIP_AX_APP_NAME="$APP_NAME" \
TESTSTRIP_AX_IMPORT_DIR="$IMPORT_DIR" \
TESTSTRIP_AX_TARGET_ASSET="$ASSET_NAME" \
TESTSTRIP_AX_TIMEOUT_SECONDS="$TIMEOUT_SECONDS" \
TESTSTRIP_AX_FEEDBACK_TIMEOUT_SECONDS="$FEEDBACK_TIMEOUT_SECONDS" \
/usr/bin/swift -e '
import AppKit
import ApplicationServices
import Foundation

let appName = ProcessInfo.processInfo.environment["TESTSTRIP_AX_APP_NAME"] ?? "Teststrip"
let importPath = ProcessInfo.processInfo.environment["TESTSTRIP_AX_IMPORT_DIR"]!
let targetAsset = ProcessInfo.processInfo.environment["TESTSTRIP_AX_TARGET_ASSET"]!
let timeout = TimeInterval(ProcessInfo.processInfo.environment["TESTSTRIP_AX_TIMEOUT_SECONDS"] ?? "15") ?? 15
let feedbackTimeout = TimeInterval(ProcessInfo.processInfo.environment["TESTSTRIP_AX_FEEDBACK_TIMEOUT_SECONDS"] ?? "1.5") ?? 1.5
let importSourceName = URL(fileURLWithPath: importPath).lastPathComponent

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
    return directChildren + navigationChildren + visibleChildren + windows
}

func accessibleText(_ element: AXUIElement) -> String? {
    stringAttribute(element, kAXTitleAttribute)
        ?? stringAttribute(element, kAXDescriptionAttribute)
        ?? stringAttribute(element, kAXValueAttribute)
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

func focusedSheetTextField() -> AXUIElement? {
    guard let focused = elementAttribute(root, kAXFocusedUIElementAttribute),
          stringAttribute(focused, kAXRoleAttribute) == kAXTextFieldRole,
          hasAncestor(focused, role: kAXSheetRole) else {
        return nil
    }
    return focused
}

func importedTargetIsVisible() -> Bool {
    walk(root) { element in
        stringAttribute(element, kAXRoleAttribute) == kAXButtonRole
            && accessibleText(element) == targetAsset
    } != nil
}

func visibleImportFeedback() -> Bool {
    if importedTargetIsVisible() {
        return true
    }
    return walk(root) { element in
        guard let text = accessibleText(element) else { return false }
        if text.contains("Importing from \(importSourceName)") {
            return true
        }
        if text.contains("Imported") && text.contains(importSourceName) {
            return true
        }
        if text.contains("Cataloging") {
            return true
        }
        if text == "Cancel Import" {
            return true
        }
        return false
    } != nil
}

if focusedSheetTextField() == nil {
    guard waitFor({ button(named: "Import Path", insideSheet: false) != nil }),
          let importPathButton = button(named: "Import Path", insideSheet: false) else {
        fputs("Import Path button not found in \(appName) within \(timeout)s\n", stderr)
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

let feedbackStartedAt = Date()
guard waitFor(timeout: feedbackTimeout, {
    visibleImportFeedback()
}) else {
    fputs("Import did not show visible progress or \(targetAsset) within \(feedbackTimeout)s\n", stderr)
    exit(1)
}
let feedbackVisibleMilliseconds = Int(Date().timeIntervalSince(feedbackStartedAt) * 1000)
print("import_feedback_visible_ms=\(feedbackVisibleMilliseconds)")

guard waitFor({
    importedTargetIsVisible()
}) else {
    fputs("Imported image \(targetAsset) did not become visible within \(timeout)s\n", stderr)
    exit(1)
}

print("imported \(targetAsset) from \(importPath)")
'
)"
import_completed_ms="$(metric_now_ms)"
printf '%s\n' "$import_output"
feedback_visible_ms="$(/usr/bin/awk -F= '/^import_feedback_visible_ms=/ { print $2; exit }' <<< "$import_output")"
if [[ -n "$feedback_visible_ms" ]]; then
  emit_import_metric "feedback_visible_seconds" "$(elapsed_seconds_from_ms 0 "$feedback_visible_ms")"
fi
emit_import_metric "import_duration_seconds" "$(elapsed_seconds_from_ms "$import_started_ms" "$import_completed_ms")"
emit_import_metric "import_count" "$IMPORT_COUNT"

app_pid="$(pgrep -n -x "$APP_NAME" || true)"
worker_listing="$(pgrep -fl "[T]eststripWorker" | /usr/bin/grep "Contents/Helpers/TeststripWorker" | /usr/bin/tail -n 1 || true)"
worker_pid="$(/usr/bin/awk 'NF { print $1 }' <<< "$worker_listing")"
catalog_path="$(extract_worker_catalog_path "$worker_listing")"
if [[ -z "$catalog_path" ]]; then
  app_command="$(/bin/ps eww -p "$app_pid" -o command= 2>/dev/null || true)"
  app_support_directory="$(extract_app_support_directory "$app_command")"
  if [[ -n "$app_support_directory" ]]; then
    catalog_path="$(catalog_path_for_app_support_directory "$app_support_directory")"
  fi
fi

emit_import_metric "app_cpu_percent" "$(process_cpu_percent "$app_pid")"
emit_import_metric "worker_cpu_percent" "$(process_cpu_percent "$worker_pid")"

if [[ -n "$catalog_path" && -f "$catalog_path" ]]; then
  sleep "$METRIC_PREVIEW_SAMPLE_SECONDS"
  emit_import_metric "pending_previews_after_sample" "$(preview_pending_count "$catalog_path")"
  preview_drain_started_ms="$(metric_now_ms)"
  if wait_until_preview_drained "$catalog_path" "$METRIC_PREVIEW_DRAIN_TIMEOUT_SECONDS" "$METRIC_PREVIEW_DRAIN_POLL_SECONDS"; then
    preview_drain_completed_ms="$(metric_now_ms)"
    emit_import_metric "preview_drain_completed" "true"
    emit_import_metric "preview_drain_seconds" "$(elapsed_seconds_from_ms "$preview_drain_started_ms" "$preview_drain_completed_ms")"
  else
    preview_drain_completed_ms="$(metric_now_ms)"
    emit_import_metric "preview_drain_completed" "false"
    emit_import_metric "preview_drain_seconds" "$(elapsed_seconds_from_ms "$preview_drain_started_ms" "$preview_drain_completed_ms")"
  fi
  emit_import_metric "pending_previews_final" "$(preview_pending_count "$catalog_path")"
else
  emit_import_metric "pending_previews_after_sample" "unknown"
  emit_import_metric "preview_drain_completed" "unknown"
  emit_import_metric "preview_drain_seconds" "unknown"
  emit_import_metric "pending_previews_final" "unknown"
fi
