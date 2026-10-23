import SwiftUI

/// Compact unlabelled ring for tight spots such as the provider switcher. Larger gauges use `LiquidRingGauge`.
public struct CircularProgressView: View {
    public let fraction: Double
    public let size: CGFloat
    public let strokeWidth: CGFloat

    public init(fraction: Double, size: CGFloat = 32, strokeWidth: CGFloat = 4.0) {
        self.fraction = max(0.0, min(1.0, fraction))
        self.size = size
        self.strokeWidth = strokeWidth
    }

    public var body: some View {
        LiquidRingGauge(fraction: fraction, size: size, lineWidth: strokeWidth, showsLabel: false)
    }
}
