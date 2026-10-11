import SwiftUI

public struct PlanCardView: View {
    public let userTier: UserTier?
    public let email: String?
    public let name: String?

    public init(userTier: UserTier?, email: String? = nil, name: String? = nil) {
        self.userTier = userTier
        self.email = email
        self.name = name
    }

    public var body: some View {
        let upgradeURL = userTier?.upgradeSubscriptionUri.flatMap { URL(string: $0) }

        ProviderPlanCard(
            provider: .gemini,
            icon: AppIconHelper.antigravityIcon,
            systemFallback: "sparkles",
            planName: userTier?.name ?? "Google AI",
            email: email,
            appName: "Antigravity",
            onLaunch: { ProcessDiscovery.launchAntigravityApp() },
            planLink: upgradeURL.map { .init(title: "Upgrade plan", url: $0) }
        )
    }
}
