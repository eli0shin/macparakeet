import SwiftUI

enum LibraryActionTone {
    case secondary
    case destructive
    case subtle

    func foreground(isHovered: Bool, isDisabled: Bool) -> Color {
        if isDisabled { return DesignSystem.Colors.textTertiary }
        switch self {
        case .secondary, .subtle:
            return isHovered ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary
        case .destructive:
            return DesignSystem.Colors.errorRed
        }
    }

    func fill(isHovered: Bool) -> Color {
        switch self {
        case .secondary:
            return isHovered
                ? DesignSystem.Colors.textPrimary.opacity(0.08)
                : DesignSystem.Colors.surface.opacity(0.72)
        case .destructive:
            return DesignSystem.Colors.errorRed.opacity(isHovered ? 0.16 : 0.09)
        case .subtle:
            return isHovered ? DesignSystem.Colors.textPrimary.opacity(0.06) : .clear
        }
    }

    var stroke: Color {
        switch self {
        case .secondary:
            return DesignSystem.Colors.border.opacity(0.8)
        case .destructive:
            return DesignSystem.Colors.errorRed.opacity(0.24)
        case .subtle:
            return .clear
        }
    }
}

/// A secondary Library control that matches the accepted primary CTA's type,
/// padding, capsule geometry, and hover lift without taking its visual priority.
struct LibraryActionButton: View {
    let title: String
    let systemImage: String
    var tone: LibraryActionTone = .secondary
    var isDisabled = false
    var role: ButtonRole?
    var accessibilityHint: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(DesignSystem.Typography.bodySmall.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(tone.foreground(isHovered: isHovered, isDisabled: isDisabled))
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 9)
            .background(Capsule().fill(tone.fill(isHovered: isHovered)))
            .overlay {
                Capsule()
                    .strokeBorder(tone.stroke, lineWidth: tone == .subtle ? 0 : 0.8)
            }
            .shadow(
                color: Color.black.opacity(tone == .subtle ? 0 : (isHovered ? 0.10 : 0.05)),
                radius: isHovered ? 5 : 3,
                y: tone == .subtle ? 0 : 2
            )
            .contentShape(Capsule())
            .scaleEffect(isHovered ? 1.035 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.48 : 1)
        .onHover { hovering in
            isHovered = hovering && !isDisabled
        }
        .onChange(of: isDisabled) { _, disabled in
            if disabled {
                isHovered = false
            }
        }
        .pointingHandCursor(isActive: isHovered && !isDisabled)
        .animation(DesignSystem.Animation.hoverTransition, value: isHovered)
        .animation(DesignSystem.Animation.hoverTransition, value: isDisabled)
        .accessibilityLabel(title)
        .accessibilityHint(accessibilityHint ?? "")
    }
}
