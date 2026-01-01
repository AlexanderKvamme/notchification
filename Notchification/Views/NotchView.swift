//
//  NotchView.swift
//  Notchification
//

import SwiftUI

struct NotchView: View {
    let activeProcesses: [ProcessType]

    // Pill dimensions
    private let pillHeight: CGFloat = 8
    private let segmentWidth: CGFloat = 50
    private let pillPadding: CGFloat = 16

    var body: some View {
        ZStack(alignment: .bottom) {
            // The expanded notch shape
            ExpandedNotchShape()
                .fill(Color.black)

            // Colored pill at the bottom
            if !activeProcesses.isEmpty {
                HStack(spacing: 0) {
                    ForEach(activeProcesses) { process in
                        Rectangle()
                            .fill(process.color)
                            .frame(width: segmentWidth, height: pillHeight)
                    }
                }
                .clipShape(Capsule())
                .padding(.bottom, pillPadding)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: activeProcesses.count)
    }
}

#Preview("With processes") {
    VStack {
        NotchView(activeProcesses: [.claude])
            .frame(width: 240, height: 100)
            .padding(.bottom, 50)

        NotchView(activeProcesses: [.claude, .xcode])
            .frame(width: 240, height: 100)
            .padding(.bottom, 50)

        NotchView(activeProcesses: [.claude, .xcode, .androidStudio])
            .frame(width: 240, height: 100)
    }
    .frame(width: 400, height: 500)
    .background(Color.gray.opacity(0.3))
}

#Preview("Empty") {
    NotchView(activeProcesses: [])
        .frame(width: 240, height: 100)
        .background(Color.gray.opacity(0.3))
}
