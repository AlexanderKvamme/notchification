//
//  MorningOverviewView.swift
//  Notchification
//
//  Displays today's calendar overview - content only, no background.
//  Background is handled by the notch shape in NotchView.
//

import SwiftUI

// Layout constants for grid alignment
private enum Layout {
    static let leftColumnWidth: CGFloat = 50  // Width for time/duration or "All day"
    static let columnSpacing: CGFloat = 16    // Space between left and right columns
    static let rowSpacing: CGFloat = 14       // Space between event rows
    static let lineSpacing: CGFloat = 2       // Space between lines within a row
}

/// Morning overview content showing today's calendar
struct MorningOverviewContent: View {
    let data: MorningOverviewData
    var onDismiss: (() -> Void)? = nil

    @State private var isHovering: Bool = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: Layout.rowSpacing) {
                if data.isEmpty {
                    Text("No events today")
                        .font(.custom("FiraCode-Regular", size: 12))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    // All-day events
                    ForEach(data.allDayEvents) { event in
                        AllDayEventRow(event: event, onDismiss: onDismiss)
                    }

                    // Separator between all-day and timed events
                    if !data.allDayEvents.isEmpty && !data.timedEvents.isEmpty {
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 1)
                            .padding(.top, -2)  // Reduce space above line to balance visually
                    }

                    // Timed events
                    ForEach(data.timedEvents) { event in
                        TimedEventRow(event: event, onDismiss: onDismiss)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

/// All-day event row - aligned to same grid as timed events
struct AllDayEventRow: View {
    let event: MorningEvent
    var onDismiss: (() -> Void)? = nil

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: Layout.columnSpacing) {
            // Left column: "All day" label (right-aligned to match time column)
            Text("All day")
                .font(.custom("FiraCode-Regular", size: 12))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: Layout.leftColumnWidth, alignment: .trailing)

            // Right column: title
            Text(event.title)
                .font(.custom("FiraCode-Medium", size: 12))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            // X button appears on hover
            if isHovering {
                Image(systemName: "xmark")
                    .font(.custom("FiraCode-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .transition(.opacity)
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss?()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

/// Timed event row: time+duration on left, title+location on right
struct TimedEventRow: View {
    let event: MorningEvent
    var onDismiss: (() -> Void)? = nil

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: Layout.columnSpacing) {
            // Left column: time and duration stacked
            VStack(alignment: .trailing, spacing: Layout.lineSpacing) {
                Text(event.formattedTime)
                    .font(.custom("FiraCode-Medium", size: 12))
                    .foregroundColor(.white)

                Text(event.formattedDuration)
                    .font(.custom("FiraCode-Regular", size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            .frame(width: Layout.leftColumnWidth, alignment: .trailing)

            // Right column: title and location stacked
            VStack(alignment: .leading, spacing: Layout.lineSpacing) {
                Text(event.title)
                    .font(.custom("FiraCode-Medium", size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)

                if let room = event.meetingRoom {
                    Text(room)
                        .font(.custom("FiraCode-Regular", size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            Spacer()

            // X button appears on hover (aligned to top)
            if isHovering {
                Image(systemName: "xmark")
                    .font(.custom("FiraCode-Medium", size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .transition(.opacity)
            }
        }
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss?()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black

        MorningOverviewContent(
            data: MorningOverviewData(
                allDayEvents: [
                    MorningEvent(
                        title: "Eric's birthday",
                        startDate: Date(),
                        endDate: Date(),
                        location: nil,
                        isAllDay: true
                    )
                ],
                timedEvents: [
                    MorningEvent(
                        title: "Daily with Mark S",
                        startDate: Date(),
                        endDate: Date().addingTimeInterval(2700), // 45 min
                        location: "Human office B",
                        isAllDay: false
                    ),
                    MorningEvent(
                        title: "Daily with Mark S",
                        startDate: Date().addingTimeInterval(3600),
                        endDate: Date().addingTimeInterval(6300), // 45 min
                        location: "Human office B",
                        isAllDay: false
                    ),
                    MorningEvent(
                        title: "Daily with Mark S",
                        startDate: Date().addingTimeInterval(7200),
                        endDate: Date().addingTimeInterval(9900), // 45 min
                        location: "Human office B",
                        isAllDay: false
                    )
                ]
            )
        )
        .padding(16)
        .frame(width: 320)
    }
    .frame(width: 380, height: 320)
}
