//
//  NotchShape.swift
//  Notchification
//

import SwiftUI

/// Notch shape - top curves outward into menu bar
struct ExpandedNotchShape: Shape {
    var topCurve: CGFloat = 16
    var bottomCurve: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let width = rect.width
        let height = rect.height

        // Body is inset from edges by topCurve amount
        let bodyLeft = topCurve
        let bodyRight = width - topCurve

        // Start at top-left corner of the full bounds (menu bar edge)
        path.move(to: CGPoint(x: 0, y: 0))

        // Go along top edge
        path.addLine(to: CGPoint(x: width, y: 0))

        // Top-right: curve down from menu bar into body (curves right then down)
        path.addQuadCurve(
            to: CGPoint(x: bodyRight, y: topCurve),
            control: CGPoint(x: bodyRight, y: 0)
        )

        // Right edge straight down
        path.addLine(to: CGPoint(x: bodyRight, y: height - bottomCurve))

        // Bottom-right: normal rounded corner
        path.addQuadCurve(
            to: CGPoint(x: bodyRight - bottomCurve, y: height),
            control: CGPoint(x: bodyRight, y: height)
        )

        // Bottom edge
        path.addLine(to: CGPoint(x: bodyLeft + bottomCurve, y: height))

        // Bottom-left: normal rounded corner
        path.addQuadCurve(
            to: CGPoint(x: bodyLeft, y: height - bottomCurve),
            control: CGPoint(x: bodyLeft, y: height)
        )

        // Left edge straight up
        path.addLine(to: CGPoint(x: bodyLeft, y: topCurve))

        // Top-left: curve up from body into menu bar (curves left then up)
        path.addQuadCurve(
            to: CGPoint(x: 0, y: 0),
            control: CGPoint(x: bodyLeft, y: 0)
        )

        path.closeSubpath()

        return path
    }
}

#Preview {
    VStack(spacing: 0) {
        Rectangle()
            .fill(Color.pink.opacity(0.5))
            .frame(height: 24)

        HStack {
            Spacer()
            ExpandedNotchShape()
                .fill(Color.blue.opacity(0.5))
                .frame(width: 280, height: 100)
            Spacer()
        }

        Spacer()
    }
    .frame(width: 600, height: 200)
    .background(Color.gray.opacity(0.2))
}
