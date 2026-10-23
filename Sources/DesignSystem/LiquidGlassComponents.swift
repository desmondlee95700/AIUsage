//
//  LiquidGlassComponents.swift
//  AIUsage
//  Shared Liquid Glass building blocks: gauges, meters, tiles, chips, buttons and empty states.
//

import SwiftUI
import AppKit

// MARK: - Section Header

/// Small label row that sits above a card: provider icon or symbol, title, optional trailing accessory.
public struct GlassSectionHeader<Trailing: View>: View {
    public let title: String
    public let systemImage: String
    public let tint: Color
    public let trailing: Trailing

    public init(
        _ title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tint)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.16))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 0.7), lineWidth: 0.8)
                )

            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(LiquidGlassText.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            trailing
        }
    }
}

public extension GlassSectionHeader where Trailing == EmptyView {
    init(_ title: String, systemImage: String, tint: Color) {
        self.init(title, systemImage: systemImage, tint: tint) { EmptyView() }
    }
}

// MARK: - Chip

/// L2 capsule badge for plan tiers, counts and health labels.
public struct GlassChip: View {
    public let text: String
    public let tint: Color
    public let systemImage: String?

    public init(_ text: String, tint: Color, systemImage: String? = nil) {
        self.text = text
        self.tint = tint
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
            }
            Text(text)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundColor(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(0.16))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.38), lineWidth: 0.8)
        )
        .fixedSize()
    }
}

// MARK: - Capsule Button

/// Capsule action button. `.standard` is frosted glass; `.prominent` is accent-filled glass.
public struct GlassCapsuleButton: View {
    public enum Style {
        case standard
        case prominent(Color)
    }

    public enum Size {
        case small, regular
    }

    public let title: String
    public let systemImage: String?
    public let trailingSystemImage: String?
    public let style: Style
    public let size: Size
    public let help: String?
    public let action: () -> Void

    public init(
        _ title: String,
        systemImage: String? = nil,
        trailingSystemImage: String? = nil,
        style: Style = .standard,
        size: Size = .regular,
        help: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.trailingSystemImage = trailingSystemImage
        self.style = style
        self.size = size
        self.help = help
        self.action = action
    }

    private var tint: Color? {
        if case .prominent(let color) = style { return color }
        return nil
    }

    public var body: some View {
        let isSmall = size == .small

        Button(action: action) {
            HStack(spacing: isSmall ? 4 : 5) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: isSmall ? 9.5 : 10.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: isSmall ? 11 : 12, weight: tint == nil ? .medium : .semibold))
                    .lineLimit(1)
                if let trailingSystemImage = trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: isSmall ? 8.5 : 9.5, weight: .bold))
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, isSmall ? 10 : 14)
            .padding(.vertical, isSmall ? 4 : 7)
            .liquidGlassButton(cornerRadius: 100, isProminent: tint != nil, tint: tint)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help(help ?? title)
    }
}

// MARK: - Icon Button

/// Square icon button used inside the header control cluster.
public struct GlassIconButton: View {
    public let systemImage: String
    public let isActive: Bool
    public let activeTint: Color
    public let help: String
    public let rotation: Double
    public let action: () -> Void

    @State private var isHovered = false

    public init(
        systemImage: String,
        isActive: Bool = false,
        activeTint: Color = LiquidGlassPalette.aiBlue,
        rotation: Double = 0,
        help: String,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.activeTint = activeTint
        self.rotation = rotation
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(isActive ? activeTint : .white.opacity(isHovered ? 1.0 : 0.82))
                .rotationEffect(.degrees(rotation))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovered ? 0.14 : 0.0))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Alerts Onboarding Card

/// One-time invitation to turn on low-quota alerts. Tapping "Turn On Alerts" brings up the macOS
/// permission prompt right after the user asked for it, instead of unannounced at launch.
public struct AlertsOnboardingCard: View {
    public let onTurnOn: () -> Void
    public let onDismiss: () -> Void

    public init(onTurnOn: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onTurnOn = onTurnOn
        self.onDismiss = onDismiss
    }

