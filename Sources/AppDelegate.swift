import Cocoa

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            AppUpdater.shared.checkForUpdateSilent()
        }
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let header = NSMenuItem(title: "Claude Sounds v\(version)", action: nil, keyEquivalent: "")
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

        let importItem = NSMenuItem(title: "Import Sounds...", action: #selector(openSoundImporter), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

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

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc func checkForUpdates() {
        AppUpdater.shared.checkForUpdateInteractive()
    }

    @objc func openPackBrowser() {
        WindowManager.shared.showPackBrowser()
    }

    @objc func openEventEditor() {
        WindowManager.shared.showEventEditor()
    }

    @objc func openSoundImporter() {
        WindowManager.shared.showSoundImporter()
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
