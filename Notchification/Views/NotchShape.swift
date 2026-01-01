import SwiftUI

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let r = min(cornerRadius, min(width/2, height/2))

        // Smoothness factor - higher = smoother transition (0.55 ≈ circle, 0.7+ = squircle)
        let k: CGFloat = 0.7

        var path = Path()

        // Start at top-left ear
        path.move(to: CGPoint(x: -r, y: 0))

        // Top edge
        path.addLine(to: CGPoint(x: width + r, y: 0))

        // Top-right outward curve (smooth bezier)
        path.addCurve(
            to: CGPoint(x: width, y: r),
            control1: CGPoint(x: width + r * (1 - k), y: 0),
            control2: CGPoint(x: width, y: r * (1 - k))
        )

        // Right edge
        path.addLine(to: CGPoint(x: width, y: height - r))

        // Bottom-right inward curve (smooth bezier)
        path.addCurve(
            to: CGPoint(x: width - r, y: height),
            control1: CGPoint(x: width, y: height - r * (1 - k)),
            control2: CGPoint(x: width - r * (1 - k), y: height)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: r, y: height))

        // Bottom-left inward curve (smooth bezier)
        path.addCurve(
            to: CGPoint(x: 0, y: height - r),
            control1: CGPoint(x: r * (1 - k), y: height),
            control2: CGPoint(x: 0, y: height - r * (1 - k))
        )

        // Left edge
        path.addLine(to: CGPoint(x: 0, y: r))

        // Top-left outward curve (smooth bezier)
        path.addCurve(
            to: CGPoint(x: -r, y: 0),
            control1: CGPoint(x: 0, y: r * (1 - k)),
            control2: CGPoint(x: -r * (1 - k), y: 0)
        )

        path.closeSubpath()

        return path
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.2)

        NotchShape(cornerRadius: 40)
            .fill(Color.blue)
            .stroke(Color.red, lineWidth: 5)
            .frame(width: 300, height: 200)
    }
    .frame(width: 600, height: 500)
}
