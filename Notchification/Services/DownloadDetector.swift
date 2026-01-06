//
//  DownloadDetector.swift
//  Notchification
//
//  Detects active browser downloads by monitoring ~/Downloads for partial files
//  (.crdownload for Chrome/Brave, .download for Safari, .part for Firefox)
//  Only shows as active when file size is growing (not paused/orphaned)
//

import Foundation
import Combine
import AppKit

/// Detects active downloads by watching for partial download files
final class DownloadDetector: ObservableObject, Detector {
    @Published private(set) var isActive: Bool = false

    let processType: ProcessType = .downloads

    private let downloadsPath: String
    private let partialExtensions = ["crdownload", "download", "part"]

    // Track file sizes to detect growth
    private var previousFileSizes: [String: UInt64] = [:]

    // Consecutive readings required
    private let requiredToShow: Int = 1
    private let requiredToHide: Int = 2

    // Counters
    private var consecutiveActiveReadings: Int = 0
    private var consecutiveInactiveReadings: Int = 0

    // Serial queue ensures checks don't overlap
    private let checkQueue = DispatchQueue(label: "com.notchification.download-check", qos: .utility)

    private var debug: Bool { DebugSettings.shared.debugDownloads }

    init() {
        self.downloadsPath = NSString(string: "~/Downloads").expandingTildeInPath
        if debug {
            print("⬇️ DownloadDetector init - watching: \(downloadsPath)")
        }
    }

    func reset() {
        consecutiveActiveReadings = 0
        consecutiveInactiveReadings = 0
        previousFileSizes = [:]
        isActive = false
    }

    func poll() {
        checkQueue.async { [weak self] in
            guard let self = self else { return }

            let isDownloading = self.checkForActiveDownloads()

            DispatchQueue.main.async {
                if self.debug {
                    print("⬇️ Downloads active=\(isDownloading)")
                }

                if isDownloading {
                    self.consecutiveActiveReadings += 1
                    self.consecutiveInactiveReadings = 0

                    if self.consecutiveActiveReadings >= self.requiredToShow && !self.isActive {
                        if self.debug { print("⬇️ >>> SHOWING DOWNLOAD INDICATOR") }
                        self.isActive = true
                    }
                } else {
                    self.consecutiveInactiveReadings += 1
                    self.consecutiveActiveReadings = 0

                    if self.consecutiveInactiveReadings >= self.requiredToHide && self.isActive {
                        if self.debug { print("⬇️ >>> HIDING DOWNLOAD INDICATOR") }
                        self.isActive = false
                    }
                }
            }
        }
    }

    /// Check for partial download files that are actively growing
    private func checkForActiveDownloads() -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: downloadsPath) else {
            if debug { print("⬇️ Cannot read Downloads folder") }
            return false
        }

        // Find all partial download files
        let partialFiles = contents.filter { file in
            let ext = (file as NSString).pathExtension.lowercased()
            return partialExtensions.contains(ext)
        }

        if partialFiles.isEmpty {
            if debug && !previousFileSizes.isEmpty {
                print("⬇️ No partial files found")
            }
            previousFileSizes = [:]
            return false
        }

        if debug {
            print("⬇️ Found \(partialFiles.count) partial file(s): \(partialFiles)")
        }

        // Check if any file is growing
        var currentFileSizes: [String: UInt64] = [:]
        var anyFileGrowing = false

        for file in partialFiles {
            let filePath = (downloadsPath as NSString).appendingPathComponent(file)

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
                  let fileSize = attrs[.size] as? UInt64 else {
                continue
            }

            currentFileSizes[file] = fileSize

            // Check if this file has grown since last poll
            if let previousSize = previousFileSizes[file] {
                if fileSize > previousSize {
                    if debug {
                        print("⬇️ File growing: \(file) (\(previousSize) → \(fileSize))")
                    }
                    anyFileGrowing = true
                } else if debug {
                    print("⬇️ File stalled: \(file) (size: \(fileSize))")
                }
            } else {
                // New file - consider it as potentially active, will confirm on next poll
                if debug {
                    print("⬇️ New partial file: \(file) (size: \(fileSize))")
                }
                // Give new files benefit of the doubt - mark as growing
                // They'll be filtered out next poll if not actually growing
                anyFileGrowing = true
            }
        }

        previousFileSizes = currentFileSizes
        return anyFileGrowing
    }
}
