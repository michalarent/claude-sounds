import Cocoa

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
        actionsCol.width = 120
        actionsCol.minWidth = 100
        actionsCol.maxWidth = 150
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
            let files = SoundPackManager.shared.allSoundFiles(forEvent: event, inPack: currentPackId)
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

        let audioUrls = urls.filter { AudioValidator.validateSingleFile(at: $0) }
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
                let cell = NSTextField(labelWithString: fi.isSkipped ? "\(fi.filename) (skipped)" : fi.filename)
                cell.font = .systemFont(ofSize: 12)
                cell.textColor = fi.isSkipped ? .tertiaryLabelColor : .labelColor
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
            } else if let fi = item as? SoundFileItem {
                let playBtn = NSButton(image: NSImage(systemSymbolName: "play.fill",
                    accessibilityDescription: "Play")!, target: self,
                    action: #selector(playFile(_:)))
                playBtn.bezelStyle = .inline
                playBtn.isBordered = false

                let skipIcon = fi.isSkipped ? "forward.fill" : "forward.end.fill"
                let skipLabel = fi.isSkipped ? "Unskip" : "Skip"
                let skipBtn = NSButton(image: NSImage(systemSymbolName: skipIcon,
                    accessibilityDescription: skipLabel)!, target: self,
                    action: #selector(toggleSkip(_:)))
                skipBtn.bezelStyle = .inline
                skipBtn.isBordered = false
                skipBtn.contentTintColor = fi.isSkipped ? .systemGreen : .systemOrange

                let delBtn = NSButton(image: NSImage(systemSymbolName: "trash",
                    accessibilityDescription: "Delete")!, target: self,
                    action: #selector(deleteFile(_:)))
                delBtn.bezelStyle = .inline
                delBtn.isBordered = false
                delBtn.contentTintColor = .systemRed

                container.addArrangedSubview(playBtn)
                container.addArrangedSubview(skipBtn)
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

        for url in panel.urls where AudioValidator.validateSingleFile(at: url) {
            let dest = (destDir as NSString).appendingPathComponent(url.lastPathComponent)
            if !fm.fileExists(atPath: dest) {
                try? fm.copyItem(at: url, to: URL(fileURLWithPath: dest))
            }
        }

        reloadSoundData()
    }

    @objc func toggleSkip(_ sender: NSButton) {
        guard let fi = itemForSender(sender) as? SoundFileItem else { return }
        let fm = FileManager.default
        let newPath: String
        if fi.isSkipped {
            // Unskip: remove .disabled suffix
            newPath = String(fi.path.dropLast(".disabled".count))
        } else {
            newPath = fi.path + ".disabled"
        }
        try? fm.moveItem(atPath: fi.path, toPath: newPath)
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
