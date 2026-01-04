//
//  LicenseWindow.swift
//  Notchification
//
//  Window controller for License activation
//

import AppKit
import SwiftUI

/// Manages the License window
final class LicenseWindowController {
    static let shared = LicenseWindowController()

    private var window: NSWindow?

    private init() {}

    func showLicenseWindow() {
        // If window exists and is visible, just bring it to front
        if let existingWindow = window, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create new window
        let licenseView = LicenseView()
        let hostingController = NSHostingController(rootView: licenseView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Notchification License"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 400, height: 300))
        window.center()
        window.setFrameAutosaveName("LicenseWindow")
        window.isReleasedWhenClosed = false
        window.level = .floating

        self.window = window

        NSApp.setActivationPolicy(.accessory)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
    }
}

// MARK: - License View

struct LicenseView: View {
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var licenseKey: String = ""

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)

                Text("Activate License")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top, 10)

            // Status
            statusView

            // License key input
            VStack(alignment: .leading, spacing: 8) {
                Text("License Key")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Enter your license key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(licenseManager.isActivating || licenseManager.state == .licensed)
            }

            // Error message
            if let error = licenseManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // Buttons
            HStack(spacing: 12) {
                if licenseManager.state == .licensed {
                    Button("Deactivate") {
                        Task {
                            await licenseManager.deactivateLicense()
                        }
                    }
                    .disabled(licenseManager.isActivating)
                } else {
                    Button("Purchase License") {
                        NSWorkspace.shared.open(licenseManager.purchaseURL)
                    }

                    Button("Activate") {
                        Task {
                            let success = await licenseManager.activateLicense(key: licenseKey)
                            if success {
                                licenseKey = ""
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(licenseKey.isEmpty || licenseManager.isActivating)
                }
            }

            if licenseManager.isActivating {
                ProgressView()
                    .scaleEffect(0.7)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 360, height: 280)
    }

    @ViewBuilder
    private var statusView: some View {
        switch licenseManager.state {
        case .licensed:
            Label("Licensed", systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
                .font(.headline)

        case .trial(let daysRemaining):
            Label("\(daysRemaining) days left in trial", systemImage: "clock")
                .foregroundColor(.orange)
                .font(.headline)

        case .expired:
            Label("Trial expired", systemImage: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.headline)
        }
    }
}

#if DEBUG
#Preview {
    LicenseView()
}
#endif