    private let tint = LiquidGlassPalette.aiBlue

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(tint.opacity(0.16)))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Get notified before you run out")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(LiquidGlassText.primary)
                    Text("AIUsage can alert you when a 5-hour or weekly limit is running low, and tell you when it resets.")
                        .font(.system(size: 11.5))
                        .foregroundColor(LiquidGlassText.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                GlassCapsuleButton("Not Now", size: .small, action: onDismiss)
                GlassCapsuleButton("Turn On Alerts", systemImage: "bell", style: .prominent(tint), size: .small, action: onTurnOn)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 16, tint: tint, material: .thinMaterial)
    }
}

// MARK: - Notifications Blocked Strip

/// Slim notice for when low-quota alerts are on but macOS is blocking AIUsage's notifications,
/// so the user knows alerts can't arrive and has a one-click way to fix it or turn them off.
public struct NotificationsBlockedStrip: View {
    public let onOpenSettings: () -> Void
    public let onTurnOffAlerts: () -> Void

    @State private var isHoveringClose = false

    public init(onOpenSettings: @escaping () -> Void, onTurnOffAlerts: @escaping () -> Void) {
        self.onOpenSettings = onOpenSettings
        self.onTurnOffAlerts = onTurnOffAlerts
    }

    private let tint = LiquidGlassPalette.moderate

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tint)

            Text("Notifications are blocked, so low-quota alerts can't appear.")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(LiquidGlassText.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            GlassCapsuleButton("Open Settings", style: .prominent(tint), size: .small, action: onOpenSettings)

            Button(action: onTurnOffAlerts) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isHoveringClose ? LiquidGlassText.primary : LiquidGlassText.tertiary)
                    .frame(width: 18, height: 18)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .help("Turn off low-quota alerts")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .liquidGlassCard(cornerRadius: 14, tint: tint, material: .thinMaterial)
    }
}

// MARK: - Menu Bar Marker

/// Small glyph beside the limit the menu bar is showing, so a figure like "87%" up there can be
/// matched to its window without comparing numbers.
/// Hidden in icon-only mode, where the menu bar shows no figures.
public struct MenuBarMarker: View {
    @AppStorage(MenuBarDisplayMode.storageKey) private var displayMode = MenuBarDisplayMode.percentages.rawValue

    public init() {}

    public var body: some View {
        if MenuBarDisplayMode(savedValue: displayMode) == .percentages {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(LiquidGlassText.tertiary)
                .help("This is the figure shown in your menu bar")
        }
    }
}

// MARK: - Overflow Scroll View

/// Vertical scroll view for the fixed-height popover. Scroll indicators stay hidden for the glass
/// look, so while content continues below the fold the bottom edge fades out and a chevron
/// appears; clicking it scrolls to the end.
public struct OverflowScrollView<Content: View>: View {
    public let content: Content

