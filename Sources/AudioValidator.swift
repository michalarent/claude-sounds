import Foundation

// MARK: - Audio File Validator

struct AudioValidator {

    static let allowedExtensions: Set<String> = ["wav", "mp3", "aiff", "m4a", "ogg", "aac"]
    static let maxFileSize: UInt64 = 10 * 1024 * 1024  // 10 MB
    static let maxNestingDepth = 3

    // MARK: - Magic Byte Validation

    /// Checks first 12 bytes for known audio format signatures.
    static func isValidAudioFile(at path: String) -> Bool {
        guard let fh = FileHandle(forReadingAtPath: path) else { return false }
        defer { fh.closeFile() }
        let header = fh.readData(ofLength: 12)
        guard header.count >= 4 else { return false }
        let bytes = [UInt8](header)

        // WAV: RIFF....WAVE
        if bytes.count >= 12
            && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            return true
        }
        // AIFF: FORM....AIFF
        if bytes.count >= 12
            && bytes[0] == 0x46 && bytes[1] == 0x4F && bytes[2] == 0x52 && bytes[3] == 0x4D
            && bytes[8] == 0x41 && bytes[9] == 0x49 && bytes[10] == 0x46 && bytes[11] == 0x46 {
            return true
        }
        // OGG: OggS
        if bytes[0] == 0x4F && bytes[1] == 0x67 && bytes[2] == 0x67 && bytes[3] == 0x53 {
            return true
        }
        // MP3: ID3 tag
        if bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 {
            return true
        }
        // MP3: frame sync (FF FB, FF F3, FF F2)
        if bytes.count >= 2 && bytes[0] == 0xFF
            && (bytes[1] == 0xFB || bytes[1] == 0xF3 || bytes[1] == 0xF2) {
            return true
        }
        // AAC ADTS: FF F1 or FF F9
        if bytes.count >= 2 && bytes[0] == 0xFF
            && (bytes[1] == 0xF1 || bytes[1] == 0xF9) {
            return true
        }
        // M4A/AAC in MP4 container: "ftyp" at offset 4
        if bytes.count >= 8
            && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return true
        }

        return false
    }

    // MARK: - ZIP Preflight

    /// Runs zipinfo to check for dangerous content before extraction.
    /// Returns an error description, or nil if safe.
    static func preflightZip(at path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        proc.arguments = ["-1", path]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return "Failed to run zipinfo: \(error.localizedDescription)"
        }

        guard proc.terminationStatus == 0 else {
            return "zipinfo failed with status \(proc.terminationStatus)"
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            return "Unable to read zipinfo output"
        }

        let entries = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        for entry in entries {
            // Path traversal
            if entry.contains("../") {
                return "Path traversal detected: \(entry)"
            }
            // Absolute paths
            if entry.hasPrefix("/") {
                return "Absolute path detected: \(entry)"
            }
            // Nesting depth
            let components = entry.components(separatedBy: "/").filter { !$0.isEmpty }
            if components.count > maxNestingDepth {
                return "Nesting too deep (\(components.count) levels): \(entry)"
            }
        }

        // Check for symlinks via full zipinfo output
        let detailProc = Process()
        detailProc.executableURL = URL(fileURLWithPath: "/usr/bin/zipinfo")
        detailProc.arguments = [path]
        let detailPipe = Pipe()
        detailProc.standardOutput = detailPipe
        detailProc.standardError = FileHandle.nullDevice

        do {
            try detailProc.run()
            detailProc.waitUntilExit()
        } catch {
            return "Failed to run zipinfo detail check"
        }

        let detailData = detailPipe.fileHandleForReading.readDataToEndOfFile()
        if let detailOutput = String(data: detailData, encoding: .utf8) {
            let lines = detailOutput.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("l") {
                    return "Symlink detected in ZIP: \(line)"
                }
            }
        }

        return nil
    }

    // MARK: - Post-Extract Sanitization

    /// Walks an extracted pack directory and removes anything unsafe.
    /// Returns the number of files removed.
    @discardableResult
    static func sanitizeExtractedPack(at packDir: String) -> Int {
        let fm = FileManager.default
        var removedCount = 0
        let validEvents = Set(ClaudeEvent.allCases.map { $0.rawValue })

        guard let enumerator = fm.enumerator(atPath: packDir) else { return 0 }

        var toRemove: [String] = []

        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (packDir as NSString).appendingPathComponent(relativePath)
            let components = relativePath.components(separatedBy: "/").filter { !$0.isEmpty }

            // Check if symlink
            var isSymlink = false
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let type = attrs[.type] as? FileAttributeType,
               type == .typeSymbolicLink {
                isSymlink = true
            }

            if isSymlink {
                toRemove.append(fullPath)
                continue
            }

            // Must be at <event>/<file> depth (exactly 2 components for files)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)

            if isDir.boolValue {
                // Directories at depth 1 must be valid event names
                if components.count == 1 && !validEvents.contains(components[0]) {
                    toRemove.append(fullPath)
                    enumerator.skipDescendants()
                }
                continue
            }

            // Files must be at depth 2: <event>/<filename>
            if components.count != 2 {
                toRemove.append(fullPath)
                continue
            }

            // Event directory must be valid
            if !validEvents.contains(components[0]) {
                toRemove.append(fullPath)
                continue
            }

            // Check extension
            let ext = (fullPath as NSString).pathExtension.lowercased()
            if !allowedExtensions.contains(ext) {
                toRemove.append(fullPath)
                continue
            }

            // Check file size
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? UInt64, size > maxFileSize {
                toRemove.append(fullPath)
                continue
            }

            // Check magic bytes
            if !isValidAudioFile(at: fullPath) {
                toRemove.append(fullPath)
                continue
            }
        }

        // Remove in reverse order so nested items are removed before parents
        for path in toRemove.reversed() {
            try? fm.removeItem(atPath: path)
            removedCount += 1
        }

        // Clean up empty directories
        if let cleanup = fm.enumerator(atPath: packDir) {
            var emptyDirs: [String] = []
            while let rel = cleanup.nextObject() as? String {
                let full = (packDir as NSString).appendingPathComponent(rel)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    if let contents = try? fm.contentsOfDirectory(atPath: full), contents.isEmpty {
                        emptyDirs.append(full)
                    }
                }
            }
            for dir in emptyDirs.reversed() {
                try? fm.removeItem(atPath: dir)
            }
        }

        return removedCount
    }

    // MARK: - Single File Validation (for drag-drop / add)

    /// Validates a single file for import: extension, size, not symlink, magic bytes.
    static func validateSingleFile(at url: URL) -> Bool {
        let path = url.path
        let fm = FileManager.default

        // Check extension
        let ext = url.pathExtension.lowercased()
        guard allowedExtensions.contains(ext) else { return false }

        // Check not symlink
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let type = attrs[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            return false
        }

        // Check file size
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let size = attrs[.size] as? UInt64, size > maxFileSize {
            return false
        }

        // Check magic bytes
        return isValidAudioFile(at: path)
    }
}
