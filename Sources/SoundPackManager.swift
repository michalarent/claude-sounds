import Cocoa

// MARK: - Sound Pack Manager

class SoundPackManager {
    static let shared = SoundPackManager()

    let soundsDir: String
    let activePackFile: String
    let manifestUrl = "https://raw.githubusercontent.com/michalarent/claude-sounds/main/sound-packs.json"

    private init() {
        soundsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds")
        activePackFile = (soundsDir as NSString).appendingPathComponent(".active-pack")
        // Ensure sounds directory exists
        try? FileManager.default.createDirectory(atPath: soundsDir, withIntermediateDirectories: true)
    }

    func installedPackIds() -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: soundsDir) else { return [] }
        return contents.filter { item in
            guard !item.hasPrefix(".") else { return false }
            var isDir: ObjCBool = false
            let path = (soundsDir as NSString).appendingPathComponent(item)
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }.sorted()
    }

    func soundFiles(forEvent event: ClaudeEvent, inPack packId: String) -> [String] {
        return allSoundFiles(forEvent: event, inPack: packId).filter { !$0.hasSuffix(".disabled") }
    }

    func allSoundFiles(forEvent event: ClaudeEvent, inPack packId: String) -> [String] {
        let dir = (soundsDir as NSString).appendingPathComponent("\(packId)/\(event.rawValue)")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let exts = Set(["wav", "mp3", "aiff", "m4a", "ogg", "aac"])
        return files.filter { f in
            let ext = (f as NSString).pathExtension.lowercased()
            if ext == "disabled" {
                let inner = ((f as NSString).deletingPathExtension as NSString).pathExtension.lowercased()
                return exts.contains(inner)
            }
            return exts.contains(ext)
        }.map { (dir as NSString).appendingPathComponent($0) }.sorted()
    }

    func activePackId() -> String? {
        guard let str = try? String(contentsOfFile: activePackFile, encoding: .utf8) else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func setActivePack(_ id: String) {
        try? id.write(toFile: activePackFile, atomically: true, encoding: .utf8)
    }

    func fetchManifest(completion: @escaping (SoundPackManifest?) -> Void) {
        guard let url = URL(string: manifestUrl) else {
            DispatchQueue.main.async { completion(self.embeddedManifest()) }
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data, let manifest = try? JSONDecoder().decode(SoundPackManifest.self, from: data) {
                DispatchQueue.main.async { completion(manifest) }
            } else {
                DispatchQueue.main.async { completion(self.embeddedManifest()) }
            }
        }.resume()
    }

    private func embeddedManifest() -> SoundPackManifest {
        return SoundPackManifest(version: "1", packs: [
            SoundPackInfo(
                id: "protoss",
                name: "StarCraft Protoss",
                description: "Protoss voice lines from StarCraft",
                version: "1.0",
                author: "Blizzard Entertainment",
                downloadUrl: "https://github.com/michalarent/claude-sounds/releases/download/v2.0/protoss.zip",
                size: "2.1 MB",
                fileCount: 42,
                previewUrl: nil
            )
        ])
    }

    func downloadAndInstall(pack: SoundPackInfo, progress: @escaping (Double) -> Void, completion: @escaping (Bool) -> Void) {
        guard let urlStr = pack.downloadUrl, let url = URL(string: urlStr) else {
            completion(false)
            return
        }

        let delegate = DownloadDelegate(progress: progress) { [weak self] tempUrl in
            guard let self = self, let tempUrl = tempUrl else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let fm = FileManager.default

            // Extract to soundsDir — zip already contains the pack-id prefix directory
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-o", tempUrl.path, "-d", self.soundsDir]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice

            do {
                try proc.run()
                proc.waitUntilExit()
                try? fm.removeItem(at: tempUrl)
                DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: url).resume()
    }

    func createPack(id: String) -> Bool {
        let fm = FileManager.default
        let packDir = (soundsDir as NSString).appendingPathComponent(id)
        do {
            for event in ClaudeEvent.allCases {
                let eventDir = (packDir as NSString).appendingPathComponent(event.rawValue)
                try fm.createDirectory(atPath: eventDir, withIntermediateDirectories: true)
            }
            return true
        } catch {
            return false
        }
    }

    func uninstallPack(id: String) {
        let path = (soundsDir as NSString).appendingPathComponent(id)
        try? FileManager.default.removeItem(atPath: path)
        if activePackId() == id {
            try? FileManager.default.removeItem(atPath: activePackFile)
        }
    }

    /// Ensures an active pack is set; auto-selects first installed pack if needed
    func ensureActivePack() {
        if activePackId() == nil {
            let installed = installedPackIds()
            if installed.contains("protoss") {
                setActivePack("protoss")
            } else if let first = installed.first {
                setActivePack(first)
            }
        }
    }
}

// MARK: - Download Delegate

class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    let progressHandler: (Double) -> Void
    let completionHandler: (URL?) -> Void

    init(progress: @escaping (Double) -> Void, completion: @escaping (URL?) -> Void) {
        self.progressHandler = progress
        self.completionHandler = completion
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".zip")
        try? FileManager.default.copyItem(at: location, to: tmp)
        completionHandler(tmp)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { self.progressHandler(pct) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if error != nil {
            DispatchQueue.main.async { self.completionHandler(nil) }
        }
    }
}