    /// Only whether content continues below matters, so that's all that's stored: tracking the
    /// exact distance would write state on every scroll frame
    @State private var hasMoreBelow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static var spaceName: String { "OverflowScrollView" }
    private static var bottomID: String { "OverflowScrollView.bottom" }
    private static var fadeHeight: CGFloat { 36 }

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        content
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .background(
                        // Tracks where the content ends relative to the viewport. Read directly rather
                        // than through a preference: on macOS, preferences set inside a ScrollView's
                        // content don't propagate out of it.
                        GeometryReader { geo in
                            let contentMaxY = geo.frame(in: .named(Self.spaceName)).maxY
                            Color.clear
                                .onAppear { updateHiddenBelow(contentMaxY: contentMaxY, viewportHeight: viewport.size.height) }
                                .onChange(of: contentMaxY) { updateHiddenBelow(contentMaxY: $0, viewportHeight: viewport.size.height) }
                                .onChange(of: viewport.size.height) { updateHiddenBelow(contentMaxY: contentMaxY, viewportHeight: $0) }
                        }
                    )
                }
                .coordinateSpace(name: Self.spaceName)
                .mask(fadeMask(height: viewport.size.height))
                .overlay(alignment: .bottom) {
                    if hasMoreBelow {
                        moreBelowButton {
                            withAnimation(LiquidGlassTokens.motion(LiquidGlassTokens.stateSpring, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(Self.bottomID, anchor: .bottom)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .animation(LiquidGlassTokens.motion(LiquidGlassTokens.hoverSpring, reduceMotion: reduceMotion), value: hasMoreBelow)
            }
        }
    }

    private func updateHiddenBelow(contentMaxY: CGFloat, viewportHeight: CGFloat) {
        let moreBelow = contentMaxY - viewportHeight > 8
        if moreBelow != hasMoreBelow {
            hasMoreBelow = moreBelow
        }
    }

    /// Opaque everywhere except a fade along the bottom while there's more content below
    private func fadeMask(height: CGFloat) -> some View {
        let fadeStart = height > 0 ? max(0, 1 - Self.fadeHeight / height) : 1
        return LinearGradient(
            stops: [
                .init(color: .black, location: 0),
                .init(color: .black, location: hasMoreBelow ? fadeStart : 1),
                .init(color: .black.opacity(hasMoreBelow ? 0.05 : 1), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func moreBelowButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(LiquidGlassText.secondary)
                .frame(width: 30, height: 16)
                .liquidGlassPill()
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
        .help("More below")
    }
}

// MARK: - Ring Gauge

/// Circular remaining-quota gauge with a glowing arc coloured by `QuotaLevel`, optionally labelled in the centre.
public struct LiquidRingGauge: View {
    public let fraction: Double
    public let size: CGFloat
    public let lineWidth: CGFloat
    public let showsLabel: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, size: CGFloat = 56, lineWidth: CGFloat = 6, showsLabel: Bool = true) {
        self.fraction = max(0.0, min(1.0, fraction))
        self.size = size
        self.lineWidth = lineWidth
        self.showsLabel = showsLabel
    }

    public var body: some View {
        let level = QuotaLevel(fraction: fraction)

        ZStack {
            // Recessed track
            Circle()
                .stroke(Color.white.opacity(0.09), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            // Soft tinted well behind the label
            if showsLabel {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [level.color.opacity(0.16), level.color.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: size / 2
                        )
                    )
                    .padding(lineWidth)
            }

            // Progress arc
            Circle()
                .trim(from: 0.0, to: CGFloat(fraction))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: level.gradientColors),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360 * max(fraction, 0.01))
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: level.color.opacity(0.55), radius: lineWidth * 0.8, x: 0, y: 0)

            if showsLabel {
                VStack(spacing: -1) {
                    HStack(alignment: .firstTextBaseline, spacing: 0.5) {
                        Text("\(Int((fraction * 100).rounded()))")
                            .font(.system(size: size * 0.27, weight: .bold, design: .rounded))
                            .foregroundColor(LiquidGlassText.primary)
                        Text("%")
                            .font(.system(size: size * 0.15, weight: .semibold, design: .rounded))
                            .foregroundColor(LiquidGlassText.tertiary)
                    }
                    .monospacedDigit()
                    
                    // Says which way the number runs, so tiles don't need a separate "% used" line
                    Text("left")
                        .font(.system(size: size * 0.13, weight: .medium, design: .rounded))
                        .foregroundColor(LiquidGlassText.tertiary)
                }
            }
        }
        .frame(width: size, height: size)
        .animation(LiquidGlassTokens.motion(LiquidGlassTokens.metricSpring, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent remaining")
    }
}

// MARK: - Meter Bar

/// Horizontal glass capsule meter. Fill colour follows `QuotaLevel` unless a tint is given.
public struct LiquidMeterBar: View {
    public let fraction: Double
    public let tint: Color?
    public let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(fraction: Double, tint: Color? = nil, height: CGFloat = 6) {
        self.fraction = max(0.0, min(1.0, fraction))
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        let level = QuotaLevel(fraction: fraction)
        let colors = tint.map { [$0.opacity(0.70), $0] } ?? level.gradientColors
        let glow = tint ?? level.color

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )

                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .overlay(
                        // Specular sheen along the top edge of the fill
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.35), Color.white.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                    )
                    .frame(width: fraction > 0 ? max(height, proxy.size.width * CGFloat(fraction)) : 0)
                    .shadow(color: glow.opacity(0.50), radius: height * 0.7, x: 0, y: 0)
            }
        }
        .frame(height: height)
        .animation(LiquidGlassTokens.motion(LiquidGlassTokens.metricSpring, reduceMotion: reduceMotion), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent remaining")
    }
}

// MARK: - Quota Tile

