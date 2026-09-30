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
                    .foregroundColor(.white.opacity(0.50))
                Spacer()
                Text("Multi-Select")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.35, green: 0.65, blue: 1.0))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.18))
                    )
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
                    title: "All Providers",
                    icon: AppIconHelper.dualTemplate,
                    systemFallback: "sparkles",
                    shortcut: "⌘A",
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
                    title: "Antigravity (Google)",
                    icon: AppIconHelper.antigravityTemplate,
                    systemFallback: "sparkles",
                    shortcut: "⌘1",
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
                    title: "ChatGPT (OpenAI)",
                    icon: AppIconHelper.chatgptTemplate,
                    systemFallback: "circle.hexagongrid",
                    shortcut: "⌘2",
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
                    title: "Claude (Anthropic)",
                    icon: AppIconHelper.claudeTemplate,
                    systemFallback: "asterisk",
                    shortcut: "⌘3",
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
                    .foregroundColor(.white.opacity(0.40))
                
                Spacer()
                
                Button(action: {
                    onDismiss?()
                }) {
                    HStack(spacing: 3) {
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.25, green: 0.55, blue: 0.95))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
        }
        .padding(4)
        .frame(width: 236)
    }
    
    private func menuRow(
        id: String,
        title: String,
        icon: NSImage?,
        systemFallback: String,
        shortcut: String,
        isChecked: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let isHovered = hoveredRow == id
        
        return Button(action: action) {
            HStack(spacing: 7) {
                // Checkmark
                Group {
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(isHovered ? .white : Color(red: 0.35, green: 0.65, blue: 1.0))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 14, height: 14)
                
                // Icon
                Group {
                    if let icon = icon {
                        Image(nsImage: icon)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .foregroundColor(isHovered ? .white : .white.opacity(0.85))
                            .frame(width: 14, height: 14)
                    } else {
                        Image(systemName: systemFallback)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(isHovered ? .white : .white.opacity(0.85))
                            .frame(width: 14, height: 14)
                    }
                }
                
                // Title
                Text(title)
                    .font(.system(size: 12.5, weight: isChecked ? .semibold : .regular))
                    .foregroundColor(isHovered ? .white : .white.opacity(isChecked ? 0.95 : 0.75))
                    .lineLimit(1)
                
                Spacer()
                
                // Shortcut badge
                Text(shortcut)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundColor(isHovered ? .white.opacity(0.90) : .white.opacity(0.35))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredRow = id
            } else if hoveredRow == id {
                hoveredRow = nil
            }
        }
    }
}
