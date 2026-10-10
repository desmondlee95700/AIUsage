import SwiftUI
import Cocoa

public struct ProviderFocusSubmenuView: View {
    @ObservedObject var service: QuotaService
    var onDismiss: (() -> Void)?
    
    @State private var hoveredRow: String? = nil
    
    public init(service: QuotaService = .shared, onDismiss: (() -> Void)? = nil) {
        self.service = service
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Header hint
            HStack {
                Text("Select Active Providers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(LiquidGlassText.tertiary)
                Spacer()
                GlassChip("Multi-Select", tint: LiquidGlassPalette.aiBlue)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 2)
            
            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            
            // "All Providers" Option (if more than 1 installed)
            if service.installedProvidersCount > 1 {
                menuRow(
                    id: "all",
                    tint: LiquidGlassPalette.aiBlue,
                    title: "All Providers",
                    icon: AppIconHelper.combinedTemplate(for: service.installedProviders),
                    systemFallback: "sparkles",
                    isChecked: service.isAllProvidersSelected
                ) {
                    service.selectAllProviders()
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
            }
            
            // Antigravity (Google)
            if service.isGeminiInstalled {
                menuRow(
                    id: "gemini",
                    tint: LiquidGlassPalette.antigravity,
                    title: "Antigravity (Google)",
                    icon: AppIconHelper.antigravityTemplate,
                    systemFallback: "sparkles",
                    isChecked: service.isProviderSelected(.gemini)
                ) {
                    if NSEvent.modifierFlags.contains(.option) {
                        service.selectOnlyProvider(.gemini)
                    } else {
                        service.toggleProviderSelection(.gemini)
                    }
                }
            }
            
            // ChatGPT (OpenAI)
            if service.isCodexInstalled {
                menuRow(
                    id: "chatgpt",
                    tint: LiquidGlassPalette.chatgpt,
                    title: "ChatGPT (OpenAI)",
                    icon: AppIconHelper.chatgptTemplate,
                    systemFallback: "circle.hexagongrid",
                    isChecked: service.isProviderSelected(.chatgpt)
                ) {
                    if NSEvent.modifierFlags.contains(.option) {
                        service.selectOnlyProvider(.chatgpt)
                    } else {
                        service.toggleProviderSelection(.chatgpt)
                    }
                }
            }
            
            // Claude (Anthropic)
            if service.isClaudeInstalled {
                menuRow(
                    id: "claude",
                    tint: LiquidGlassPalette.claude,
                    title: "Claude (Anthropic)",
                    icon: AppIconHelper.claudeTemplate,
                    systemFallback: "asterisk",
                    isChecked: service.isProviderSelected(.claude)
                ) {
                    if NSEvent.modifierFlags.contains(.option) {
                        service.selectOnlyProvider(.claude)
                    } else {
                        service.toggleProviderSelection(.claude)
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.10))
                .padding(.horizontal, 6)
                .padding(.top, 3)
                .padding(.bottom, 2)
            
            // Footer: Dismiss Button
            HStack {
                Text("⌥-click to isolate single")
                    .font(.system(size: 10))
                    .foregroundColor(LiquidGlassText.tertiary)
                
                Spacer()
                
                GlassCapsuleButton("Done", trailingSystemImage: "checkmark", style: .prominent(LiquidGlassPalette.aiBlue), size: .small) {
                    onDismiss?()
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(4)
        .frame(width: 236)
    }
    
    private func menuRow(
        id: String,
        tint: Color,
        title: String,
        icon: NSImage?,
        systemFallback: String,
        isChecked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredRow == id
        
        return Button(action: action) {
            HStack(spacing: 7) {
                // Glass checkbox filled with the provider accent when selected
                ZStack {
                    Circle()
                        .fill(isChecked ? tint : Color.white.opacity(0.06))
                    Circle()
                        .strokeBorder(
                            isChecked
                                ? LiquidGlassTokens.specularBorder(isDark: true, intensity: 1.4)
                                : LiquidGlassTokens.specularBorder(isDark: true, intensity: 0.9),
                            lineWidth: 0.8
                        )
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 7.5, weight: .heavy))
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 14, height: 14)
                .shadow(color: isChecked ? tint.opacity(0.45) : .clear, radius: 3)
                
                // Icon
                Group {
                    if let icon = icon {
                        Image(nsImage: icon)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(isHovered || isChecked ? .white : LiquidGlassText.secondary)
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: systemFallback)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(isHovered || isChecked ? .white : LiquidGlassText.secondary)
                            .frame(width: 14, height: 14)
                    }
                }
                
                // Title
                Text(title)
                    .font(.system(size: 12.5, weight: isChecked ? .semibold : .regular))
                    .foregroundColor(isHovered || isChecked ? LiquidGlassText.primary : LiquidGlassText.secondary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color.white.opacity(0.12) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(LiquidGlassTokens.specularBorder(isDark: true, intensity: isHovered ? 0.8 : 0.0), lineWidth: 0.8)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(LiquidGlassTokens.hoverSpring, value: isHovered)
        .onHover { hovering in
            if hovering {
                hoveredRow = id
            } else if hoveredRow == id {
                hoveredRow = nil
            }
        }
    }
}
