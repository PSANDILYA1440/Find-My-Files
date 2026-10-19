import AppKit
import WebKit

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    private var locationURLs: [String: URL] = [:]
    private var specialLocations: [String: (title: String, message: String)] = [:]
    private var itemURLs: [String: URL] = [:]
    private var currentLocationID: String?
    private var currentDirectoryURL: URL?
    private let fileIconCache = NSCache<NSString, NSData>()
    private var contextMenuURL: URL?
    private var contextMenuItemID: String?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        configureLocations()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "findMyFiles",
              let body = message.body as? [String: Any],
              let action = body["action"] as? String else {
            NSLog("Find My Files received an invalid native message.")
            return
        }

        switch action {
        case "getSidebar":
            sendToWeb("renderSidebar", arguments: ["groups": sidebarGroups()])
        case "openLocation":
            guard let locationID = body["locationId"] as? String else {
                NSLog("Find My Files received an invalid location request.")
                return
            }
            openLocation(locationID)
        case "listDirectory":
            guard let itemID = body["itemId"] as? String,
                  let url = itemURLs[itemID] else {
                NSLog("Find My Files received an unknown directory reference.")
                return
            }
            showDirectory(at: url)
        case "openItem":
            guard let itemID = body["itemId"] as? String,
                  let url = itemURLs[itemID] else {
                NSLog("Find My Files received an unknown file reference.")
                return
            }
            if !NSWorkspace.shared.open(url) {
                NSLog("Find My Files could not open the selected item: %@", url.path)
            }
        case "refreshLocation":
            if let currentLocationID {
                openLocation(currentLocationID)
            } else if let currentDirectoryURL {
                showDirectory(at: currentDirectoryURL)
            }
        case "showContextMenu":
            showContextMenu(for: body)
        case "requestFullDiskAccess":
            Self.openFullDiskAccessSettings()
        default:
            NSLog("Find My Files received an unsupported action: %@", action)
        }
    }

    private func configureLocations() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        locationURLs = [
            "applications": URL(fileURLWithPath: "/Applications", isDirectory: true),
            "desktop": home.appendingPathComponent("Desktop", isDirectory: true),
            "documents": home.appendingPathComponent("Documents", isDirectory: true),
            "downloads": home.appendingPathComponent("Downloads", isDirectory: true),
            "home": home,
            "icloud": home
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Mobile Documents", isDirectory: true)
                .appendingPathComponent("com~apple~CloudDocs", isDirectory: true),
            "computer": URL(fileURLWithPath: "/", isDirectory: true),
            "network": URL(fileURLWithPath: "/Network", isDirectory: true),
            "trash": home.appendingPathComponent(".Trash", isDirectory: true)
        ]

        specialLocations = [
            "airdrop": (
                "AirDrop",
                "AirDrop is managed by macOS and is not a browsable folder."
            ),
            "recents": (
                "Recents",
                "Recent-file indexing is not available yet."
            ),
            "tag-red": ("Red Tag", "No files with this tag were found."),
            "tag-orange": ("Orange Tag", "No files with this tag were found."),
            "tag-yellow": ("Yellow Tag", "No files with this tag were found."),
            "tag-green": ("Green Tag", "No files with this tag were found."),
            "tag-blue": ("Blue Tag", "No files with this tag were found."),
            "tag-purple": ("Purple Tag", "No files with this tag were found.")
        ]

        for volume in FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? [] {
            guard volume.path != "/" else { continue }
            let identifier = "volume-\(UUID().uuidString)"
            locationURLs[identifier] = volume
        }
    }

    private func sidebarGroups() -> [[String: Any]] {
        func entry(_ id: String, _ name: String, _ icon: String) -> [String: String] {
            ["id": id, "name": name, "icon": icon]
        }

        var groups: [[String: Any]] = [
            [
                "title": "Favorites",
                "items": [
                    entry("airdrop", "AirDrop", "⌁"),
                    entry("recents", "Recents", "◷"),
                    entry("applications", "Applications", "▦"),
                    entry("desktop", "Desktop", "▣"),
                    entry("documents", "Documents", "▤"),
                    entry("downloads", "Downloads", "⇩")
                ]
            ],
            [
                "title": "iCloud",
                "items": [entry("icloud", "iCloud Drive", "☁")]
            ],
            [
                "title": "Locations",
                "items": [
                    entry("home", "Home", "⌂"),
                    entry("computer", "Macintosh HD", "▰"),
                    entry("network", "Network", "⌘")
                ]
            ]
        ]

        let volumes = locationURLs.keys
            .filter { $0.hasPrefix("volume-") }
            .compactMap { id -> [String: String]? in
                guard let url = locationURLs[id] else { return nil }
                let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName)
                    ?? url.lastPathComponent
                return entry(id, name, "▰")
            }
        if !volumes.isEmpty {
            groups[2]["items"] = (groups[2]["items"] as? [[String: String]] ?? []) + volumes
        }
        groups[2]["items"] = (groups[2]["items"] as? [[String: String]] ?? [])
            + [entry("trash", "Trash", "▱")]

        groups.append([
            "title": "Tags",
            "items": [
                entry("tag-red", "Red", "●"),
                entry("tag-orange", "Orange", "●"),
                entry("tag-yellow", "Yellow", "●"),
                entry("tag-green", "Green", "●"),
                entry("tag-blue", "Blue", "●"),
                entry("tag-purple", "Purple", "●")
            ]
        ])
        return groups
    }

    private func openLocation(_ identifier: String) {
        currentLocationID = identifier
        if let location = specialLocations[identifier] {
            sendToWeb("showLocation", arguments: [
                "location": [
                    "title": location.title,
                    "section": identifier.hasPrefix("tag-") ? "TAGS" : "FAVORITES",
                    "description": location.message,
                    "message": location.message,
                    "items": []
                ]
            ])
            return
        }

        guard let url = locationURLs[identifier] else {
            NSLog("Find My Files received an unsupported location: %@", identifier)
            return
        }
        showDirectory(at: url, locationID: identifier)
    }

    private func showDirectory(at url: URL, locationID: String? = nil) {
        currentDirectoryURL = url
        currentLocationID = locationID
        let title: String
        switch locationID {
        case "applications": title = "Applications"
        case "desktop": title = "Desktop"
        case "documents": title = "Documents"
        case "downloads": title = "Downloads"
        case "home": title = "Home"
        case "icloud": title = "iCloud Drive"
        case "computer": title = "Macintosh HD"
        case "network": title = "Network"
        case "trash": title = "Trash"
        default: title = url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent
        }
        var payload: [String: Any] = [
            "title": title,
            "path": url.path,
            "items": []
        ]
        if let locationID {
            payload["section"] = locationID.hasPrefix("tag-") ? "TAGS" : "LOCATION"
        }

        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )
            let sortedURLs = urls.sorted { left, right in
                let leftIsDirectory = (try? left.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                let rightIsDirectory = (try? right.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if leftIsDirectory != rightIsDirectory {
                    return leftIsDirectory
                }
                return left.lastPathComponent.localizedStandardCompare(right.lastPathComponent) == .orderedAscending
            }

            itemURLs.removeAll(keepingCapacity: true)
            var iconIDs: [Data: String] = [:]
            var iconPayload: [String: String] = [:]
            let items: [[String: Any]] = sortedURLs.prefix(2_000).compactMap { childURL in
                guard let values = try? childURL.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ]) else {
                    return nil
                }

                let itemID = UUID().uuidString
                itemURLs[itemID] = childURL
                let isApplication = childURL.pathExtension.lowercased() == "app"
                let isDirectory = values.isDirectory == true
                    && values.isSymbolicLink != true
                    && !isApplication
                let itemSize: Any
                if isApplication {
                    if let bundleSize = directoryContentsSize(at: childURL) {
                        itemSize = bundleSize
                    } else {
                        itemSize = NSNull()
                    }
                } else if isDirectory {
                    itemSize = NSNull()
                } else if let fileSize = values.fileSize {
                    itemSize = fileSize
                } else {
                    itemSize = NSNull()
                }
                var item: [String: Any] = [
                    "id": itemID,
                    "name": childURL.lastPathComponent,
                    "isDirectory": isDirectory,
                    "kind": itemKind(for: childURL, isDirectory: isDirectory),
                    "size": itemSize
                ]
                if let iconData = fileIconData(for: childURL) {
                    let iconID: String
                    if let cachedID = iconIDs[iconData] {
                        iconID = cachedID
                    } else {
                        iconID = "icon-\(iconIDs.count)"
                        iconIDs[iconData] = iconID
                        iconPayload[iconID] = iconData.base64EncodedString()
                    }
                    item["iconID"] = iconID
                }
                if let modified = values.contentModificationDate {
                    item["modified"] = modified.formatted(date: .abbreviated, time: .shortened)
                    item["modifiedTimestamp"] = modified.timeIntervalSince1970
                }
                return item
            }
            payload["items"] = items
            payload["icons"] = iconPayload
            if urls.count > 2_000 {
                payload["message"] = "Showing the first 2,000 items."
            } else if items.isEmpty {
                payload["message"] = "No visible items in this location."
            }
        } catch {
            payload["error"] = true
            payload["message"] = error.localizedDescription
            NSLog("Find My Files could not list %@: %@", url.path, error.localizedDescription)
        }

        sendToWeb(locationID == nil ? "showDirectory" : "showLocation", arguments: [
            locationID == nil ? "directory" : "location": payload
        ])
    }

    private func directoryContentsSize(at url: URL) -> Int64? {
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ],
            options: [],
            errorHandler: { _, error in
                enumerationError = error
                return false
            }
        ) else {
            NSLog("Find My Files could not calculate the size of %@.", url.path)
            return nil
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey
            ]) else {
                enumerationError = CocoaError(.fileReadUnknown, userInfo: [
                    NSFilePathErrorKey: fileURL.path
                ])
                break
            }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let fileSize = values.fileSize else {
                continue
            }

            let (nextSize, overflow) = totalSize.addingReportingOverflow(Int64(fileSize))
            guard !overflow else {
                enumerationError = CocoaError(.fileReadTooLarge, userInfo: [
                    NSFilePathErrorKey: url.path
                ])
                break
            }
            totalSize = nextSize
        }

        if let enumerationError {
            NSLog(
                "Find My Files could not calculate the complete size of %@: %@",
                url.path,
                enumerationError.localizedDescription
            )
            return nil
        }
        return totalSize
    }

    private func fileIconData(for url: URL) -> Data? {
        let cacheKey = url.path as NSString
        if let cachedData = fileIconCache.object(forKey: cacheKey) {
            return cachedData as Data
        }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let pixelSize = NSSize(width: 64, height: 64)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 64,
            pixelsHigh: 64,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        graphicsContext.imageInterpolation = .high
        icon.draw(
            in: NSRect(origin: .zero, size: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        graphicsContext.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        fileIconCache.setObject(data as NSData, forKey: cacheKey)
        return data
    }

    private func itemKind(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "folder" }
        if url.pathExtension.lowercased() == "app" { return "application" }

        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "tiff", "bmp", "svg":
            return "image"
        case "mp3", "m4a", "aac", "wav", "aiff", "flac":
            return "audio"
        case "mov", "mp4", "m4v", "avi", "mkv":
            return "video"
        case "zip", "gz", "tar", "dmg", "pkg", "7z":
            return "archive"
        default:
            return "document"
        }
    }

    private func showContextMenu(for message: [String: Any]) {
        guard let itemID = message["itemId"] as? String,
              let url = itemURLs[itemID],
              let webView,
              let x = message["x"] as? Double,
              let y = message["y"] as? Double else {
            NSLog("Find My Files received an invalid context-menu request.")
            return
        }
        contextMenuURL = url
        contextMenuItemID = itemID
        contextMenuItemID = itemID

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open",
            action: #selector(openContextMenuItem(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let revealItem = NSMenuItem(
            title: "Show in Finder",
            action: #selector(showContextMenuItemInFinder(_:)),
            keyEquivalent: ""
        )
        revealItem.target = self
        menu.addItem(revealItem)

        let getInfoItem = NSMenuItem(
            title: "Get Info",
            action: #selector(showContextMenuItemInfo(_:)),
            keyEquivalent: ""
        )
        getInfoItem.target = self
        menu.addItem(getInfoItem)

        let copyPathItem = NSMenuItem(
            title: "Copy Path",
            action: #selector(copyContextMenuItemPath(_:)),
            keyEquivalent: ""
        )
        copyPathItem.target = self
        menu.addItem(copyPathItem)

        let point = NSPoint(
            x: min(max(x, 0), webView.bounds.width),
            y: webView.bounds.height - min(max(y, 0), webView.bounds.height)
        )
        menu.popUp(positioning: nil, at: point, in: webView)
    }

    @objc private func openContextMenuItem(_ sender: NSMenuItem) {
        guard contextMenuURL != nil, let contextMenuItemID else { return }
        sendToWeb("openItemFromMenu", arguments: ["itemID": contextMenuItemID])
    }

    @objc private func showContextMenuItemInFinder(_ sender: NSMenuItem) {
        guard let url = contextMenuURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func copyContextMenuItemPath(_ sender: NSMenuItem) {
        guard let url = contextMenuURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    @objc private func showContextMenuItemInfo(_ sender: NSMenuItem) {
        guard let url = contextMenuURL,
              let values = try? url.resourceValues(forKeys: [
                .localizedTypeDescriptionKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .isDirectoryKey
              ]) else {
            NSLog("Find My Files could not read information for the selected item.")
            return
        }

        let kind = values.localizedTypeDescription
            ?? (values.isDirectory == true ? "Folder" : "File")
        let size = values.isDirectory == true
            ? "—"
            : ByteCountFormatter.string(fromByteCount: Int64(values.fileSize ?? 0), countStyle: .file)
        let created = values.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"
        let modified = values.contentModificationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown"

        let alert = NSAlert()
        alert.messageText = url.lastPathComponent
        alert.informativeText = """
        Kind: \(kind)
        Size: \(size)
        Created: \(created)
        Modified: \(modified)

        \(url.path)
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func openFullDiskAccessSettings() {
        guard let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else {
            NSLog("Find My Files could not create the Full Disk Access settings URL.")
            return
        }
        guard NSWorkspace.shared.open(settingsURL) else {
            NSLog("Find My Files could not open Full Disk Access settings.")
            return
        }
    }

    private func sendToWeb(_ function: String, arguments: [String: Any]) {
        guard let webView else { return }
        Task { @MainActor in
            do {
                _ = try await webView.callAsyncJavaScript(
                    "window.FindMyFiles.\(function)(payload)",
                    arguments: ["payload": arguments.values.first ?? [:]],
                    in: nil,
                    contentWorld: .page
                )
            } catch {
                NSLog("Unable to update the interface: %@", error.localizedDescription)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    private var webView: WKWebView?
    private var nativeBridge: NativeBridge?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        let projectDirectory = URL(
            fileURLWithPath: #filePath
        ).deletingLastPathComponent()
        let projectWebDirectory = projectDirectory.appendingPathComponent(
            "WebUI",
            isDirectory: true
        )
        let webDirectoryCandidates = [
            Bundle.main.resourceURL?.appendingPathComponent(
                "WebUI",
                isDirectory: true
            ),
            projectWebDirectory
        ].compactMap { $0 }

        guard let webDirectory = webDirectoryCandidates.first(where: {
            FileManager.default.fileExists(
                atPath: $0.appendingPathComponent("index.html").path
            )
        }) else {
            NSLog("Find My Files could not find WebUI/index.html at %@", projectWebDirectory.path)
            NSApp.terminate(nil)
            return
        }
        let indexURL = webDirectory.appendingPathComponent("index.html")

        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.autoresizingMask = [.width, .height]
        webView.underPageBackgroundColor = .clear

        let nativeBridge = NativeBridge(webView: webView)
        contentController.add(nativeBridge, name: "findMyFiles")

        let visualEffectView = NSVisualEffectView(frame: .zero)
        visualEffectView.material = .hudWindow
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]
        visualEffectView.addSubview(webView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Find My Files"
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = visualEffectView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.webView = webView
        self.nativeBridge = nativeBridge
        self.window = window
        webView.loadFileURL(indexURL, allowingReadAccessTo: webDirectory)

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.requestFullDiskAccessOnFirstLaunch()
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        if let window {
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
        return false
    }

    private func requestFullDiskAccessOnFirstLaunch() {
        let preferenceKey = "didShowFullDiskAccessPrompt"
        guard !UserDefaults.standard.bool(forKey: preferenceKey) else { return }
        UserDefaults.standard.set(true, forKey: preferenceKey)

        let alert = NSAlert()
        alert.messageText = "Allow Full Disk Access"
        alert.informativeText = """
        Full Disk Access lets Find My Files browse protected locations across your Mac. \
        macOS requires you to enable it in Privacy & Security settings.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            NativeBridge.openFullDiskAccessSettings()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.setActivationPolicy(.regular)
app.delegate = delegate
app.run()
