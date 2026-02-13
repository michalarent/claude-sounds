import Cocoa

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
    private var openEditorOnCreate: Bool

    init(onCreated: (() -> Void)? = nil, openEditorOnCreate: Bool = true) {
        self.onCreated = onCreated
        self.openEditorOnCreate = openEditorOnCreate

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
        if openEditorOnCreate {
            WindowManager.shared.showEventEditor()
        }
    }
}
