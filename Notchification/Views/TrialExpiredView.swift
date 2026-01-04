//
//  TrialExpiredView.swift
//  Notchification
//
//  Shown when the trial period has expired
//

import SwiftUI

struct TrialExpiredView: View {
    @ObservedObject private var licenseManager = LicenseManager.shared
    @State private var licenseKey: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            // Icon
            Image(systemName: "clock.badge.xmark")
                .font(.system(size: 48))
                .foregroundColor(.red)

            // Title
            Text("Trial Expired")
                .font(.title)
                .fontWeight(.bold)

            // Message
            Text("Your 14-day free trial has ended.\nPurchase a license to continue using Notchification.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // License key input
            VStack(alignment: .leading, spacing: 6) {
                Text("Already have a license?")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("Enter license key", text: $licenseKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(licenseManager.isActivating)

                    Button("Activate") {
                        Task {
                            await licenseManager.activateLicense(key: licenseKey)
                        }
                    }
                    .disabled(licenseKey.isEmpty || licenseManager.isActivating)
                }
            }
            .padding(.horizontal, 20)

            // Error message
            if let error = licenseManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            // Loading
            if licenseManager.isActivating {
                ProgressView()
                    .scaleEffect(0.8)
            }

            Spacer()

            // Purchase button
            Button(action: {
                NSWorkspace.shared.open(licenseManager.purchaseURL)
            }) {
                HStack {
                    Image(systemName: "cart")
                    Text("Purchase License - $10")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(width: 350, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

#if DEBUG
#Preview {
    TrialExpiredView()
}
#endif