/// Control Center–style tile: ring gauge, window name, caption and reset countdown.
/// Drawn as an L2 inner surface (translucent fill, no extra material) for use inside an L1 card.
public struct QuotaTile: View {
    public let title: String
    public let caption: String?
    public let fraction: Double
    public let resetText: String?
    /// Exact reset time, shown on hover behind the relative countdown
    public let resetDate: Date?
    /// Whether this is the limit the menu bar shows for the provider
    public let isInMenuBar: Bool

    @State private var isHovered = false

    public init(title: String, caption: String?, fraction: Double, resetText: String?, resetDate: Date? = nil, isInMenuBar: Bool = false) {
        self.title = title
        self.caption = caption
        self.fraction = fraction
        self.resetText = resetText
        self.resetDate = resetDate
        self.isInMenuBar = isInMenuBar
    }

    public var body: some View {
        let level = QuotaLevel(fraction: fraction)

        VStack(spacing: 8) {
            LiquidRingGauge(fraction: fraction, size: 62, lineWidth: 6.5)
                .padding(.top, 2)

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(LiquidGlassText.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if isInMenuBar {
                        MenuBarMarker()
                    }
                }

                if let caption = caption {
                    Text(caption)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(LiquidGlassText.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }

            if level.needsAttention {
                GlassChip(level.label, tint: level.color)
            }

            if let resetText = resetText {
                // One line in every layout: in a three-up row "Resets in 1d 18h" doesn't fit, so drop
                // the prefix (the clock already says it) and only wrap if even that is too wide
                ViewThatFits(in: .horizontal) {
                    resetLabel(resetText).fixedSize()
                    resetLabel(Self.compactResetText(resetText)).fixedSize()
                    resetLabel(resetText)
                }
                .foregroundColor(LiquidGlassText.tertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(resetText)
                .help(resetDate.map { "Resets \(DateParsing.exact($0))" } ?? "")
            }
        }
        // Fill the row's height so a tile without a status chip matches its neighbour
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: isHovered ? 0.9 : 0.6), lineWidth: 0.8)
        )
        .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
        .onHover { isHovered = $0 }
    }

    private func resetLabel(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 3) {
            Image(systemName: "clock")
                .font(.system(size: 8.5, weight: .semibold))
                .padding(.top, 1.5)
            Text(text)
                .font(.system(size: 10))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Resets in 1d 18h" → "1d 18h"; other wording ("Resets soon", "Refreshed") is kept as is.
    static func compactResetText(_ text: String) -> String {
        let prefix = "Resets in "
        return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
    }
}

/// Lays out quota tiles two or three to a row.
public struct QuotaTileGrid<Tile: View>: View {
    public let count: Int
    public let tile: (Int) -> Tile

    public init(count: Int, @ViewBuilder tile: @escaping (Int) -> Tile) {
        self.count = count
        self.tile = tile
    }

    private var rows: [[Int]] {
        let perRow = count == 3 ? 3 : 2
        return stride(from: 0, to: count, by: perRow).map { start in
            Array(start..<min(start + perRow, count))
        }
    }

