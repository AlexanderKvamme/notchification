//
//  CameraPreviewView.swift
//  Notchification
//
//  Camera preview view for Teams pre-meeting selfie check.
//  Uses video frame capture instead of preview layer for compatibility with overlay windows.
//

import SwiftUI
import AVFoundation
import AppKit

/// SwiftUI wrapper for camera preview
/// Hover to enlarge, move mouse away to dismiss
struct CameraPreviewView: View {
    var onDismiss: (() -> Void)?

    @ObservedObject private var cameraManager = CameraManager.shared
    @State private var isHovered = false
    @State private var hasBeenHovered = false  // Track if user has hovered at least once

    var body: some View {
        ZStack {
            // Solid black background to prevent anything showing through
            Color.black
                .clipShape(RoundedRectangle(cornerRadius: 20))

            if let image = cameraManager.currentFrame {
                // Show camera feed only when we have a frame
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(x: -1, y: 1)  // Mirror horizontally
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                // Subtle border
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            } else if cameraManager.authorizationDenied {
                // Camera access denied - tap to open settings
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Camera access denied")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    Text("Click to open Settings")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else {
                // Loading/requesting permission - just show spinner on black background
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            }
        }
        .scaleEffect(isHovered ? 1.8 : 1.0, anchor: .top)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .onHover { hovering in
            if hovering {
                isHovered = true
                hasBeenHovered = true
            } else {
                isHovered = false
                // Dismiss when mouse leaves (only if they've hovered at least once)
                if hasBeenHovered {
                    onDismiss?()
                }
            }
        }
        .contentShape(Rectangle())
        // Note: Camera session is managed by TeamsDetector for pre-warming
    }
}

/// Shared camera manager - can be pre-warmed before showing UI
final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published var isAuthorized: Bool = false
    @Published var authorizationDenied: Bool = false
    @Published var currentFrame: NSImage?
    @Published var hasFirstFrame: Bool = false  // True once we have video

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isRunning = false
    private let sessionQueue = DispatchQueue(label: "com.notchification.camera-session")
    private let videoOutputQueue = DispatchQueue(label: "com.notchification.video-output")

    override init() {
        super.init()
    }

    func startSession() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        print("Camera startSession - status: \(status.rawValue)")

        switch status {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
                self.authorizationDenied = false
            }
            setupAndStartSession()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                print("Camera: permission granted = \(granted)")
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    self?.authorizationDenied = !granted
                }
                if granted {
                    self?.setupAndStartSession()
                }
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
                self.isAuthorized = false
                self.authorizationDenied = true
            }

        @unknown default:
            break
        }
    }

    private func setupAndStartSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRunning else {
                print("Camera: session already running")
                return
            }

            print("Camera: configuring session...")
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .medium

            // Add video input
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                  ?? AVCaptureDevice.default(for: .video) else {
                print("Camera: no video device found")
                self.captureSession.commitConfiguration()
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if self.captureSession.canAddInput(videoInput) {
                    self.captureSession.addInput(videoInput)
                    print("Camera: added video input")
                }
            } catch {
                print("Camera: failed to create video input: \(error)")
                self.captureSession.commitConfiguration()
                return
            }

            // Add video output for frame capture
            self.videoOutput.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]

            if self.captureSession.canAddOutput(self.videoOutput) {
                self.captureSession.addOutput(self.videoOutput)
                print("Camera: added video output")
            }

            self.captureSession.commitConfiguration()

            // Start the session
            print("Camera: starting session...")
            self.captureSession.startRunning()
            self.isRunning = true
            print("Camera: session running = \(self.captureSession.isRunning)")
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self, self.isRunning else { return }
            self.captureSession.stopRunning()
            self.isRunning = false
            DispatchQueue.main.async {
                self.currentFrame = nil
                self.hasFirstFrame = false
            }
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

        DispatchQueue.main.async { [weak self] in
            self?.currentFrame = nsImage
            if self?.hasFirstFrame == false {
                self?.hasFirstFrame = true
            }
        }
    }
}

#Preview {
    CameraPreviewView()
        .frame(width: 200, height: 150)
        .background(Color.black)
}
