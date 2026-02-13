import Cocoa

// MARK: - Sound Pack Browser

class PackBrowserController: NSObject {
    let window: NSWindow
    private let scrollView: NSScrollView
    private let stackView: NSStackView
    private var installedPacks: [String] = []
    private var manifestPacks: [SoundPackInfo] = []
    private var downloadProgress: [String: NSProgressIndicator] = [:]
    private var downloadButtons: [String: NSButton] = [:]
    private var updateProgress: [String: NSProgressIndicator] = [:]
    private var updateButtons: [String: NSButton] = [:]
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

        // Version label
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let versionLabel = NSTextField(labelWithString: "Claude Sounds v\(version)")
        versionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(versionLabel)

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

        let installURLBtn = NSButton(title: "Install URL...", target: self, action: #selector(installFromURL))
        installURLBtn.translatesAutoresizingMaskIntoConstraints = false
        installURLBtn.bezelStyle = .rounded
        installURLBtn.controlSize = .small
        contentView.addSubview(installURLBtn)

        let installZIPBtn = NSButton(title: "Install ZIP...", target: self, action: #selector(installFromZip))
        installZIPBtn.translatesAutoresizingMaskIntoConstraints = false
        installZIPBtn.bezelStyle = .rounded
        installZIPBtn.controlSize = .small
        contentView.addSubview(installZIPBtn)

        NSLayoutConstraint.activate([
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            versionLabel.centerYAnchor.constraint(equalTo: refreshBtn.centerYAnchor),
            refreshBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            refreshBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            newPackBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            newPackBtn.trailingAnchor.constraint(equalTo: refreshBtn.leadingAnchor, constant: -8),
            installURLBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            installURLBtn.trailingAnchor.constraint(equalTo: newPackBtn.leadingAnchor, constant: -8),
            installZIPBtn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            installZIPBtn.trailingAnchor.constraint(equalTo: installURLBtn.leadingAnchor, constant: -8),
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
        SoundPackManager.shared.fetchManifestMerged { [weak self] manifest in
            self?.manifestPacks = manifest?.packs ?? []
            self?.rebuildUI()
        }
        rebuildUI()
    }

    private func rebuildUI() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        downloadProgress.removeAll()
        downloadButtons.removeAll()
        updateProgress.removeAll()
        updateButtons.removeAll()

        let activePack = SoundPackManager.shared.activePackId()

        // Installed section
        addSectionHeader("Installed")
        if installedPacks.isEmpty {
            addLabel("  No packs installed", color: .secondaryLabelColor)
        } else {
            for packId in installedPacks {
                let info = manifestPacks.first { $0.id == packId }
                let localMeta = SoundPackManager.shared.loadPackMetadata(id: packId)
                let localVersion = localMeta?["version"]
                let updateAvailable: Bool = {
                    guard let local = localVersion, let manifest = info?.version else { return false }
                    return local != manifest
                }()
                addPackRow(
                    id: packId,
                    name: localMeta?["name"] ?? info?.name ?? packId.capitalized,
                    description: localMeta?["description"].flatMap({ $0.isEmpty ? nil : $0 }) ?? info?.description ?? "Locally installed",
                    version: localVersion ?? info?.version ?? "—",
                    isInstalled: true,
                    isActive: packId == activePack,
                    packInfo: info,
                    updateAvailable: updateAvailable,
                    manifestVersion: info?.version
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

        // Registries section
        let registryURLs = SoundPackManager.shared.customManifestURLs()
        addSectionHeader("Registries")
        if registryURLs.isEmpty {
            addLabel("  No custom registries", color: .secondaryLabelColor)
        } else {
            for urlStr in registryURLs {
                addRegistryRow(urlStr)
            }
        }
        let manageBtn = NSButton(title: "Manage Registries...", target: self, action: #selector(openManageRegistries))
        manageBtn.bezelStyle = .rounded
        manageBtn.controlSize = .small
        manageBtn.translatesAutoresizingMaskIntoConstraints = false
        let btnWrapper = NSView()
        btnWrapper.translatesAutoresizingMaskIntoConstraints = false
        btnWrapper.addSubview(manageBtn)
        NSLayoutConstraint.activate([
            btnWrapper.heightAnchor.constraint(equalToConstant: 36),
            manageBtn.leadingAnchor.constraint(equalTo: btnWrapper.leadingAnchor, constant: 16),
            manageBtn.centerYAnchor.constraint(equalTo: btnWrapper.centerYAnchor),
        ])
        stackView.addArrangedSubview(btnWrapper)
        btnWrapper.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

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
                            packInfo: SoundPackInfo? = nil,
                            updateAvailable: Bool = false,
                            manifestVersion: String? = nil) {
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

        let versionText: String
        let versionColor: NSColor
        if updateAvailable, let newVer = manifestVersion {
            versionText = "v\(version) → v\(newVer)"
            versionColor = .systemOrange
        } else {
            versionText = "v\(version)"
            versionColor = .tertiaryLabelColor
        }
        let versionLabel = NSTextField(labelWithString: versionText)
        versionLabel.font = .systemFont(ofSize: 10)
        versionLabel.textColor = versionColor
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
            // Top-right: Active badge or Activate button, plus Update button if available
            var topRightAnchor = row.trailingAnchor
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
                topRightAnchor = badge.leadingAnchor
            } else {
                let activateBtn = createButton("Activate", id: id, action: #selector(activatePack(_:)))
                activateBtn.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(activateBtn)
                NSLayoutConstraint.activate([
                    activateBtn.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
                    activateBtn.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
                ])
                topRightAnchor = activateBtn.leadingAnchor
            }

            if updateAvailable, packInfo != nil {
                let updBtn = createButton("Update", id: id, action: #selector(updatePack(_:)))
                updBtn.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(updBtn)
                updateButtons[id] = updBtn

                let progress = NSProgressIndicator()
                progress.style = .bar
                progress.isIndeterminate = false
                progress.minValue = 0
                progress.maxValue = 1
                progress.doubleValue = 0
                progress.isHidden = true
                progress.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(progress)
                updateProgress[id] = progress

                NSLayoutConstraint.activate([
                    updBtn.trailingAnchor.constraint(equalTo: topRightAnchor, constant: -8),
                    updBtn.topAnchor.constraint(equalTo: row.topAnchor, constant: 10),
                    progress.trailingAnchor.constraint(equalTo: topRightAnchor, constant: -8),
                    progress.topAnchor.constraint(equalTo: updBtn.bottomAnchor, constant: 4),
                    progress.widthAnchor.constraint(equalToConstant: 100),
                ])
            }

            // Bottom-right buttons: Preview, (Publish if local-only), Uninstall
            var bottomButtons: [NSButton] = []

            let previewBtn = createButton("Preview", id: id, action: #selector(previewPack(_:)))
            previewBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(previewBtn)
            bottomButtons.append(previewBtn)

            let isLocalOnly = !manifestPacks.contains(where: { $0.id == id })

            if isLocalOnly {
                let editBtn = createButton("Edit", id: id, action: #selector(editPack(_:)))
                editBtn.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(editBtn)
                bottomButtons.append(editBtn)
            }

            if isLocalOnly {
                let publishBtn = createButton("Publish", id: id, action: #selector(publishPack(_:)))
                publishBtn.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(publishBtn)
                bottomButtons.append(publishBtn)
            }

            let uninstallBtn = createButton("Uninstall", id: id, action: #selector(uninstallPack(_:)))
            uninstallBtn.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(uninstallBtn)
            bottomButtons.append(uninstallBtn)

            // Layout bottom buttons right-aligned
            var trailingRef = row.trailingAnchor
            for btn in bottomButtons.reversed() {
                NSLayoutConstraint.activate([
                    btn.trailingAnchor.constraint(equalTo: trailingRef, constant: trailingRef === row.trailingAnchor ? -16 : -8),
                    btn.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -10),
                ])
                trailingRef = btn.leadingAnchor
            }
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

    @objc func previewPack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if let proc = previewProcess, proc.isRunning { proc.terminate() }

        let allFiles = ClaudeEvent.allCases.flatMap {
            SoundPackManager.shared.allSoundFiles(forEvent: $0, inPack: id)
        }.filter { !$0.hasSuffix(".disabled") }
        guard !allFiles.isEmpty else { return }
        let file = allFiles[Int.random(in: 0..<allFiles.count)]

        let volumeFile = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/sounds/.volume")
        let vol = (try? String(contentsOfFile: volumeFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "0.50"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
        proc.arguments = ["-v", vol, file]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try? proc.run()
        previewProcess = proc
    }

    @objc func editPack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        WindowManager.shared.showEditPack(packId: id) { [weak self] in
            self?.rebuildUI()
        }
    }

    @objc func publishPack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        WindowManager.shared.showPublishPack(packId: id) { [weak self] in
            self?.refresh()
        }
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

    @objc func updatePack(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue,
              let pack = manifestPacks.first(where: { $0.id == id }) else { return }

        sender.isEnabled = false
        sender.title = "Updating..."
        updateProgress[id]?.isHidden = false

        SoundPackManager.shared.downloadAndInstall(pack: pack, progress: { [weak self] pct in
            self?.updateProgress[id]?.doubleValue = pct
        }, completion: { [weak self] success in
            if success {
                self?.installedPacks = SoundPackManager.shared.installedPackIds()
                self?.rebuildUI()
            } else {
                sender.isEnabled = true
                sender.title = "Update"
                self?.updateProgress[id]?.isHidden = true
                let alert = NSAlert()
                alert.messageText = "Update Failed"
                alert.informativeText = "Could not download or extract the updated sound pack."
                alert.runModal()
            }
        })
    }

    @objc func installFromURL() {
        WindowManager.shared.showInstallURL { [weak self] in
            self?.refresh()
        }
    }

    @objc func installFromZip() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.init(filenameExtension: "zip")!]

        guard panel.runModal() == .OK, let url = panel.url else { return }

        SoundPackManager.shared.installFromZip(at: url) { [weak self] success in
            if success {
                self?.refresh()
            } else {
                let alert = NSAlert()
                alert.messageText = "Extraction Failed"
                alert.informativeText = "Could not extract the ZIP file."
                alert.runModal()
            }
        }
    }

    @objc func openManageRegistries() {
        WindowManager.shared.showManageRegistries { [weak self] in
            self?.refresh()
        }
    }

    private func addRegistryRow(_ urlStr: String) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: urlStr)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(label)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -16),
            label.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])

        stackView.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true
    }
}