    public var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row, id: \.self) { index in
                        tile(index)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Provider Plan Card

/// Compact account strip shared by all providers: which plan and account the limits below belong to.
/// Kept to one row so the limits, not the account, lead the popover; app and plan actions sit in a
/// small glass cluster on the trailing edge.
public struct ProviderPlanCard: View {
    /// A browser link for the plan, e.g. "Manage plan" for paid tiers or "Upgrade plan" for free ones.
    public struct PlanLink {
        public let title: String
        public let url: URL

        public init(title: String, url: URL) {
            self.title = title
            self.url = url
        }
    }

    public let provider: AIProvider
    public let icon: NSImage?
    public let systemFallback: String
    public let planName: String
    public let email: String?
    public let appName: String
    public let onLaunch: () -> Void
    public let planLink: PlanLink?

    @AppStorage(EmailMasking.defaultsKey) private var hideEmail = false

    public init(
        provider: AIProvider,
        icon: NSImage?,
        systemFallback: String,
        planName: String,
        email: String?,
        appName: String,
        onLaunch: @escaping () -> Void,
        planLink: PlanLink?
    ) {
        self.provider = provider
        self.icon = icon
        self.systemFallback = systemFallback
        self.planName = planName
        self.email = email
        self.appName = appName
        self.onLaunch = onLaunch
        self.planLink = planLink
    }

    private var tint: Color { LiquidGlassPalette.accent(for: provider) }

    public var body: some View {
        HStack(spacing: 10) {
            ProviderIconBadge(icon: icon, systemFallback: systemFallback, tint: tint, size: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(planName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(LiquidGlassText.primary)
                    .lineLimit(1)

                if let email = email, !email.isEmpty {
                    Text(hideEmail ? EmailMasking.mask(email) : email)
                        .font(.system(size: 11))
                        .foregroundColor(LiquidGlassText.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 0) {
                GlassIconButton(systemImage: "arrow.up.forward.app", help: "Open \(appName)", action: onLaunch)
                if let planLink = planLink {
                    GlassIconButton(systemImage: "creditcard", help: planLink.title) {
                        NSWorkspace.shared.open(planLink.url)
                    }
                }
            }
            .padding(2)
            .liquidGlassPill()
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: 14, tint: tint, material: .thinMaterial)
    }
}

// MARK: - Provider Icon Badge

/// App icon set in a tinted glass squircle with a soft accent glow.
public struct ProviderIconBadge: View {
    public let icon: NSImage?
    public let systemFallback: String
    public let tint: Color
    public let size: CGFloat

    public init(icon: NSImage?, systemFallback: String, tint: Color, size: CGFloat) {
        self.icon = icon
        self.systemFallback = systemFallback
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        let radius = size * 0.26

        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [tint.opacity(0.30), tint.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if let icon = icon {
                Image(nsImage: icon)
                    .resizable().scaledToFit()
                    .frame(width: size * 0.66, height: size * 0.66)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.15, style: .continuous))
            } else {
                Image(systemName: systemFallback)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundColor(tint)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.1), lineWidth: 1)
        )
        .shadow(color: tint.opacity(0.35), radius: size * 0.2, x: 0, y: size * 0.06)
    }
}

// MARK: - Empty State

/// Centered placeholder for disconnected or missing providers: haloed icon, title, message and actions.
public struct GlassEmptyState<Actions: View>: View {
    public let icon: NSImage?
    public let systemFallback: String
    public let tint: Color
    public let title: String
    public let message: String
    public let actions: Actions

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(
        icon: NSImage?,
        systemFallback: String,
        tint: Color,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) {
        self.icon = icon
        self.systemFallback = systemFallback
        self.tint = tint
        self.title = title
        self.message = message
        self.actions = actions()
    }

    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Concentric halo rings
                ForEach(0..<3) { ring in
                    Circle()
                        .strokeBorder(tint.opacity(0.22 - Double(ring) * 0.06), lineWidth: 1)
                        .frame(width: 84 + CGFloat(ring) * 24, height: 84 + CGFloat(ring) * 24)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [tint.opacity(0.28), tint.opacity(0.0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 70
                        )
                    )
                    .frame(width: 140, height: 140)

                Group {
                    if reduceTransparency {
                        Circle().fill(Color(NSColor.controlBackgroundColor))
                    } else {
                        Circle().fill(.thinMaterial)
                    }
                }
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.1), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 6)

                if let icon = icon {
                    Image(nsImage: icon)
                        .resizable().scaledToFit()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    Image(systemName: systemFallback)
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(tint)
                }
            }
            .frame(height: 140)

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LiquidGlassText.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundColor(LiquidGlassText.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
            }

            HStack(spacing: 10) {
                actions
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ambient Tint Bleed

/// Soft provider-coloured light pooled behind the popover content (tint bleed through the glass).
/// Gradients only, no blur, so it adds no offscreen passes. Hidden under Reduce Transparency.
public struct AmbientTintBackground: View {
    public let tint: Color

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(tint: Color) {
        self.tint = tint
    }

    public var body: some View {
        if reduceTransparency {
            Color.clear
        } else {
            ZStack {
                RadialGradient(
                    colors: [tint.opacity(0.22), tint.opacity(0.0)],
                    center: UnitPoint(x: 0.12, y: 0.0),
                    startRadius: 0,
                    endRadius: 260
                )
                RadialGradient(
                    colors: [tint.opacity(0.10), tint.opacity(0.0)],
                    center: UnitPoint(x: 1.0, y: 0.85),
                    startRadius: 0,
                    endRadius: 220
                )
            }
            .allowsHitTesting(false)
        }
    }
}
