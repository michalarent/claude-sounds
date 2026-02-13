import Cocoa

// MARK: - Data Models

enum ClaudeEvent: String, CaseIterable {
    case sessionStart = "session-start"
    case promptSubmit = "prompt-submit"
    case notification = "notification"
    case stop = "stop"
    case sessionEnd = "session-end"
    case subagentStop = "subagent-stop"
    case toolFailure = "tool-failure"

    var displayName: String {
        switch self {
        case .sessionStart: return "Session Start"
        case .promptSubmit: return "Prompt Submit"
        case .notification: return "Notification"
        case .stop: return "Stop"
        case .sessionEnd: return "Session End"
        case .subagentStop: return "Subagent Stop"
        case .toolFailure: return "Tool Failure"
        }
    }

    var hookEventName: String {
        switch self {
        case .sessionStart: return "SessionStart"
        case .promptSubmit: return "UserPromptSubmit"
        case .notification: return "Notification"
        case .stop: return "Stop"
        case .sessionEnd: return "SessionEnd"
        case .subagentStop: return "SubagentStop"
        case .toolFailure: return "PostToolUseFailure"
        }
    }
}

struct SoundPackInfo: Codable {
    let id: String
    let name: String
    let description: String
    let version: String
    let author: String
    let downloadUrl: String?
    let size: String
    let fileCount: Int
    let previewUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, version, author, size
        case downloadUrl = "download_url"
        case fileCount = "file_count"
        case previewUrl = "preview_url"
    }
}

struct SoundPackManifest: Codable {
    let version: String
    let packs: [SoundPackInfo]
}

// MARK: - Outline View Models

class EventItem {
    let event: ClaudeEvent
    var soundFiles: [SoundFileItem] = []

    init(event: ClaudeEvent) {
        self.event = event
    }
}

class SoundFileItem {
    let path: String
    let filename: String
    weak var parent: EventItem?

