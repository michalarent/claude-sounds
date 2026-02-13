import Cocoa

// MARK: - Sound Pack Manager

class SoundPackManager {
    static let shared = SoundPackManager()

    let soundsDir: String
    let activePackFile: String
    let customManifestsFile: String
    let manifestUrl = "https://raw.githubusercontent.com/michalarent/claude-sounds/main/sound-packs.json"
    let communityManifestUrl = "https://raw.githubusercontent.com/michalarent/claude-sounds/community-packs/community/manifest.json"

    private init() {
        soundsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds")
        activePackFile = (soundsDir as NSString).appendingPathComponent(".active-pack")
        customManifestsFile = (soundsDir as NSString).appendingPathComponent(".custom-manifests.json")
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

    // MARK: - Install from URL

    func installFromURL(_ urlString: String, progress: @escaping (Double) -> Void, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { completion(false) }
            return
        }

        let delegate = DownloadDelegate(progress: progress) { [weak self] tempUrl in
            guard let self = self, let tempUrl = tempUrl else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.extractZip(at: tempUrl, completion: completion)
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        session.downloadTask(with: url).resume()
    }

    // MARK: - Install from local ZIP

    func installFromZip(at fileURL: URL, completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-o", fileURL.path, "-d", self.soundsDir]
            proc.standardOutput = FileHandle.nullDevice
            proc.standardError = FileHandle.nullDevice
            do {
                try proc.run()
                proc.waitUntilExit()
                DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private func extractZip(at tempUrl: URL, completion: @escaping (Bool) -> Void) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-o", tempUrl.path, "-d", self.soundsDir]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            proc.waitUntilExit()
            try? FileManager.default.removeItem(at: tempUrl)
            DispatchQueue.main.async { completion(proc.terminationStatus == 0) }
        } catch {
            DispatchQueue.main.async { completion(false) }
        }
    }

    // MARK: - Custom Manifest Registry

    func customManifestURLs() -> [String] {
        guard let data = FileManager.default.contents(atPath: customManifestsFile),
              let urls = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return urls
    }

    private func saveCustomManifestURLs(_ urls: [String]) {
        guard let data = try? JSONEncoder().encode(urls) else { return }
        try? data.write(to: URL(fileURLWithPath: customManifestsFile))
    }

    func addCustomManifestURL(_ url: String) {
        var urls = customManifestURLs()
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !urls.contains(trimmed) else { return }
        urls.append(trimmed)
        saveCustomManifestURLs(urls)
    }

    func removeCustomManifestURL(_ url: String) {
        var urls = customManifestURLs()
        urls.removeAll { $0 == url }
        saveCustomManifestURLs(urls)
    }

    func fetchManifestMerged(completion: @escaping (SoundPackManifest?) -> Void) {
        fetchManifest { [weak self] primary in
            guard let self = self else {
                completion(primary)
                return
            }

            // Always include community manifest + any user-added registries
            var allURLs = [self.communityManifestUrl]
            allURLs.append(contentsOf: self.customManifestURLs())

            var allPacks = primary?.packs ?? []
            let group = DispatchGroup()

            for urlStr in allURLs {
                guard let url = URL(string: urlStr) else { continue }
                group.enter()
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    if let data = data,
                       let manifest = try? JSONDecoder().decode(SoundPackManifest.self, from: data) {
                        DispatchQueue.main.async {
                            // Later manifests take precedence — remove dupes from earlier
                            let newIds = Set(manifest.packs.map { $0.id })
                            allPacks.removeAll { newIds.contains($0.id) }
                            allPacks.append(contentsOf: manifest.packs)
                        }
                    }
                    group.leave()
                }.resume()
            }

            group.notify(queue: .main) {
                let merged = SoundPackManifest(version: primary?.version ?? "1", packs: allPacks)
                completion(merged)
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
