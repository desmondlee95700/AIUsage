import SwiftUI

public struct CreditsCardView: View {
    public let planStatus: PlanStatus?
    @State private var overagesEnabled: Bool = false
    
    public init(planStatus: PlanStatus?) {
        self.planStatus = planStatus
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.98))
                
                Text("Model Credits")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Enable AI Credit Overages")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(.white)
                        
                        Text("When toggled on, Antigravity IDE will use your AI credits to fulfill model requests once you're out of model quota.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.white.opacity(0.60))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $overagesEnabled)
                        .toggleStyle(SwitchToggleStyle(tint: Color(red: 0.25, green: 0.48, blue: 0.98)))
                        .labelsHidden()
                }
                
                if let prompt = planStatus?.availablePromptCredits, let flow = planStatus?.availableFlowCredits {
                    Divider()
                        .background(Color.white.opacity(0.06))
                    
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Text("Prompt Credits:")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.60))
                            Text("\(prompt)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        
                        HStack(spacing: 6) {
                            Text("Flow Credits:")
                                .font(.system(size: 11.5))
                                .foregroundColor(.white.opacity(0.60))
                            Text("\(flow)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .padding(14)
            .liquidGlassCard(cornerRadius: 14, material: .thinMaterial)
        }
    }
}
