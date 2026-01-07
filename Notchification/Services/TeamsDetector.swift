//
//  TeamsDetector.swift
//  Notchification
//
//  Detects when Microsoft Teams is launched to show camera preview.
//  Hides when camera becomes active (user joined meeting).
//  Color: #6264A7 (Teams purple)
//

import Foundation
import Combine
import AppKit
import AVFoundation

/// Detects Teams launch to show camera preview before meetings
final class TeamsDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .teams

    // No debouncing needed - we want instant response
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 1

    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Track if Teams was running in previous poll (to detect launch)
    private var wasTeamsRunning: Bool = false

    // Track if we've been dismissed for this Teams session
    private var dismissedThisSession: Bool = false

    // Track if camera is warming up
    private var cameraStarted: Bool = false

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.teams-check", qos: .utility)

    init() {}

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        wasTeamsRunning = false
        dismissedThisSession = false
        cameraStarted = false
        isActive = false
        CameraManager.shared.stopSession()
    }

    func poll() {
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let teamsRunning = self.isTeamsRunning()
            let cameraInUse = self.isCameraInUse()

            // Teams quit - reset session state
            if !teamsRunning && self.wasTeamsRunning {
                DispatchQueue.main.async {
                    self.dismissedThisSession = false
                    self.wasTeamsRunning = false
                    self.cameraStarted = false
                    self.consecutiveActiveReadings = 0
                    self.consecutiveInactiveReadings = 0
                    CameraManager.shared.stopSession()
                    if self.isActive {
                        self.isActive = false
                    }
                }
                return
            }

            // Teams not running
            if !teamsRunning {
                DispatchQueue.main.async {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                        CameraManager.shared.stopSession()
                        self.cameraStarted = false
                    }
                }
                return
            }

            // Teams is running - start camera to pre-warm if not already started
            if !self.cameraStarted && !self.dismissedThisSession && !cameraInUse {
                DispatchQueue.main.async {
                    self.cameraStarted = true
                    CameraManager.shared.startSession()
                }
            }

            self.wasTeamsRunning = teamsRunning

            // Determine if we should be active:
            // - Teams is running
            // - Camera is NOT in use by another app (not in a meeting)
            // - Not dismissed this session
            // - Camera has first frame ready
            let hasFrame = CameraManager.shared.hasFirstFrame
            let shouldBeActive = teamsRunning && !cameraInUse && !self.dismissedThisSession && hasFrame

            // If camera just became active (user joined meeting), mark as dismissed
            if teamsRunning && cameraInUse && self.isActive {
                DispatchQueue.main.async {
                    self.dismissedThisSession = true
                    CameraManager.shared.stopSession()
                    self.cameraStarted = false
                }
            }

            DispatchQueue.main.async {
                if shouldBeActive {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0
                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0
                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Mark as dismissed by user click
    func dismiss() {
        dismissedThisSession = true
        cameraStarted = false
        isActive = false
        CameraManager.shared.stopSession()
    }

    private func isTeamsRunning() -> Bool {
        // Check for both old Teams and new Teams (Teams 2.0)
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.microsoft.teams" ||
            $0.bundleIdentifier == "com.microsoft.teams2"
        }
    }

    /// Check if the camera is currently in use by any application
    private func isCameraInUse() -> Bool {
        // Use AVCaptureDevice to check camera status
        guard let device = AVCaptureDevice.default(for: .video) else {
            return false
        }

        // Check if another app is using the camera
        // Note: This will return true if ANY app is using the camera
        return device.isInUseByAnotherApplication
    }
}
