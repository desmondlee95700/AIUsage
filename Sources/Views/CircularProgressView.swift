import SwiftUI

public struct CircularProgressView: View {
    public let fraction: Double
    public let size: CGFloat
    public let strokeWidth: CGFloat
    
    public init(fraction: Double, size: CGFloat = 32, strokeWidth: CGFloat = 4.0) {
        self.fraction = max(0.0, min(1.0, fraction))
        self.size = size
        self.strokeWidth = strokeWidth
    }
    
    private var gradientColors: [Color] {
        if fraction >= 0.5 {
            return [
                Color(red: 0.18, green: 0.72, blue: 0.85),
                Color(red: 0.20, green: 0.84, blue: 0.52)
            ]
        } else if fraction >= 0.2 {
            return [
                Color(red: 0.98, green: 0.82, blue: 0.28),
                Color(red: 0.98, green: 0.62, blue: 0.16)
            ]
        } else {
            return [
                Color(red: 0.98, green: 0.46, blue: 0.42),
                Color(red: 0.95, green: 0.26, blue: 0.32)
            ]
        }
    }
    
    private var primaryColor: Color {
        gradientColors.last ?? .green
    }
    
    public var body: some View {
        ZStack {
            // Background Liquid Glass Track
            Circle()
                .stroke(
                    Color.white.opacity(0.09),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
            
            // Progress Arc with Refractive Angular Gradient
            Circle()
                .trim(from: 0.0, to: CGFloat(fraction))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: gradientColors),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: primaryColor.opacity(0.40), radius: 3, x: 0, y: 0)
                .animation(LiquidGlassTokens.metricSpring, value: fraction)
        }
        .frame(width: size, height: size)
    }
}
