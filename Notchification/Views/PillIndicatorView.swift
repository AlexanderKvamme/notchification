//
//  PillIndicatorView.swift
//  Notchification
//

import SwiftUI

struct PillIndicatorView: View {
    let activeProcesses: [ProcessType]

    private let segmentWidth: CGFloat = 40
    private let pillHeight: CGFloat = 8
    private let cornerRadius: CGFloat = 4

    var body: some View {
        HStack(spacing: 0) {
            ForEach(activeProcesses) { process in
                ProcessSegment(process: process, height: pillHeight)
            }
        }
        .clipShape(Capsule())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: activeProcesses.count)
    }
}

struct ProcessSegment: View {
    let process: ProcessType
    let height: CGFloat

    private let segmentWidth: CGFloat = 50

    var body: some View {
        Rectangle()
            .fill(process.color)
            .frame(width: segmentWidth, height: height)
            .transition(.asymmetric(
                insertion: .scale(scale: 0, anchor: .leading).combined(with: .opacity),
                removal: .scale(scale: 0, anchor: .trailing).combined(with: .opacity)
            ))
    }
}

#Preview {
    VStack(spacing: 20) {
        PillIndicatorView(activeProcesses: [.claude])
        PillIndicatorView(activeProcesses: [.claude, .xcode])
        PillIndicatorView(activeProcesses: [.claude, .xcode, .androidStudio])
    }
    .padding(40)
    .background(Color.black)
}
