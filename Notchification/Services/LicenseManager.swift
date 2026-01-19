//
//  LicenseManager.swift
//  Notchification
//
//  Manages trial period and LemonSqueezy license validation
//

import Foundation
import Combine
import LemonSqueezyLicense
import os.log

private let logger = Logger(subsystem: "com.hoi.Notchification", category: "LicenseManager")

enum LicenseState: Equatable {
    case trial(daysRemaining: Int)
    case licensed
    case expired

    var isActive: Bool {
        switch self {
        case .trial, .licensed:
            return true
        case .expired:
            return false
        }
    }
}

final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var state: LicenseState = .expired
    @Published private(set) var isActivating: Bool = false
    @Published private(set) var lastError: String?

    private let trialDays: Int = 14
    private let license = LemonSqueezyLicense()

    // UserDefaults keys
    private let trialStartDateKey = "trialStartDate"
    private let licenseKeyKey = "licenseKey"
    private let licenseInstanceIdKey = "licenseInstanceId"
    private let licenseValidatedKey = "licenseValidated"

    // LemonSqueezy production checkout URL
    let purchaseURL = URL(string: "https://homeofficesinternational.lemonsqueezy.com/checkout/buy/f92881cf-2596-497c-b404-b1783a46bce3")!

    private init() {
        checkLicenseStatus()
    }

    // MARK: - Public Methods

    func checkLicenseStatus() {
        // First check if we have a stored valid license
        if let licenseKey = UserDefaults.standard.string(forKey: licenseKeyKey),
           let instanceId = UserDefaults.standard.string(forKey: licenseInstanceIdKey),
           UserDefaults.standard.bool(forKey: licenseValidatedKey) {
            // We have a cached valid license
            state = .licensed
            logger.info("License found in cache, validating in background...")

            // Validate in background (don't block the app)
            Task {
                await validateLicenseInBackground(key: licenseKey, instanceId: instanceId)
            }
            return
        }

        // No license, check trial status
        if let startDate = UserDefaults.standard.object(forKey: trialStartDateKey) as? Date {
            let daysUsed = Calendar.current.dateComponents([.day], from: startDate, to: Date()).day ?? 0
            let daysRemaining = max(0, trialDays - daysUsed)

            if daysRemaining > 0 {
                state = .trial(daysRemaining: daysRemaining)
                logger.info("Trial active: \(daysRemaining) days remaining")
            } else {
                state = .expired
                logger.info("Trial expired")
            }
        } else {
            // First launch - start trial
            UserDefaults.standard.set(Date(), forKey: trialStartDateKey)
            state = .trial(daysRemaining: trialDays)
            logger.info("Trial started: \(self.trialDays) days")
        }
    }

    @MainActor
    func activateLicense(key: String) async -> Bool {
        isActivating = true
        lastError = nil

        defer { isActivating = false }

        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            lastError = "Please enter a license key"
            return false
        }

        do {
            let instanceName = Host.current().localizedName ?? "Mac"
            let response = try await license.activate(key: trimmedKey, instanceName: instanceName)

            if response.activated, let instanceId = response.instance?.id {
                // Store the license
                UserDefaults.standard.set(trimmedKey, forKey: licenseKeyKey)
                UserDefaults.standard.set(instanceId, forKey: licenseInstanceIdKey)
                UserDefaults.standard.set(true, forKey: licenseValidatedKey)

                state = .licensed
                logger.info("License activated successfully")
                return true
            } else {
                lastError = "Activation failed - key may be invalid or already used"
                logger.error("License activation failed")
                return false
            }
        } catch let error as LemonSqueezyLicenseError {
            switch error {
            case .badServerResponse:
                lastError = "Could not connect to license server"
            case .serverError(let code, let message):
                lastError = message ?? "Server error (\(code))"
            }
            logger.error("License activation error: \(self.lastError ?? "unknown")")
            return false
        } catch {
            lastError = error.localizedDescription
            logger.error("License activation error: \(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    func deactivateLicense() async -> Bool {
        guard let licenseKey = UserDefaults.standard.string(forKey: licenseKeyKey),
              let instanceId = UserDefaults.standard.string(forKey: licenseInstanceIdKey) else {
            return false
        }

        isActivating = true
        defer { isActivating = false }

        do {
            let response = try await license.deactivate(key: licenseKey, instanceId: instanceId)

            if response.deactivated {
                clearStoredLicense()
                checkLicenseStatus()
                logger.info("License deactivated successfully")
                return true
            }
        } catch {
            logger.error("License deactivation error: \(error.localizedDescription)")
        }

        // Even if server deactivation fails, clear local state
        clearStoredLicense()
        checkLicenseStatus()
        return true
    }

    // MARK: - Private Methods

    private func validateLicenseInBackground(key: String, instanceId: String) async {
        do {
            let response = try await license.validate(key: key, instanceId: instanceId)

            await MainActor.run {
                if response.valid {
                    logger.info("Background license validation successful")
                } else {
                    logger.warning("Background license validation failed, clearing license")
                    clearStoredLicense()
                    checkLicenseStatus()
                }
            }
        } catch {
            // Don't invalidate on network errors - allow offline use
            logger.warning("Background license validation network error: \(error.localizedDescription)")
        }
    }

    private func clearStoredLicense() {
        UserDefaults.standard.removeObject(forKey: licenseKeyKey)
        UserDefaults.standard.removeObject(forKey: licenseInstanceIdKey)
        UserDefaults.standard.set(false, forKey: licenseValidatedKey)
    }

    // MARK: - Debug

    #if DEBUG
    func resetTrial() {
        clearStoredLicense()
        UserDefaults.standard.removeObject(forKey: trialStartDateKey)
        checkLicenseStatus()
        logger.info("Trial reset for debugging")
    }

    func expireTrial() {
        clearStoredLicense()
        let expiredDate = Calendar.current.date(byAdding: .day, value: -(trialDays + 1), to: Date())!
        UserDefaults.standard.set(expiredDate, forKey: trialStartDateKey)
        checkLicenseStatus()
        logger.info("Trial expired for debugging")
    }
    #endif
}
