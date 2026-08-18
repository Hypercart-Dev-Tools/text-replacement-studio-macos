import SwiftUI

/// Bottom feedback capsule that replaces the old status log.
///
/// Success/info auto-dismiss and stay a single line. Errors do not auto-dismiss and carry a
/// second line — what went wrong and what to do — because an error the user cannot act on is
/// just "Apply failed" with extra steps. The action button is chosen by the failure: Retry when
/// retrying could work, Show when a specific row is at fault.
struct ToastView: View {
    let toast: ToastMessage
    let onAction: (ToastMessage.Action) -> Void
    let onDismiss: () -> Void

    @State private var didCopy = false

    private var hasDetail: Bool { !(toast.detail ?? "").isEmpty }

    var body: some View {
        HStack(alignment: hasDetail ? .top : .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, hasDetail ? 1 : 0)

            VStack(alignment: .leading, spacing: 4) {
                Text(toast.text)
                    .font(Theme.bodyMed)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = toast.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if hasDetail {
                    HStack(spacing: 14) {
                        if let action = toast.action {
                            Button(action.title) { onAction(action) }
                                .buttonStyle(.borderless)
                                .font(Theme.bodyMed)
                                .foregroundStyle(Theme.accent)
                        }
                        if let copyable = toast.copyableDetail, !copyable.isEmpty {
                            Button(didCopy ? "Copied" : "Copy Details") { copy(copyable) }
                                .buttonStyle(.borderless)
                                .font(Theme.bodyMed)
                                .foregroundStyle(Theme.text3)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            // Bounded so a long explanation wraps into a readable column instead of one
            // window-wide line; multi-line detail is the norm for errors now.
            .frame(maxWidth: hasDetail ? 420 : .infinity, alignment: .leading)

            // Single-line toasts keep the original inline-action layout.
            if !hasDetail, let action = toast.action {
                Button(action.title) { onAction(action) }
                    .buttonStyle(.borderless)
                    .font(Theme.bodyMed)
                    .foregroundStyle(Theme.accent)
            }

            Button { onDismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text3)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 11)
        .background(background)
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .padding(.bottom, Theme.Space.xl)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hasDetail ? "\(toast.text). \(toast.detail ?? "")" : toast.text)
    }

    /// A capsule reads as a pill only while the content is one line; a multi-line explanation
    /// needs corners that match its height. Written out per shape rather than through a type-erased
    /// one so `strokeBorder` (which needs `InsettableShape`) stays available on both.
    @ViewBuilder private var background: some View {
        if hasDetail {
            let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
            shape.fill(.regularMaterial)
                .overlay(shape.strokeBorder(Theme.separator, lineWidth: 1))
        } else {
            Capsule().fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 1))
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        didCopy = true
    }

    private var icon: String {
        switch toast.style {
        case .success: return "checkmark.circle.fill"
        case .error:   return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }
    private var tint: Color {
        switch toast.style {
        case .success: return Theme.diffAdd
        case .error:   return Theme.diffRemove
        case .info:    return Theme.accent
        }
    }
}

extension ToastMessage.Action {
    var title: String {
        switch self {
        case .retryApply:  return "Retry"
        case .retryImport: return "Import"
        case .reveal:      return "Show Me"
        }
    }
}
