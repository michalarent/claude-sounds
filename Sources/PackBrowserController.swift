import Cocoa
import SwiftUI

// MARK: - Pack Grid Data

struct PackGridItem: Identifiable {
    let id: String
    let name: String
    let description: String
    let version: String
    let isInstalled: Bool
    let isActive: Bool
    let isLocalOnly: Bool
    let updateAvailable: Bool
    let manifestVersion: String?
    let size: String
    let fileCount: Int
}

// MARK: - View Model

class PackBrowserViewModel: ObservableObject {
    @Published var packs: [PackGridItem] = []
    @Published var registryURLs: [String] = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloading: Set<String> = []
    @Published var updating: Set<String> = []

    weak var controller: PackBrowserController?

    func activate(_ id: String) { controller?.activatePack(id) }
    func uninstall(_ id: String) { controller?.uninstallPack(id) }
    func download(_ id: String) { controller?.downloadPack(id) }
    func update(_ id: String) { controller?.updatePack(id) }
    func preview(_ id: String) { controller?.previewPack(id) }
    func edit(_ id: String) { controller?.editPack(id) }
    func publish(_ id: String) { controller?.publishPack(id) }
    func viewInFinder(_ id: String) { controller?.viewInFinder(id) }
    func refresh() { controller?.refresh() }
    func newPack() { controller?.newPack() }
    func installFromURL() { controller?.installFromURL() }
    func installFromZip() { controller?.installFromZip() }
    func manageRegistries() { controller?.openManageRegistries() }
}

// MARK: - Pack Browser Grid View

