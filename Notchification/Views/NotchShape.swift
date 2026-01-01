import SwiftUI

struct NotchShape: Shape {
    var cornerRadius: CGFloat = 40
    
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let radius = min(cornerRadius, min(width/2, height/2))
        
        var path = Path()
        
        // Start at top-left
        path.move(to: CGPoint(x: -cornerRadius, y: 0))
        
        // Top edge
        path.addLine(to: CGPoint(x: width+cornerRadius, y: 0))
        
        // Curve down from the top right
        path.addArc(
            center: CGPoint(x: width+cornerRadius, y: cornerRadius),
            radius: radius,
            startAngle: Angle(degrees: -90),
            endAngle: Angle(degrees: -180),
            clockwise: true
        )
        
        // Right edge down to the corner
        path.addLine(to: CGPoint(x: width, y: height - radius))
        
        // Bottom-right corner
        path.addArc(
            center: CGPoint(x: width - radius, y: height - radius),
            radius: radius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 90),
            clockwise: false
        )
        
        // Bottom edge
        path.addLine(to: CGPoint(x: radius, y: height))
        
        // Bottom-left corner
        path.addArc(
            center: CGPoint(x: radius, y: height - radius),
            radius: radius,
            startAngle: Angle(degrees: 90),
            endAngle: Angle(degrees: 180),
            clockwise: false
        )
        
        // Left edge back to top
        path.addLine(to: CGPoint(x: 0, y: radius))
        
        // Round up and to the left
        path.addArc(
            center: CGPoint(x: 0-radius, y: radius),
            radius: radius,
            startAngle: Angle(degrees: 0),
            endAngle: Angle(degrees: 270),
            clockwise: true
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