    init(path: String, parent: EventItem) {
        self.path = path
        self.filename = (path as NSString).lastPathComponent
        self.parent = parent
    }
}

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
        let dir = (soundsDir as NSString).appendingPathComponent("\(packId)/\(event.rawValue)")
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        let exts = Set(["wav", "mp3", "aiff", "m4a", "ogg", "aac"])
        return files.filter { f in
            exts.contains((f as NSString).pathExtension.lowercased())
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

            let packDir = (self.soundsDir as NSString).appendingPathComponent(pack.id)
            let fm = FileManager.default
            try? fm.createDirectory(atPath: packDir, withIntermediateDirectories: true)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            proc.arguments = ["-o", tempUrl.path, "-d", packDir]
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

// MARK: - Hook Installer

class HookInstaller {
    static let shared = HookInstaller()

    let hooksDir: String
    let hookScriptPath: String
    let settingsFile: String

    private init() {
        hooksDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/hooks")
        hookScriptPath = (hooksDir as NSString).appendingPathComponent("claude-sounds.sh")
        settingsFile = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/settings.json")
    }

    static let hookScriptContent = """
#!/bin/bash
# Claude Sounds - Generic hook script
# Reads active pack from ~/.claude/sounds/.active-pack

SOUNDS_DIR="$HOME/.claude/sounds"
ACTIVE_PACK_FILE="$SOUNDS_DIR/.active-pack"
MUTE_FILE="$SOUNDS_DIR/.muted"
VOLUME_FILE="$SOUNDS_DIR/.volume"

# Exit early if muted
[ -f "$MUTE_FILE" ] && exit 0

# Read active pack
[ ! -f "$ACTIVE_PACK_FILE" ] && exit 0
PACK=$(cat "$ACTIVE_PACK_FILE" | tr -d '[:space:]')
[ -z "$PACK" ] && exit 0

# Read volume (default 0.50)
VOLUME="0.50"
[ -f "$VOLUME_FILE" ] && VOLUME=$(cat "$VOLUME_FILE" | tr -d '[:space:]')

INPUT=$(cat)
EVENT=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('hook_event_name',''))" 2>/dev/null)

pick_random() {
  local dir="$1"
  local existing=()
  for f in "$dir"/*.wav "$dir"/*.mp3 "$dir"/*.aiff "$dir"/*.m4a "$dir"/*.ogg; do
    [ -e "$f" ] && existing+=("$f")
  done
  local count=${#existing[@]}
  [ "$count" -eq 0 ] && return
  local idx=$((RANDOM % count))
  echo "${existing[$idx]}"
}

play() {
  local file="$1"
  [ -z "$file" ] && return
  python3 -c "
import subprocess
subprocess.Popen(
  ['/usr/bin/afplay', '-v', '$VOLUME', '$file'],
  start_new_session=True,
  stdin=subprocess.DEVNULL,
  stdout=subprocess.DEVNULL,
  stderr=subprocess.DEVNULL
)
"
}

PACK_DIR="$SOUNDS_DIR/$PACK"

case "$EVENT" in
  SessionStart)
    play "$(pick_random "$PACK_DIR/session-start")"
    ;;
  UserPromptSubmit)
    play "$(pick_random "$PACK_DIR/prompt-submit")"
    ;;
  Notification)
    play "$(pick_random "$PACK_DIR/notification")"
    ;;
  Stop)
    play "$(pick_random "$PACK_DIR/stop")"
    ;;
  SessionEnd)
    play "$(pick_random "$PACK_DIR/session-end")"
    ;;
  SubagentStop)
    play "$(pick_random "$PACK_DIR/subagent-stop")"
    ;;
  PostToolUseFailure)
    play "$(pick_random "$PACK_DIR/tool-failure")"
    ;;
esac

exit 0
"""

    func isHookInstalled() -> Bool {
        FileManager.default.fileExists(atPath: hookScriptPath)
    }

    @discardableResult
    func install() -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)

        // Write hook script
        do {
            try HookInstaller.hookScriptContent.write(toFile: hookScriptPath, atomically: true, encoding: .utf8)
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/chmod")
            proc.arguments = ["+x", hookScriptPath]
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return false
        }

        return mergeHookSettings()
    }

    private func mergeHookSettings() -> Bool {
        let fm = FileManager.default

        // Backup existing settings
        if fm.fileExists(atPath: settingsFile) {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd-HHmmss"
            let backup = settingsFile + ".backup-\(df.string(from: Date()))"
            try? fm.copyItem(atPath: settingsFile, toPath: backup)
        }

        // Read existing
        var settings: [String: Any] = [:]
        if let data = fm.contents(atPath: settingsFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            settings = json
        }

        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let cmd = "\"$HOME/.claude/hooks/claude-sounds.sh\""
        let standardEntry: [String: Any] = [
            "hooks": [["type": "command", "command": cmd, "async": true] as [String: Any]]
        ]
        let notificationEntry: [String: Any] = [
            "matcher": "permission_prompt",
            "hooks": [["type": "command", "command": cmd, "async": true] as [String: Any]]
        ]

        let events: [(String, [String: Any])] = [
            ("SessionStart", standardEntry),
            ("UserPromptSubmit", standardEntry),
            ("Stop", standardEntry),
            ("Notification", notificationEntry),
            ("SubagentStop", standardEntry),
            ("PostToolUseFailure", standardEntry),
            ("SessionEnd", standardEntry),
        ]

        for (eventName, entry) in events {
            var eventHooks = hooks[eventName] as? [[String: Any]] ?? []

            // Remove old pack-specific script references
            eventHooks.removeAll { hookGroup in
                guard let arr = hookGroup["hooks"] as? [[String: Any]] else { return false }
                return arr.contains { h in
                    guard let c = h["command"] as? String else { return false }
                    return c.contains("protoss-sounds.sh") || c.contains("peon-sounds.sh")
                }
            }

            // Skip if claude-sounds.sh already present
            let present = eventHooks.contains { hookGroup in
                guard let arr = hookGroup["hooks"] as? [[String: Any]] else { return false }
                return arr.contains { ($0["command"] as? String)?.contains("claude-sounds.sh") == true }
            }

            if !present {
                eventHooks.append(entry)
            }

            hooks[eventName] = eventHooks
        }

        settings["hooks"] = hooks

        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            return false
        }

        do {
            try data.write(to: URL(fileURLWithPath: settingsFile))
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Window Manager

class WindowManager {
    static let shared = WindowManager()

    private var packBrowserWindow: NSWindow?
    private var eventEditorWindow: NSWindow?
    private var setupWizardWindow: NSWindow?

    private var packBrowserController: PackBrowserController?
    private var eventEditorController: EventEditorController?
    private var wizardController: SetupWizardController?

    func showPackBrowser() {
        if let w = packBrowserWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = PackBrowserController()
        let w = ctrl.window
        packBrowserWindow = w
        packBrowserController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showEventEditor() {
        if let w = eventEditorWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = EventEditorController()
        let w = ctrl.window
        eventEditorWindow = w
        eventEditorController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var newPackWindow: NSWindow?
    private var newPackController: NewPackController?

    func showNewPack(onCreated: (() -> Void)? = nil) {
        if let w = newPackWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = NewPackController(onCreated: onCreated)
        let w = ctrl.window
        newPackWindow = w
        newPackController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showSetupWizard(completion: (() -> Void)? = nil) {
        if let w = setupWizardWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = SetupWizardController(completion: completion)
        let w = ctrl.window
        setupWizardWindow = w
        wizardController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - New Pack Controller

class NewPackController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    private let nameField: NSTextField
    private let idField: NSTextField
    private let descField: NSTextField
    private let authorField: NSTextField
    private let errorLabel: NSTextField
    private var onCreated: (() -> Void)?
    private var updatingId = false

    init(onCreated: (() -> Void)? = nil) {
        self.onCreated = onCreated

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Create New Sound Pack"
        window.center()
        window.isReleasedWhenClosed = false

        nameField = NSTextField()
        idField = NSTextField()
        descField = NSTextField()
        authorField = NSTextField()
        errorLabel = NSTextField(labelWithString: "")

        super.init()

        nameField.delegate = self

        let contentView = window.contentView!
        var yOffset: CGFloat = 240

        func addRow(label: String, field: NSTextField) {
            let lbl = NSTextField(labelWithString: label)
            lbl.font = .systemFont(ofSize: 12, weight: .medium)
            lbl.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(lbl)

            field.translatesAutoresizingMaskIntoConstraints = false
            field.font = .systemFont(ofSize: 12)
            contentView.addSubview(field)

            NSLayoutConstraint.activate([
                lbl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
                lbl.topAnchor.constraint(equalTo: contentView.topAnchor, constant: CGFloat(280) - yOffset),
                lbl.widthAnchor.constraint(equalToConstant: 90),
                field.leadingAnchor.constraint(equalTo: lbl.trailingAnchor, constant: 8),
                field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
                field.centerYAnchor.constraint(equalTo: lbl.centerYAnchor),
            ])
            yOffset -= 36
        }

        addRow(label: "Pack Name:", field: nameField)
        addRow(label: "Pack ID:", field: idField)
        addRow(label: "Description:", field: descField)
        addRow(label: "Author:", field: authorField)

        nameField.placeholderString = "My Custom Pack"
        idField.placeholderString = "my-custom-pack"
        descField.placeholderString = "(optional)"
        authorField.placeholderString = "(optional)"

        // Error label
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 11)
        contentView.addSubview(errorLabel)

        // Buttons
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .regular
        contentView.addSubview(cancelBtn)

        let createBtn = NSButton(title: "Create", target: self, action: #selector(create))
        createBtn.translatesAutoresizingMaskIntoConstraints = false
        createBtn.bezelStyle = .rounded
        createBtn.controlSize = .regular
        createBtn.keyEquivalent = "\r"
        contentView.addSubview(createBtn)

        NSLayoutConstraint.activate([
            errorLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            errorLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            errorLabel.bottomAnchor.constraint(equalTo: createBtn.topAnchor, constant: -8),
            createBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            createBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: createBtn.leadingAnchor, constant: -8),
            cancelBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === nameField else { return }
        idField.stringValue = slugify(nameField.stringValue)
    }

    private func slugify(_ name: String) -> String {
        let lowered = name.lowercased()
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        var slug = ""
        for ch in lowered.unicodeScalars {
            if allowed.contains(ch) {
                slug.append(String(ch))
            } else if ch == " " || ch == "_" {
                if !slug.hasSuffix("-") { slug.append("-") }
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    @objc private func cancel() {
        window.close()
    }

    @objc private func create() {
        let packId = idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if packId.isEmpty {
            errorLabel.stringValue = "Pack ID cannot be empty."
            return
        }
        if SoundPackManager.shared.installedPackIds().contains(packId) {
            errorLabel.stringValue = "A pack with ID \"\(packId)\" already exists."
            return
        }
        guard SoundPackManager.shared.createPack(id: packId) else {
            errorLabel.stringValue = "Failed to create pack directory."
            return
        }
        SoundPackManager.shared.setActivePack(packId)
        window.close()
        onCreated?()
        WindowManager.shared.showEventEditor()
    }
}

// MARK: - Sound Pack Browser

class PackBrowserController: NSObject {
    let window: NSWindow
    private let scrollView: NSScrollView
    private let stackView: NSStackView
    private var installedPacks: [String] = []
    private var manifestPacks: [SoundPackInfo] = []
    private var downloadProgress: [String: NSProgressIndicator] = [:]
    private var downloadButtons: [String: NSButton] = [:]
    private var previewProcess: Process?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 450),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Sound Packs"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 350)

        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 0
        stackView.translatesAutoresizingMaskIntoConstraints = false

        super.init()

        let contentView = window.contentView!
        contentView.addSubview(scrollView)

        // Toolbar buttons
        let refreshBtn = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.bezelStyle = .rounded
        refreshBtn.controlSize = .small
        contentView.addSubview(refreshBtn)

        let newPackBtn = NSButton(title: "New Pack...", target: self, action: #selector(newPack))
        newPackBtn.translatesAutoresizingMaskIntoConstraints = false
        newPackBtn.bezelStyle = .rounded
        newPackBtn.controlSize = .small
        contentView.addSubview(newPackBtn)

        NSLayoutConstraint.activate([
            refreshBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            refreshBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            newPackBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            newPackBtn.trailingAnchor.constraint(equalTo: refreshBtn.leadingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: refreshBtn.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        scrollView.documentView = stackView
        // Pin stack view width to scroll view
        let clipView = scrollView.contentView
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: clipView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])

        refresh()
    }

    @objc func newPack() {
        WindowManager.shared.showNewPack { [weak self] in
            self?.refresh()
        }
    }

    @objc func refresh() {
        installedPacks = SoundPackManager.shared.installedPackIds()
        SoundPackManager.shared.fetchManifest { [weak self] manifest in
            self?.manifestPacks = manifest?.packs ?? []
            self?.rebuildUI()
        }
        rebuildUI()
    }

    private func rebuildUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        downloadProgress.removeAll()
        downloadButtons.removeAll()

        let activePack = SoundPackManager.shared.activePackId()

        // Installed section
        addSectionHeader("Installed")
        if installedPacks.isEmpty {
            addLabel("  No packs installed", color: .secondaryLabelColor)
        } else {
            for packId in installedPacks {
                let info = manifestPacks.first { $0.id == packId }
                addPackRow(
                    id: packId,
                    name: info?.name ?? packId.capitalized,
                    description: info?.description ?? "Locally installed",
                    version: info?.version ?? "—",
                    isInstalled: true,
                    isActive: packId == activePack
                )
            }
        }

        // Available section
        let available = manifestPacks.filter { !installedPacks.contains($0.id) }
        if !available.isEmpty {
            addSectionHeader("Available")
            for pack in available {
                addPackRow(
                    id: pack.id,
                    name: pack.name,
                    description: pack.description,
                    version: pack.version,
                    isInstalled: false,
                    isActive: false,
                    packInfo: pack
                )
            }
        }

        // Spacer
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        stackView.addArrangedSubview(spacer)
    }

    private func addSectionHeader(_ title: String) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: 13)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 30),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            sep.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            sep.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        stackView.addArrangedSubview(container)
        container.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func addLabel(_ text: String, color: NSColor = .labelColor) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(label)
        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 14),
            label.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])
        stackView.addArrangedSubview(wrapper)
        wrapper.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func addPackRow(id: String, name: String, description: String,
                            version: String, isInstalled: Bool, isActive: Bool,
                            packInfo: SoundPackInfo? = nil) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(nameLabel)

        let descLabel = NSTextField(labelWithString: description)
        descLabel.font = .systemFont(ofSize: 11)
        descLabel.textColor = .secondaryLabelColor
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(descLabel)

        let versionLabel = NSTextField(labelWithString: "v\(version)")
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = .tertiaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(versionLabel)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 72),
            nameLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            nameLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
            descLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            descLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -180),
            versionLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            versionLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
        ])

        // Buttons
        if isInstalled {
            if isActive {
                let badge = NSTextField(labelWithString: "Active")
                badge.font = .systemFont(ofSize: 11, weight: .medium)
                badge.textColor = .systemGreen
                badge.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(badge)
                NSLayoutConstraint.activate([
                    badge.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                    badge.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                ])
            } else {
                let activateBtn = createButton("Activate", id: id, action: #selector(activatePack(_:)))
                activateBtn.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(activateBtn)
                NSLayoutConstraint.activate([
                    activateBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                    activateBtn.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
                ])
            }

            let uninstallBtn = createButton("Uninstall", id: id, action: #selector(uninstallPack(_:)))
            uninstallBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(uninstallBtn)
            NSLayoutConstraint.activate([
                uninstallBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                uninstallBtn.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
            ])
        } else {
            let dlBtn = createButton("Download & Install", id: id, action: #selector(downloadPack(_:)))
            dlBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(dlBtn)
            downloadButtons[id] = dlBtn

            let progress = NSProgressIndicator()
            progress.style = .bar
            progress.isIndeterminate = false
            progress.minValue = 0
            progress.maxValue = 1
            progress.doubleValue = 0
            progress.isHidden = true
            progress.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(progress)
            downloadProgress[id] = progress

            NSLayoutConstraint.activate([
                dlBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                dlBtn.topAnchor.constraint(equalTo: row.topAnchor, constant: 12),
                progress.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                progress.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -12),
                progress.widthAnchor.constraint(equalToConstant: 140),
            ])
        }

        // Bottom separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(sep)
        NSLayoutConstraint.activate([
            sep.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            sep.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            sep.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])

        stackView.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }

    private func createButton(_ title: String, id: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        btn.controlSize = .small
        btn.identifier = NSUserInterfaceItemIdentifier(id)
        return btn
    }

    @objc func activatePack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        SoundPackManager.shared.setActivePack(id)
        rebuildUI()
    }

    @objc func uninstallPack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        let alert = NSAlert()
        alert.messageText = "Uninstall \(id)?"
        alert.informativeText = "This will delete all sound files for this pack."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            SoundPackManager.shared.uninstallPack(id: id)
            installedPacks = SoundPackManager.shared.installedPackIds()
            rebuildUI()
        }
    }

    @objc func downloadPack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let pack = manifestPacks.first(where: { $0.id == id }) else { return }

        sender.isEnabled = false
        sender.title = "Downloading..."
        downloadProgress[id]?.isHidden = false

        SoundPackManager.shared.downloadAndInstall(pack: pack, progress: { [weak self] pct in
            self?.downloadProgress[id]?.doubleValue = pct
        }, completion: { [weak self] success in
            if success {
                self?.installedPacks = SoundPackManager.shared.installedPackIds()
                self?.rebuildUI()
            } else {
                sender.isEnabled = true
                sender.title = "Download & Install"
                self?.downloadProgress[id]?.isHidden = true
                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = "Could not download or extract the sound pack."
                alert.runModal()
            }
        })
    }
}