struct PackBrowserGridView: View {
    @ObservedObject var viewModel: PackBrowserViewModel

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 350), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    installedSection
                    availableSection
                    registriesSection
                }
                .padding(16)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
            Text("Claude Sounds v\(version)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Button("Install ZIP...") { viewModel.installFromZip() }
                .controlSize(.small)
            Button("Install URL...") { viewModel.installFromURL() }
                .controlSize(.small)
            Button("New Pack...") { viewModel.newPack() }
                .controlSize(.small)
            Button("Refresh") { viewModel.refresh() }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var installedSection: some View {
        let installed = viewModel.packs.filter { $0.isInstalled }
        sectionHeader("Installed")
        if installed.isEmpty {
            Text("No packs installed")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(installed) { pack in
                    PackCardView(pack: pack, viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private var availableSection: some View {
        let available = viewModel.packs.filter { !$0.isInstalled }
        if !available.isEmpty {
            sectionHeader("Available")
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(available) { pack in
                    PackCardView(pack: pack, viewModel: viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private var registriesSection: some View {
        sectionHeader("Registries")
        if viewModel.registryURLs.isEmpty {
            Text("No custom registries")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        } else {
            ForEach(viewModel.registryURLs, id: \.self) { url in
                Text(url)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        Button("Manage Registries...") { viewModel.manageRegistries() }
            .controlSize(.small)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.secondary)
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(height: 1)
        }
    }
}

// MARK: - Pack Card View

struct PackCardView: View {
    let pack: PackGridItem
    @ObservedObject var viewModel: PackBrowserViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Text(pack.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                if pack.isInstalled && pack.isActive {
                    Text("Active")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                }
            }

            // Description
            Text(pack.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)

            // Version
            if pack.updateAvailable, let newVer = pack.manifestVersion {
                Text("v\(pack.version) \u{2192} v\(newVer)")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            } else {
                Text("v\(pack.version)")
                    .font(.system(size: 10))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }

            // Size/count for available packs
            if !pack.isInstalled && (pack.fileCount > 0 || !pack.size.isEmpty) {
                HStack(spacing: 8) {
                    if pack.fileCount > 0 {
                        Text("\(pack.fileCount) files")
                    }
                    if !pack.size.isEmpty {
                        Text(pack.size)
                    }
                }
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }

            Spacer(minLength: 4)

            // Progress bar
            if let progress = viewModel.downloadProgress[pack.id] {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            }

            Divider()

            // Actions
            if pack.isInstalled {
                installedActions
            } else {
                availableActions
            }
        }
        .padding(12)
        .frame(minHeight: 180)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    pack.isActive
                        ? Color.green.opacity(0.4)
                        : Color(NSColor.separatorColor).opacity(0.5),
                    lineWidth: pack.isActive ? 1.5 : 1
                )
        )
    }

    @ViewBuilder
    private var installedActions: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if !pack.isActive {
                    Button("Activate") { viewModel.activate(pack.id) }
                        .controlSize(.small)
                }
                if pack.updateAvailable {
                    Button("Update") { viewModel.update(pack.id) }
                        .controlSize(.small)
                        .disabled(viewModel.updating.contains(pack.id))
                }
                Spacer()
                Button("Preview") { viewModel.preview(pack.id) }
                    .controlSize(.small)
            }
            HStack(spacing: 6) {
                if pack.isLocalOnly {
                    Button("Edit") { viewModel.edit(pack.id) }
                        .controlSize(.small)
                    Button("Publish") { viewModel.publish(pack.id) }
                        .controlSize(.small)
                }
                Button("Finder") { viewModel.viewInFinder(pack.id) }
                    .controlSize(.small)
                Spacer()
                Button("Uninstall") { viewModel.uninstall(pack.id) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var availableActions: some View {
        HStack {
            Spacer()
            Button("Download & Install") { viewModel.download(pack.id) }
                .controlSize(.small)
                .disabled(viewModel.downloading.contains(pack.id))
        }
    }
}

// MARK: - Pack Browser Controller

class PackBrowserController: NSObject {
    let window: NSWindow
    private let viewModel = PackBrowserViewModel()
    private var installedPacks: [String] = []
    private var manifestPacks: [SoundPackInfo] = []
    private var previewProcess: Process?

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "Sound Packs"
        window.center()
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 500, height: 400)

        super.init()

        viewModel.controller = self

        let hostingView = NSHostingView(rootView: PackBrowserGridView(viewModel: viewModel))
        window.contentView = hostingView

        refresh()
    }

    @objc func refresh() {
        installedPacks = SoundPackManager.shared.installedPackIds()
        SoundPackManager.shared.fetchManifestMerged { [weak self] manifest in
            self?.manifestPacks = manifest?.packs ?? []
            self?.rebuildData()
        }
        rebuildData()
    }

    private func rebuildData() {
        let activePack = SoundPackManager.shared.activePackId()
        var items: [PackGridItem] = []

        for packId in installedPacks {
            let info = manifestPacks.first { $0.id == packId }
            let localMeta = SoundPackManager.shared.loadPackMetadata(id: packId)
            let localVersion = localMeta?["version"]
            let updateAvailable: Bool = {
                guard let local = localVersion, let manifest = info?.version else { return false }
                return local != manifest
            }()
            let isLocalOnly = !manifestPacks.contains(where: { $0.id == packId })

            items.append(PackGridItem(
                id: packId,
                name: localMeta?["name"] ?? info?.name ?? packId.capitalized,
                description: localMeta?["description"].flatMap({ $0.isEmpty ? nil : $0 }) ?? info?.description ?? "Locally installed",
                version: localVersion ?? info?.version ?? "\u{2014}",
                isInstalled: true,
                isActive: packId == activePack,
                isLocalOnly: isLocalOnly,
                updateAvailable: updateAvailable,
                manifestVersion: info?.version,
                size: info?.size ?? "",
                fileCount: info?.fileCount ?? 0
            ))
        }

        let available = manifestPacks.filter { !installedPacks.contains($0.id) }
        for pack in available {
            items.append(PackGridItem(
                id: pack.id,
                name: pack.name,
                description: pack.description,
                version: pack.version,
                isInstalled: false,
                isActive: false,
                isLocalOnly: false,
                updateAvailable: false,
                manifestVersion: nil,
                size: pack.size,
                fileCount: pack.fileCount
            ))
        }

        viewModel.packs = items
        viewModel.registryURLs = SoundPackManager.shared.customManifestURLs()
    }

    // MARK: - Actions

    func newPack() {
        WindowManager.shared.showNewPack { [weak self] in
            self?.refresh()
        }
    }

    func previewPack(_ id: String) {
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

    func viewInFinder(_ id: String) {
        let path = (SoundPackManager.shared.soundsDir as NSString).appendingPathComponent(id)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func editPack(_ id: String) {
        WindowManager.shared.showEditPack(packId: id) { [weak self] in
            self?.rebuildData()
        }
    }

    func publishPack(_ id: String) {
        WindowManager.shared.showPublishPack(packId: id) { [weak self] in
            self?.refresh()
        }
    }

    func activatePack(_ id: String) {
        SoundPackManager.shared.setActivePack(id)
        rebuildData()
    }

    func uninstallPack(_ id: String) {
        let alert = NSAlert()
        alert.messageText = "Uninstall \(id)?"
        alert.informativeText = "This will delete all sound files for this pack."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                SoundPackManager.shared.uninstallPack(id: id)
                self?.installedPacks = SoundPackManager.shared.installedPackIds()
                self?.rebuildData()
            }
        }
    }

    func downloadPack(_ id: String) {
        guard let pack = manifestPacks.first(where: { $0.id == id }) else { return }

        viewModel.downloading.insert(id)
        viewModel.downloadProgress[id] = 0

        SoundPackManager.shared.downloadAndInstall(pack: pack, progress: { [weak self] pct in
            self?.viewModel.downloadProgress[id] = pct
        }, completion: { [weak self] success in
            self?.viewModel.downloading.remove(id)
            self?.viewModel.downloadProgress.removeValue(forKey: id)
            if success {
                self?.installedPacks = SoundPackManager.shared.installedPackIds()
                self?.rebuildData()
            } else {
                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = "Could not download or extract the sound pack."
                alert.beginSheetModal(for: self?.window ?? NSWindow()) { _ in }
            }
        })
    }

    func updatePack(_ id: String) {
        guard let pack = manifestPacks.first(where: { $0.id == id }) else { return }

        viewModel.updating.insert(id)
        viewModel.downloadProgress[id] = 0

        SoundPackManager.shared.downloadAndInstall(pack: pack, progress: { [weak self] pct in
            self?.viewModel.downloadProgress[id] = pct
        }, completion: { [weak self] success in
            self?.viewModel.updating.remove(id)
            self?.viewModel.downloadProgress.removeValue(forKey: id)
            if success {
                self?.installedPacks = SoundPackManager.shared.installedPackIds()
                self?.rebuildData()
            } else {
                let alert = NSAlert()
                alert.messageText = "Update Failed"
                alert.informativeText = "Could not download or extract the updated sound pack."
                alert.beginSheetModal(for: self?.window ?? NSWindow()) { _ in }
            }
        })
    }

    func installFromURL() {
        WindowManager.shared.showInstallURL { [weak self] in
            self?.refresh()
        }
    }

    func installFromZip() {
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
                alert.beginSheetModal(for: self?.window ?? NSWindow()) { _ in }
            }
        }
    }

    func openManageRegistries() {
        WindowManager.shared.showManageRegistries { [weak self] in
            self?.refresh()
        }
    }
}
