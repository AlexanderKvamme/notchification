//
//  NotchView.swift
//  Notchification
//

import SwiftUI

struct NotchView: View {
    let activeProcesses: [ProcessType]

    // Animation state
    @State private var isExpanded: Bool = false

    // Dimensions
    private let expandedHeight: CGFloat = 120
    private let notchWidth: CGFloat = 300
    private let frameWidth: CGFloat = 380  // Extra 80 for outward curves

    // Pill dimensions
    private let pillHeight: CGFloat = 8
    private let segmentWidth: CGFloat = 50
    private let pillPadding: CGFloat = 16

    var body: some View {
        ZStack(alignment: .top) {
            // The notch shape - scales from top
            NotchShape()
                .fill(Color.black)
                .frame(width: notchWidth, height: expandedHeight)
                .scaleEffect(x: 1, y: isExpanded ? 1 : 0, anchor: .top)

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
                .offset(y: expandedHeight - pillPadding - pillHeight)
                .opacity(isExpanded ? 1 : 0)
                .scaleEffect(isExpanded ? 1 : 0.5)
            }
        }
        .frame(width: frameWidth, height: expandedHeight, alignment: .top)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: isExpanded)
        .onChange(of: activeProcesses.isEmpty) { _, isEmpty in
            isExpanded = !isEmpty
        }
        .onAppear {
            if !activeProcesses.isEmpty {
                // Small delay to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isExpanded = true
                }
            }
        }
    }
}

#Preview("Expanded") {
    VStack(spacing: 0) {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 24)

        NotchView(activeProcesses: [.claude])

        Spacer()
    }
    .frame(width: 400, height: 300)
    .background(Color.gray.opacity(0.2))
}

#Preview("Empty") {
    VStack(spacing: 0) {
        Rectangle()
            .fill(Color.gray.opacity(0.3))
            .frame(height: 24)

        NotchView(activeProcesses: [])

        Spacer()
    }
    .frame(width: 400, height: 300)
    .background(Color.gray.opacity(0.2))
}