// MARK: - Per-Event Sound Editor

class EventEditorController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let window: NSWindow
    private var outlineView: NSOutlineView!
    private var packPopup: NSPopUpButton!
    private var eventItems: [EventItem] = []
    private var currentPackId: String = ""
    private var previewProcess: Process?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Sound Editor"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 550, height: 400)

        super.init()

        let contentView = window.contentView!

        // Pack selector
        let packLabel = NSTextField(labelWithString: "Pack:")
        packLabel.font = .systemFont(ofSize: 12)
        packLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(packLabel)

        packPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        packPopup.translatesAutoresizingMaskIntoConstraints = false
        packPopup.target = self
        packPopup.action = #selector(packChanged(_:))
        contentView.addSubview(packPopup)

        // Outline view
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.rowHeight = 28
        outlineView.indentationPerLevel = 20

        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameCol.title = "Sound"
        nameCol.minWidth = 200
        outlineView.addTableColumn(nameCol)

        let actionsCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("actions"))
        actionsCol.title = ""
        actionsCol.width = 100
        actionsCol.minWidth = 80
        actionsCol.maxWidth = 120
        outlineView.addTableColumn(actionsCol)

        outlineView.outlineTableColumn = nameCol
        outlineView.dataSource = self
        outlineView.delegate = self

        // Register for drag-and-drop
        outlineView.registerForDraggedTypes([.fileURL])

        scrollView.documentView = outlineView

        // Drop hint label
        let hint = NSTextField(labelWithString: "Drop audio files onto events to add them")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(hint)

        NSLayoutConstraint.activate([
            packLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            packLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            packPopup.leadingAnchor.constraint(equalTo: packLabel.trailingAnchor, constant: 6),
            packPopup.centerYAnchor.constraint(equalTo: packLabel.centerYAnchor),
            packPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            scrollView.topAnchor.constraint(equalTo: packLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -4),
            hint.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            hint.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            hint.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            hint.heightAnchor.constraint(equalToConstant: 20),
        ])

        reloadPacks()
    }

    private func reloadPacks() {
        let installed = SoundPackManager.shared.installedPackIds()
        packPopup.removeAllItems()
        packPopup.addItems(withTitles: installed)

        let active = SoundPackManager.shared.activePackId() ?? installed.first ?? ""
        if let idx = installed.firstIndex(of: active) {
            packPopup.selectItem(at: idx)
        }
        currentPackId = active
        reloadSoundData()
    }

    private func reloadSoundData() {
        eventItems = ClaudeEvent.allCases.map { event in
            let item = EventItem(event: event)
            let files = SoundPackManager.shared.soundFiles(forEvent: event, inPack: currentPackId)
            item.soundFiles = files.map { SoundFileItem(path: $0, parent: item) }
            return item
        }
        outlineView.reloadData()
        // Expand all
        for item in eventItems {
            outlineView.expandItem(item)
        }
    }

    @objc func packChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else { return }
        currentPackId = title
        reloadSoundData()
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return eventItems.count }
        if let ei = item as? EventItem { return ei.soundFiles.count }
        return 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return eventItems[index] }
        if let ei = item as? EventItem { return ei.soundFiles[index] }
        fatalError("Unexpected item")
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is EventItem
    }

    // Drag-and-drop validation
    func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo,
                     proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        // Accept drops on EventItem rows
        if item is EventItem {
            return .copy
        }
        // If dropping on a SoundFileItem, retarget to its parent
        if let fi = item as? SoundFileItem, let parent = fi.parent {
            outlineView.setDropItem(parent, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }
        return []
    }

    // Drag-and-drop accept
    func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo,
                     item: Any?, childIndex index: Int) -> Bool {
        guard let eventItem = item as? EventItem else { return false }
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return false }

        let audioExts = Set(["wav", "mp3", "aiff", "m4a", "ogg", "aac"])
        let audioUrls = urls.filter { audioExts.contains($0.pathExtension.lowercased()) }
        guard !audioUrls.isEmpty else { return false }

        let destDir = (SoundPackManager.shared.soundsDir as NSString)
            .appendingPathComponent("\(currentPackId)/\(eventItem.event.rawValue)")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        for url in audioUrls {
            let dest = (destDir as NSString).appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest) {
                try? fm.copyItem(at: url, to: URL(fileURLWithPath: dest))
            }
        }

        reloadSoundData()
        return true
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?,
                     item: Any) -> NSView? {
        let colId = tableColumn?.identifier.rawValue ?? ""

        if colId == "name" {
            if let ei = item as? EventItem {
                let cell = NSTextField(labelWithString: "\(ei.event.displayName) (\(ei.soundFiles.count) sounds)")
                cell.font = .systemFont(ofSize: 12, weight: .semibold)
                return cell
            }
            if let fi = item as? SoundFileItem {
                let cell = NSTextField(labelWithString: fi.filename)
                cell.font = .systemFont(ofSize: 12)
                return cell
            }
        }

        if colId == "actions" {
            let container = NSStackView()
            container.orientation = .horizontal
            container.spacing = 4

            if item is EventItem {
                let playBtn = NSButton(image: NSImage(systemSymbolName: "play.fill",
                    accessibilityDescription: "Play random")!, target: self,
                    action: #selector(playRandom(_:)))
                playBtn.bezelStyle = .inline
                playBtn.isBordered = false

                let addBtn = NSButton(image: NSImage(systemSymbolName: "plus",
                    accessibilityDescription: "Add sound")!, target: self,
                    action: #selector(addSound(_:)))
                addBtn.bezelStyle = .inline
                addBtn.isBordered = false

                container.addArrangedSubview(playBtn)
                container.addArrangedSubview(addBtn)
            } else if item is SoundFileItem {
                let playBtn = NSButton(image: NSImage(systemSymbolName: "play.fill",
                    accessibilityDescription: "Play")!, target: self,
                    action: #selector(playFile(_:)))
                playBtn.bezelStyle = .inline
                playBtn.isBordered = false

                let delBtn = NSButton(image: NSImage(systemSymbolName: "trash",
                    accessibilityDescription: "Delete")!, target: self,
                    action: #selector(deleteFile(_:)))
                delBtn.bezelStyle = .inline
                delBtn.isBordered = false
                delBtn.contentTintColor = .systemRed

                container.addArrangedSubview(playBtn)
                container.addArrangedSubview(delBtn)
            }

            return container
        }

        return nil
    }

    // MARK: Actions

    private func itemForSender(_ sender: NSView) -> Any? {
        let row = outlineView.row(for: sender)
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row)
    }

    @objc func playRandom(_ sender: NSButton) {
        guard let ei = itemForSender(sender) as? EventItem,
              let file = ei.soundFiles.randomElement() else { return }
        playAudio(file.path)
    }

    @objc func playFile(_ sender: NSButton) {
        guard let fi = itemForSender(sender) as? SoundFileItem else { return }
        playAudio(fi.path)
    }

    @objc func addSound(_ sender: NSButton) {
        guard let ei = itemForSender(sender) as? EventItem else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [
            .init(filenameExtension: "wav")!,
            .init(filenameExtension: "mp3")!,
            .init(filenameExtension: "aiff")!,
            .init(filenameExtension: "m4a")!,
        ]

        guard panel.runModal() == .OK else { return }

        let destDir = (SoundPackManager.shared.soundsDir as NSString)
            .appendingPathComponent("\(currentPackId)/\(ei.event.rawValue)")
        let fm = FileManager.default
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)

        for url in panel.urls {
            let dest = (destDir as NSString).appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest) {
                try? fm.copyItem(at: url, to: URL(fileURLWithPath: dest))
            }
        }

        reloadSoundData()
    }

    @objc func deleteFile(_ sender: NSButton) {
        guard let fi = itemForSender(sender) as? SoundFileItem else { return }

        let alert = NSAlert()
        alert.messageText = "Delete \(fi.filename)?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? FileManager.default.removeItem(atPath: fi.path)
        reloadSoundData()
    }

    private func playAudio(_ path: String) {
        if let proc = previewProcess, proc.isRunning { proc.terminate() }

        let vol = (try? String(contentsOfFile:
            (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds/.volume"),
            encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.50"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        proc.arguments = ["-v", vol, path]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        previewProcess = proc
    }
}

// MARK: - Setup Wizard

class SetupWizardController: NSObject {
    let window: NSWindow
    private var currentStep = 0
    private let contentContainer: NSView
    private let stepLabel: NSTextField
    private let backBtn: NSButton
    private let nextBtn: NSButton
    private let skipBtn: NSButton
    private var selectedPackId: String?
    private var installedPacks: [String] = []
    private var manifestPacks: [SoundPackInfo] = []
    private var packRadioButtons: [NSButton] = []
    private var statusLabel: NSTextField?
    private var hookInstallDone = false
    private var completionHandler: (() -> Void)?

    init(completion: (() -> Void)? = nil) {
        self.completionHandler = completion

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "Claude Sounds Setup"
        window.center()
        window.isReleasedWhenClosed = false

        let cv = window.contentView!

        stepLabel = NSTextField(labelWithString: "Step 1 of 3")
        stepLabel.font = .systemFont(ofSize: 11)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(stepLabel)

        contentContainer = NSView()
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(contentContainer)

        backBtn = NSButton(title: "Back", target: nil, action: nil)
        backBtn.bezelStyle = .rounded
        backBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(backBtn)

        nextBtn = NSButton(title: "Next", target: nil, action: nil)
        nextBtn.bezelStyle = .rounded
        nextBtn.keyEquivalent = "\r"
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(nextBtn)

        skipBtn = NSButton(title: "Skip Setup", target: nil, action: nil)
        skipBtn.bezelStyle = .rounded
        skipBtn.translatesAutoresizingMaskIntoConstraints = false
        cv.addSubview(skipBtn)

        NSLayoutConstraint.activate([
            stepLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: 14),
            stepLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            contentContainer.topAnchor.constraint(equalTo: stepLabel.bottomAnchor, constant: 8),
            contentContainer.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 20),
            contentContainer.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -20),
            contentContainer.bottomAnchor.constraint(equalTo: backBtn.topAnchor, constant: -16),
            skipBtn.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
            skipBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
            nextBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
            nextBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
            backBtn.trailingAnchor.constraint(equalTo: nextBtn.leadingAnchor, constant: -8),
            backBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -14),
        ])

        super.init()

        backBtn.target = self
        backBtn.action = #selector(goBack)
        nextBtn.target = self
        nextBtn.action = #selector(goNext)
        skipBtn.target = self
        skipBtn.action = #selector(skipSetup)

        installedPacks = SoundPackManager.shared.installedPackIds()
        if installedPacks.contains("protoss") {
            selectedPackId = "protoss"
        } else if let first = installedPacks.first {
            selectedPackId = first
        }

        SoundPackManager.shared.fetchManifest { [weak self] manifest in
            self?.manifestPacks = manifest?.packs ?? []
            if self?.currentStep == 0 { self?.showStep(0) }
        }

        showStep(0)
    }

    private func showStep(_ step: Int) {
        currentStep = step
        contentContainer.subviews.forEach { $0.removeFromSuperview() }
        packRadioButtons.removeAll()

        stepLabel.stringValue = "Step \(step + 1) of 3"
        backBtn.isHidden = step == 0
        skipBtn.isHidden = step == 2

        switch step {
        case 0: showPackSelection()
        case 1: showHookInstall()
        case 2: showComplete()
        default: break
        }
    }

    // MARK: Step 1 - Pack Selection

    private func showPackSelection() {
        nextBtn.title = "Next"
        nextBtn.isEnabled = true

        let title = NSTextField(labelWithString: "Welcome to Claude Sounds!")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(title)

        let subtitle = NSTextField(labelWithString: "Choose a sound pack to get started:")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(subtitle)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
        ])

        // Collect all packs (installed + from manifest)
        var allPacks: [(id: String, name: String, desc: String, installed: Bool)] = []
        for packId in installedPacks {
            let info = manifestPacks.first { $0.id == packId }
            allPacks.append((packId, info?.name ?? packId.capitalized,
                             info?.description ?? "Locally installed", true))
        }
        for pack in manifestPacks where !installedPacks.contains(pack.id) {
            allPacks.append((pack.id, pack.name, pack.description, false))
        }

        var lastAnchor = subtitle.bottomAnchor
        for (i, pack) in allPacks.enumerated() {
            let radio = NSButton(radioButtonWithTitle: " \(pack.name)", target: self,
                                 action: #selector(packSelected(_:)))
            radio.tag = i
            radio.font = .systemFont(ofSize: 13)
            radio.state = pack.id == selectedPackId ? .on : .off
            radio.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(radio)
            packRadioButtons.append(radio)

            let desc = NSTextField(labelWithString: pack.desc + (pack.installed ? "" : " (will download)"))
            desc.font = .systemFont(ofSize: 11)
            desc.textColor = .tertiaryLabelColor
            desc.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(desc)

            NSLayoutConstraint.activate([
                radio.topAnchor.constraint(equalTo: lastAnchor, constant: i == 0 ? 20 : 10),
                radio.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor, constant: 10),
                desc.topAnchor.constraint(equalTo: radio.bottomAnchor, constant: 1),
                desc.leadingAnchor.constraint(equalTo: radio.leadingAnchor, constant: 20),
            ])
            lastAnchor = desc.bottomAnchor
        }

        if allPacks.isEmpty {
            let empty = NSTextField(labelWithString: "No packs found. You can add packs later from the menu.")
            empty.font = .systemFont(ofSize: 12)
            empty.textColor = .secondaryLabelColor
            empty.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(empty)
            NSLayoutConstraint.activate([
                empty.topAnchor.constraint(equalTo: lastAnchor, constant: 20),
                empty.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            ])
        }
    }

    @objc func packSelected(_ sender: NSButton) {
        for btn in packRadioButtons { btn.state = .off }
        sender.state = .on

        var allPacks: [(id: String, name: String)] = []
        for packId in installedPacks {
            let info = manifestPacks.first { $0.id == packId }
            allPacks.append((packId, info?.name ?? packId.capitalized))
        }
        for pack in manifestPacks where !installedPacks.contains(pack.id) {
            allPacks.append((pack.id, pack.name))
        }

        if sender.tag < allPacks.count {
            selectedPackId = allPacks[sender.tag].id
        }
    }

    // MARK: Step 2 - Hook Install

    private func showHookInstall() {
        nextBtn.title = "Install"
        nextBtn.isEnabled = !hookInstallDone
        hookInstallDone = false

        let title = NSTextField(labelWithString: "Install Sound Hooks")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(title)

        let desc = NSTextField(wrappingLabelWithString:
            "This will:\n" +
            "  \u{2022} Create claude-sounds.sh hook script\n" +
            "  \u{2022} Add hook entries to Claude settings.json\n" +
            "  \u{2022} Back up your current settings first\n" +
            "  \u{2022} Set \"\(selectedPackId ?? "—")\" as the active pack")
        desc.font = .systemFont(ofSize: 13)
        desc.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(desc)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(status)
        statusLabel = status

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            desc.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            desc.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            desc.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            status.topAnchor.constraint(equalTo: desc.bottomAnchor, constant: 20),
            status.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
        ])
    }

    private func performInstall() {
        // Set active pack
        if let packId = selectedPackId {
            // Download if not installed
            if !installedPacks.contains(packId),
               let pack = manifestPacks.first(where: { $0.id == packId }) {
                statusLabel?.stringValue = "Downloading \(pack.name)..."
                statusLabel?.textColor = .labelColor
                nextBtn.isEnabled = false

                SoundPackManager.shared.downloadAndInstall(pack: pack, progress: { _ in },
                    completion: { [weak self] success in
                        if success {
                            self?.installedPacks = SoundPackManager.shared.installedPackIds()
                            self?.finishInstall()
                        } else {
                            self?.statusLabel?.stringValue = "Download failed. Try again."
                            self?.statusLabel?.textColor = .systemRed
                            self?.nextBtn.isEnabled = true
                        }
                    })
                return
            }
            SoundPackManager.shared.setActivePack(packId)
        }

        finishInstall()
    }

    private func finishInstall() {
        if let packId = selectedPackId {
            SoundPackManager.shared.setActivePack(packId)
        }

        let success = HookInstaller.shared.install()
        if success {
            statusLabel?.stringValue = "Installed successfully!"
            statusLabel?.textColor = .systemGreen
            hookInstallDone = true
            nextBtn.title = "Next"
            nextBtn.isEnabled = true
        } else {
            statusLabel?.stringValue = "Installation failed. Check permissions."
            statusLabel?.textColor = .systemRed
            nextBtn.isEnabled = true
        }
    }

    // MARK: Step 3 - Complete

    private func showComplete() {
        nextBtn.title = "Done"
        nextBtn.isEnabled = true

        let title = NSTextField(labelWithString: "You're all set!")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(title)

        let activePack = SoundPackManager.shared.activePackId() ?? "none"
        let hookStatus = HookInstaller.shared.isHookInstalled() ? "Installed" : "Not installed"

        let info = NSTextField(wrappingLabelWithString:
            "Active pack: \(activePack)\n" +
            "Hooks: \(hookStatus)\n\n" +
            "You can manage sound packs and edit individual sounds from the menu bar icon.")
        info.font = .systemFont(ofSize: 13)
        info.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(info)

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: contentContainer.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            info.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            info.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            info.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
        ])
    }

    // MARK: Navigation

    @objc func goBack() {
        if currentStep > 0 { showStep(currentStep - 1) }
    }

    @objc func goNext() {
        switch currentStep {
        case 0:
            showStep(1)
        case 1:
            if hookInstallDone {
                showStep(2)
            } else {
                performInstall()
            }
        case 2:
            markSetupComplete()
            window.close()
            completionHandler?()
        default:
            break
        }
    }

    @objc func skipSetup() {
        markSetupComplete()
        window.close()
        completionHandler?()
    }

    private func markSetupComplete() {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds/.setup-complete")
        try? "1".write(toFile: path, atomically: true, encoding: .utf8)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    let muteFile = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds/.muted")
    let volumeFile = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds/.volume")
    var currentVolume: Float = 0.5
    var volumeSlider: NSSlider!
    var volumeLabel: NSTextField!
    var muteMenuItem: NSMenuItem!
    var setupHookMenuItem: NSMenuItem!
    var previewProcess: Process?

    override init() {
        super.init()
        if let str = try? String(contentsOfFile: volumeFile, encoding: .utf8),
           let val = Float(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            currentVolume = max(0, min(1, val))
        }
    }

    var isMuted: Bool {
        FileManager.default.fileExists(atPath: muteFile)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        SoundPackManager.shared.ensureActivePack()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        setupMenu()
        checkFirstLaunch()
    }

    private func checkFirstLaunch() {
        let setupFile = (NSHomeDirectory() as NSString)
            .appendingPathComponent(".claude/sounds/.setup-complete")
        if !FileManager.default.fileExists(atPath: setupFile) {
            // Delay slightly to let menu bar settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                WindowManager.shared.showSetupWizard { [weak self] in
                    self?.rebuildMenu()
                }
            }
        }
    }

    // MARK: - Menu

    func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self
        buildMenuItems(menu)
        statusItem.menu = menu
    }

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        menu.removeAllItems()
        buildMenuItems(menu)
    }

    private func buildMenuItems(_ menu: NSMenu) {
        let header = NSMenuItem(title: "Claude Sounds", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        // Volume slider row
        let sliderContainer = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 30))

        let speakerIcon = NSImageView(frame: NSRect(x: 14, y: 6, width: 16, height: 16))
        speakerIcon.image = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "Volume")
        speakerIcon.contentTintColor = .secondaryLabelColor
        sliderContainer.addSubview(speakerIcon)

        volumeSlider = NSSlider(frame: NSRect(x: 36, y: 6, width: 130, height: 18))
        volumeSlider.minValue = 0
        volumeSlider.maxValue = 100
        volumeSlider.integerValue = Int(currentVolume * 100)
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged(_:))
        volumeSlider.isContinuous = true
        sliderContainer.addSubview(volumeSlider)

        volumeLabel = NSTextField(labelWithString: "\(Int(currentVolume * 100))%")
        volumeLabel.frame = NSRect(x: 172, y: 6, width: 44, height: 18)
        volumeLabel.alignment = .right
        volumeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        volumeLabel.textColor = .secondaryLabelColor
        sliderContainer.addSubview(volumeLabel)

        let sliderItem = NSMenuItem()
        sliderItem.view = sliderContainer
        menu.addItem(sliderItem)
        menu.addItem(.separator())

        muteMenuItem = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "m")
        muteMenuItem.target = self
        muteMenuItem.state = isMuted ? .on : .off
        menu.addItem(muteMenuItem)
        menu.addItem(.separator())

        // Sound management items
        let packsItem = NSMenuItem(title: "Sound Packs...", action: #selector(openPackBrowser), keyEquivalent: "")
        packsItem.target = self
        menu.addItem(packsItem)

        let editorItem = NSMenuItem(title: "Edit Sounds...", action: #selector(openEventEditor), keyEquivalent: "")
        editorItem.target = self
        menu.addItem(editorItem)

        if !HookInstaller.shared.isHookInstalled() {
            setupHookMenuItem = NSMenuItem(title: "Setup Hook...", action: #selector(openSetupWizard), keyEquivalent: "")
            setupHookMenuItem.target = self
            menu.addItem(setupHookMenuItem)
        }

        menu.addItem(.separator())

        // Active pack indicator
        if let packId = SoundPackManager.shared.activePackId() {
            let activeItem = NSMenuItem(title: "Pack: \(packId)", action: nil, keyEquivalent: "")
            activeItem.isEnabled = false
            menu.addItem(activeItem)
            menu.addItem(.separator())
        }

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func openPackBrowser() {
        WindowManager.shared.showPackBrowser()
    }

    @objc func openEventEditor() {
        WindowManager.shared.showEventEditor()
    }

    @objc func openSetupWizard() {
        WindowManager.shared.showSetupWizard { [weak self] in
            self?.rebuildMenu()
        }
    }

    @objc func volumeChanged(_ sender: NSSlider) {
        currentVolume = Float(sender.integerValue) / 100.0
        volumeLabel.stringValue = "\(sender.integerValue)%"
        try? String(format: "%.2f", currentVolume)
            .write(toFile: volumeFile, atomically: true, encoding: .utf8)
        updateIcon()

        if let event = NSApp.currentEvent, event.type == .leftMouseUp {
            playPreview()
        }
    }

    // MARK: - Sound Preview

    func playPreview() {
        if let proc = previewProcess, proc.isRunning { proc.terminate() }
        guard currentVolume > 0, let file = pickRandomSound() else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        proc.arguments = ["-v", String(format: "%.2f", currentVolume), file]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        previewProcess = proc
    }

    func pickRandomSound() -> String? {
        guard let packId = SoundPackManager.shared.activePackId() else { return nil }
        let soundsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds/\(packId)")
        let fm = FileManager.default
        guard let subdirs = try? fm.contentsOfDirectory(atPath: soundsDir) else { return nil }

        let exts = Set(["wav", "mp3", "aiff", "m4a", "ogg", "aac"])
        var allFiles: [String] = []
        for sub in subdirs {
            let subPath = (soundsDir as NSString).appendingPathComponent(sub)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue else { continue }
            if let files = try? fm.contentsOfDirectory(atPath: subPath) {
                for f in files where exts.contains((f as NSString).pathExtension.lowercased()) {
                    allFiles.append((subPath as NSString).appendingPathComponent(f))
                }
            }
        }

        guard !allFiles.isEmpty else { return nil }
        return allFiles[Int.random(in: 0..<allFiles.count)]
    }

    @objc func toggleMute() {
        if isMuted {
            try? FileManager.default.removeItem(atPath: muteFile)
        } else {
            FileManager.default.createFile(atPath: muteFile, contents: nil, attributes: nil)
        }
        muteMenuItem.state = isMuted ? .on : .off
        updateIcon()
    }

    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Icon Drawing

    func updateIcon() {
        let muted = isMuted
        let vol = currentVolume
        let waveCount = muted ? 0 : (vol < 0.01 ? 0 : (vol < 0.34 ? 1 : (vol < 0.67 ? 2 : 3)))

        let sparkleSize: CGFloat = 16
        let gap: CGFloat = 2
        let wavesWidth: CGFloat = muted ? 12 : (waveCount > 0 ? CGFloat(waveCount) * 3.0 + 4.0 : 4)
        let totalWidth = sparkleSize + gap + wavesWidth
        let height: CGFloat = 18

        let image = NSImage(size: NSSize(width: totalWidth, height: height), flipped: true) { rect in
            let logoRect = NSRect(x: 2, y: 3, width: 12, height: 12)
            self.drawClaudeLogo(in: logoRect)
            self.drawHeadphones(around: logoRect)

            let waveOriginX: CGFloat = sparkleSize + 2
            let waveOriginY: CGFloat = height / 2

            if muted {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: waveOriginX, y: waveOriginY - 5))
                slash.line(to: NSPoint(x: waveOriginX + 8, y: waveOriginY + 5))
                slash.lineWidth = 1.5
                slash.lineCapStyle = .round
                NSColor.black.setStroke()
                slash.stroke()
            } else {
                for i in 0..<waveCount {
                    let offset = CGFloat(i) * 3.0 + 2.0
                    let waveH = CGFloat(3 + i * 2)
                    let x = waveOriginX + offset
                    let path = NSBezierPath()
                    path.move(to: NSPoint(x: x, y: waveOriginY - waveH))
                    path.curve(
                        to: NSPoint(x: x, y: waveOriginY + waveH),
                        controlPoint1: NSPoint(x: x + waveH * 0.6, y: waveOriginY - waveH * 0.3),
                        controlPoint2: NSPoint(x: x + waveH * 0.6, y: waveOriginY + waveH * 0.3)
                    )
                    path.lineWidth = 1.5
                    path.lineCapStyle = .round
                    NSColor.black.setStroke()
                    path.stroke()
                }
            }
            return true
        }
        image.isTemplate = true
        statusItem.button?.image = image

        let tooltip = muted ? "Claude sounds: Muted" : "Claude sounds: \(Int(vol * 100))%"
        statusItem.button?.toolTip = tooltip
    }

    func drawHeadphones(around rect: NSRect) {
        let cx = rect.midX
        let bandRadius = rect.width / 2 + 1.5
        let bandTop = rect.minY - 1

        let band = NSBezierPath()
        band.move(to: NSPoint(x: cx - bandRadius, y: rect.midY - 1))
        band.curve(
            to: NSPoint(x: cx + bandRadius, y: rect.midY - 1),
            controlPoint1: NSPoint(x: cx - bandRadius, y: bandTop - 2),
            controlPoint2: NSPoint(x: cx + bandRadius, y: bandTop - 2)
        )
        band.lineWidth = 1.0
        band.lineCapStyle = .round
        NSColor.black.setStroke()
        band.stroke()

        let cupW: CGFloat = 3.5
        let cupH: CGFloat = 6.5
        let leftCup = NSBezierPath(roundedRect: NSRect(
            x: cx - bandRadius - cupW / 2 + 0.5,
            y: rect.midY - 1,
            width: cupW, height: cupH
        ), xRadius: 1, yRadius: 1)
        NSColor.black.setFill()
        leftCup.fill()

        let rightCup = NSBezierPath(roundedRect: NSRect(
            x: cx + bandRadius - cupW / 2 - 0.5,
            y: rect.midY - 1,
            width: cupW, height: cupH
        ), xRadius: 1, yRadius: 1)
        rightCup.fill()
    }

    static let claudeSVGPath = "M 233.96 800.21 L 468.64 668.54 L 472.59 657.10 L 468.64 650.74 L 457.21 650.74 L 417.99 648.32 L 283.89 644.70 L 167.60 639.87 L 54.93 633.83 L 26.58 627.79 L 0 592.75 L 2.74 575.28 L 26.58 559.25 L 60.72 562.23 L 136.19 567.38 L 249.42 575.19 L 331.57 580.03 L 453.26 592.67 L 472.59 592.67 L 475.33 584.86 L 468.72 580.03 L 463.57 575.19 L 346.39 495.79 L 219.54 411.87 L 153.10 363.54 L 117.18 339.06 L 99.06 316.11 L 91.25 266.01 L 123.87 230.09 L 167.68 233.07 L 178.87 236.05 L 223.25 270.20 L 318.04 343.57 L 441.83 434.74 L 459.95 449.80 L 467.19 444.64 L 468.08 441.02 L 459.95 427.41 L 392.62 305.72 L 320.78 181.93 L 288.81 130.63 L 280.35 99.87 C 277.37 87.22 275.19 76.59 275.19 63.62 L 312.32 13.21 L 332.86 6.60 L 382.39 13.21 L 403.25 31.33 L 434.01 101.72 L 483.87 212.54 L 561.18 363.22 L 583.81 407.92 L 595.89 449.32 L 600.40 461.96 L 608.21 461.96 L 608.21 454.71 L 614.58 369.83 L 626.34 265.61 L 637.77 131.52 L 641.72 93.75 L 660.40 48.48 L 697.53 24.00 L 726.52 37.85 L 750.36 72 L 747.06 94.07 L 732.89 186.20 L 705.10 330.52 L 686.98 427.17 L 697.53 427.17 L 709.61 415.09 L 758.50 350.17 L 840.64 247.49 L 876.89 206.74 L 919.17 161.72 L 946.31 140.30 L 997.61 140.30 L 1035.38 196.43 L 1018.47 254.42 L 965.64 321.42 L 921.83 378.20 L 859.01 462.77 L 819.79 530.42 L 823.41 535.81 L 832.75 534.93 L 974.66 504.72 L 1051.33 490.87 L 1142.82 475.17 L 1184.21 494.50 L 1188.72 514.15 L 1172.46 554.34 L 1074.60 578.50 L 959.84 601.45 L 788.94 641.88 L 786.85 643.41 L 789.26 646.39 L 866.26 653.64 L 899.19 655.41 L 979.81 655.41 L 1129.93 666.60 L 1169.15 692.54 L 1192.67 724.27 L 1188.72 748.43 L 1128.32 779.19 L 1046.82 759.87 L 856.59 714.60 L 791.36 698.34 L 782.34 698.34 L 782.34 703.73 L 836.70 756.89 L 936.32 846.85 L 1061.07 962.82 L 1067.44 991.49 L 1051.41 1014.12 L 1034.50 1011.70 L 924.89 929.23 L 882.60 892.11 L 786.85 811.49 L 780.48 811.49 L 780.48 819.95 L 802.55 852.24 L 919.09 1027.41 L 925.13 1081.13 L 916.67 1098.60 L 886.47 1109.15 L 853.29 1103.11 L 785.07 1007.36 L 714.68 899.52 L 657.91 802.87 L 650.98 806.82 L 617.48 1167.70 L 601.77 1186.15 L 565.53 1200 L 535.33 1177.05 L 519.30 1139.92 L 535.33 1066.55 L 554.66 970.79 L 570.36 894.68 L 584.54 800.13 L 592.99 768.72 L 592.43 766.63 L 585.50 767.52 L 514.23 865.37 L 405.83 1011.87 L 320.05 1103.68 L 299.52 1111.81 L 263.92 1093.37 L 267.22 1060.43 L 287.11 1031.11 L 405.83 880.11 L 477.42 786.52 L 523.65 732.48 L 523.33 724.67 L 520.59 724.67 L 205.29 929.40 L 149.15 936.64 L 124.99 914.01 L 127.97 876.89 L 139.41 864.81 L 234.20 799.57 Z"

    func drawClaudeLogo(in rect: NSRect) {
        let path = NSBezierPath()
        let svgSize: CGFloat = 1200
        let scale = min(rect.width, rect.height) / svgSize

        let transform = NSAffineTransform()
        transform.translateX(by: rect.origin.x, yBy: rect.origin.y)
        transform.scale(by: scale)

        var tokens: [String] = []
        var current = ""
        for ch in AppDelegate.claudeSVGPath {
            if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }

        var i = 0
        while i < tokens.count {
            let cmd = tokens[i]; i += 1
            switch cmd {
            case "M":
                let x = CGFloat(Double(tokens[i])!); i += 1
                let y = CGFloat(Double(tokens[i])!); i += 1
                path.move(to: NSPoint(x: x, y: y))
            case "L":
                let x = CGFloat(Double(tokens[i])!); i += 1
                let y = CGFloat(Double(tokens[i])!); i += 1
                path.line(to: NSPoint(x: x, y: y))
            case "C":
                let x1 = CGFloat(Double(tokens[i])!); i += 1
                let y1 = CGFloat(Double(tokens[i])!); i += 1
                let x2 = CGFloat(Double(tokens[i])!); i += 1
                let y2 = CGFloat(Double(tokens[i])!); i += 1
                let x = CGFloat(Double(tokens[i])!); i += 1
                let y = CGFloat(Double(tokens[i])!); i += 1
                path.curve(to: NSPoint(x: x, y: y),
                           controlPoint1: NSPoint(x: x1, y: y1),
                           controlPoint2: NSPoint(x: x2, y: y2))
            case "Z":
                path.close()
            default:
                i -= 1
                let x = CGFloat(Double(tokens[i])!); i += 1
                let y = CGFloat(Double(tokens[i])!); i += 1
                path.line(to: NSPoint(x: x, y: y))
            }
        }

        path.transform(using: transform as AffineTransform)
        NSColor.black.setFill()
        path.fill()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        muteMenuItem.state = isMuted ? .on : .off
        if let str = try? String(contentsOfFile: volumeFile, encoding: .utf8),
           let val = Float(str.trimmingCharacters(in: .whitespacesAndNewlines)) {
            currentVolume = max(0, min(1, val))
            volumeSlider.integerValue = Int(currentVolume * 100)
            volumeLabel.stringValue = "\(Int(currentVolume * 100))%"
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
