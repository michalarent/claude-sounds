import Cocoa

// MARK: - Window Manager

class WindowManager {
    static let shared = WindowManager()

    private var packBrowserWindow: NSWindow?
    private var eventEditorWindow: NSWindow?
    private var setupWizardWindow: NSWindow?
    private var installURLWindow: NSWindow?
    private var manageRegistriesWindow: NSWindow?

    private var packBrowserController: PackBrowserController?
    private var eventEditorController: EventEditorController?
    private var wizardController: SetupWizardController?
    private var installURLController: InstallURLController?
    private var manageRegistriesController: ManageRegistriesController?

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

    func showNewPack(onCreated: (() -> Void)? = nil, openEditorOnCreate: Bool = true) {
        if let w = newPackWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = NewPackController(onCreated: onCreated, openEditorOnCreate: openEditorOnCreate)
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

    func showInstallURL(onInstalled: (() -> Void)? = nil) {
        if let w = installURLWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = InstallURLController(onInstalled: onInstalled)
        let w = ctrl.window
        installURLWindow = w
        installURLController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var publishPackWindow: NSWindow?
    private var publishPackController: PublishPackController?

    func showPublishPack(packId: String, onPublished: (() -> Void)? = nil) {
        if let w = publishPackWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = PublishPackController(packId: packId, onPublished: onPublished)
        let w = ctrl.window
        publishPackWindow = w
        publishPackController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var soundImporterWindow: NSWindow?
    private var soundImporterController: SoundImporterController?

    func showSoundImporter(onImported: (() -> Void)? = nil) {
        if let w = soundImporterWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = SoundImporterController(onImported: onImported)
        let w = ctrl.window
        soundImporterWindow = w
        soundImporterController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showManageRegistries(onChanged: (() -> Void)? = nil) {
        if let w = manageRegistriesWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let ctrl = ManageRegistriesController(onChanged: onChanged)
        let w = ctrl.window
        manageRegistriesWindow = w
        manageRegistriesController = ctrl
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
