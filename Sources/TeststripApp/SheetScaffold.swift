import SwiftUI

// Shared spacing/width tokens for every sheet, per spec §2c (one template):
// docs/superpowers/specs/2026-07-11-trash-and-ux-coherence-design.md
enum SheetScaffoldMetrics {
    static let defaultWidth: CGFloat = 420
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 18
}

/// Validates the sheet-template conventions from spec §2c: the primary
/// button reads as a verb + object (never a bare "OK"/"Confirm"), and the
/// optional "Options" disclosure starts collapsed.
enum SheetScaffoldPresentation {
    // "Done" isn't in this list: a review-only sheet with no destructive or
    // creating action (e.g. the import issue log) has nothing to name as a
    // verb+object, and the spec's rule text singles out OK/Confirm.
    private static let genericPrimaryLabels: Set<String> = ["OK", "Confirm", "Submit", "Yes"]

    static func isValidPrimaryLabel(_ label: String) -> Bool {
        !genericPrimaryLabels.contains(label)
    }

    static let optionsStartExpanded = false
}

/// One template for every sheet/dialog (spec §2c): title + one-line subtitle
/// + essence content + an optional single "Options" disclosure for rarely
/// changed fields + a Cancel/primary-verb footer, all sharing width/spacing
/// tokens.
struct SheetScaffold<Content: View, Options: View>: View {
    var title: String
    var subtitle: String?
    var width: CGFloat
    var primaryLabel: String
    var isPrimaryEnabled: Bool
    var cancel: () -> Void
    var primary: () -> Void
    var content: Content
    var options: Options?

    @State private var isOptionsExpanded = SheetScaffoldPresentation.optionsStartExpanded

    init(
        title: String,
        subtitle: String? = nil,
        width: CGFloat = SheetScaffoldMetrics.defaultWidth,
        primaryLabel: String,
        isPrimaryEnabled: Bool = true,
        cancel: @escaping () -> Void,
        primary: @escaping () -> Void,
        @ViewBuilder content: () -> Content,
        @ViewBuilder options: () -> Options
    ) {
        self.title = title
        self.subtitle = subtitle
        self.width = width
        self.primaryLabel = primaryLabel
        self.isPrimaryEnabled = isPrimaryEnabled
        self.cancel = cancel
        self.primary = primary
        self.content = content()
        self.options = options()
        assert(
            SheetScaffoldPresentation.isValidPrimaryLabel(primaryLabel),
            "SheetScaffold primary label must be a verb + object, not a generic \"\(primaryLabel)\""
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SheetScaffoldMetrics.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content
            if let options {
                DisclosureGroup("Options", isExpanded: $isOptionsExpanded) {
                    options
                        .padding(.top, 6)
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                Button(primaryLabel, action: primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isPrimaryEnabled)
            }
            // Bare Return is usually consumed by whichever text field has
            // focus (its field editor's insertNewline: swallows it before it
            // can reach the sheet's default-action button), so a keyword/
            // caption field's Return never reaches the primary action —
            // persona-3 saw this dead-end in Batch Metadata. A second,
            // invisible button bound to ⌘Return gives every sheet a commit
            // key that works regardless of which field is focused.
            Button(primaryLabel, action: primary)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!isPrimaryEnabled)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .padding(SheetScaffoldMetrics.padding)
        .frame(width: width)
    }
}

extension SheetScaffold where Options == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        width: CGFloat = SheetScaffoldMetrics.defaultWidth,
        primaryLabel: String,
        isPrimaryEnabled: Bool = true,
        cancel: @escaping () -> Void,
        primary: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            width: width,
            primaryLabel: primaryLabel,
            isPrimaryEnabled: isPrimaryEnabled,
            cancel: cancel,
            primary: primary,
            content: content,
            options: { EmptyView() }
        )
        self.options = nil
    }
}
