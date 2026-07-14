import AppKit
import Foundation

// Keep a global strong reference to prevent deallocation of AppDelegate
var globalDelegate: AppDelegate?

// Keep a global handle to DFRFoundation to prevent category unloading
var dfrLibraryHandle: UnsafeMutableRawPointer?

// Define identifiers
extension NSTouchBarItem.Identifier {
    static let systemTrayItem = NSTouchBarItem.Identifier("com.ampamp.agy-touchbar.systemTray")
    static let quotaTextItem = NSTouchBarItem.Identifier("com.ampamp.agy-touchbar.quotaText")
}

extension NSTouchBar.CustomizationIdentifier {
    static let touchBar = NSTouchBar.CustomizationIdentifier("com.ampamp.agy-touchbar.bar")
}

typealias DFRElementSetControlStripPresenceForIdentifierType = @convention(c) (CFString, Bool) -> Void

@objc protocol PrivateNSTouchBar_TouchBar {
    @objc(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)
    static func presentSystemModalTouchBar(_ touchBar: NSTouchBar, placement: Int, systemTrayItemIdentifier: String)
    
    @objc(dismissSystemModalTouchBar:)
    static func dismissSystemModalTouchBar(_ touchBar: NSTouchBar)
}

@objc protocol PrivateNSTouchBar_FunctionBar {
    @objc(presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:)
    static func presentSystemModalFunctionBar(_ touchBar: NSTouchBar, placement: Int, systemTrayItemIdentifier: String)
    
    @objc(dismissSystemModalFunctionBar:)
    static func dismissSystemModalFunctionBar(_ touchBar: NSTouchBar)
}

@objc protocol PrivateNSTouchBar_Legacy {
    @objc(presentSystemModalTouchBar:systemTrayItemIdentifier:)
    static func presentSystemModalTouchBar(_ touchBar: NSTouchBar, systemTrayItemIdentifier: String)
    
    @objc(presentSystemModalFunctionBar:systemTrayItemIdentifier:)
    static func presentSystemModalFunctionBar(_ touchBar: NSTouchBar, systemTrayItemIdentifier: String)
}

struct QuotaData: Codable {
    let gemini_weekly: Double
    let gemini_5h: Double
    let claude_weekly: Double
    let claude_5h: Double
    let gemini_weekly_reset: String
    let gemini_5h_reset: String
    let claude_weekly_reset: String
    let claude_5h_reset: String
    let cost: Double
    let status: String
}

func logToFile(_ message: String) {
    let logMsg = "[\(Date())] \(message)\n"
    if let fileHandle = FileHandle(forWritingAtPath: "/tmp/agy-touchbar.log") {
        fileHandle.seekToEndOfFile()
        if let data = logMsg.data(using: .utf8) {
            fileHandle.write(data)
        }
        fileHandle.closeFile()
    } else {
        try? logMsg.write(toFile: "/tmp/agy-touchbar.log", atomically: true, encoding: .utf8)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSTouchBarDelegate {
    var statusItem: NSStatusItem?
    var systemTrayItem: NSCustomTouchBarItem?
    var trayButton: NSButton?
    var quotaTouchBar: NSTouchBar?
    var timer: Timer?
    var isModalPresented = false
    
    // Cached non-100% online fallback values
    var cachedWeekly: Double?
    var cachedFiveHour: Double?

    // Expanded Touch Bar references
    var geminiWeeklyBar: NSProgressIndicator?
    var geminiWeeklyLabel: NSTextField?
    var gemini5hBar: NSProgressIndicator?
    var gemini5hLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logToFile("Application did finish launching.")
        
        // Run as accessory/background application (no Dock icon)
        NSApp.setActivationPolicy(.accessory)
        
        // Load and retain DFRFoundation private framework category extensions
        dfrLibraryHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)
        if dfrLibraryHandle != nil {
            logToFile("DFRFoundation dynamically loaded and retained.")
        } else {
            logToFile("Warning: DFRFoundation could not be loaded via dlopen.")
        }
        
        setupMenuBar()
        setupTouchBar()
        startTimer()
    }
    
    func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "Loading..."
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            
            if let icon = getAntigravityIcon() {
                button.image = icon
                button.imagePosition = .imageLeading
                logToFile("Loaded Antigravity icon for Menu Bar successfully.")
            } else {
                button.title = "🌌 Loading..."
            }
            
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Force Update", action: #selector(updateQuotas), keyEquivalent: "u"))
            menu.addItem(NSMenuItem(title: "Toggle Expanded Touchbar", action: #selector(toggleTouchBarFromMenu), keyEquivalent: "t"))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
            statusItem?.menu = menu
        }
        logToFile("Menu bar setup completed.")
    }
    
    @objc func quitApp() {
        logToFile("Quitting application.")
        NSApplication.shared.terminate(nil)
    }

    func getAntigravityIcon() -> NSImage? {
        let paths = [
            "/Applications/Antigravity.app/Contents/Resources/icon.icns",
            "/Applications/Antigravity IDE.app/Contents/Resources/Antigravity IDE.icns"
        ]
        for path in paths {
            if let img = NSImage(contentsOfFile: path) {
                // Resize for Touch Bar Control Strip and Menu Bar (16x16 standard)
                img.size = NSSize(width: 16, height: 16)
                return img
            }
        }
        return nil
    }

    func makeIconImageView() -> NSImageView {
        let imgView = NSImageView()
        if let icon = getAntigravityIcon() {
            let copy = icon.copy() as! NSImage
            copy.size = NSSize(width: 14, height: 14)
            imgView.image = copy
        }
        imgView.translatesAutoresizingMaskIntoConstraints = false
        imgView.widthAnchor.constraint(equalToConstant: 14).isActive = true
        imgView.heightAnchor.constraint(equalToConstant: 14).isActive = true
        return imgView
    }

    func setControlStripPresence(visible: Bool) {
        if let handle = dfrLibraryHandle {
            let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier")
            if let sym = sym {
                let setPresence = unsafeBitCast(sym, to: DFRElementSetControlStripPresenceForIdentifierType.self)
                setPresence("com.ampamp.agy-touchbar.systemTray" as CFString, visible)
                logToFile("DFRElementSetControlStripPresenceForIdentifier (\(visible)) call succeeded.")
            }
        }
    }

    func setupTouchBar() {
        logToFile("Setting up Touch Bar...")
        
        // 1. Create Control Strip button
        let button = NSButton(title: "Loading...", target: self, action: #selector(handleButtonTap(_:)))
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        
        if let icon = getAntigravityIcon() {
            button.image = icon
            button.imagePosition = .imageLeading
            logToFile("Loaded Antigravity icon for Touch Bar successfully.")
        } else {
            button.title = "🌌 Loading..."
        }
        
        trayButton = button

        // 2. Wrap in NSCustomTouchBarItem
        let trayItem = NSCustomTouchBarItem(identifier: .systemTrayItem)
        trayItem.view = button
        systemTrayItem = trayItem
        
        // 3. Register System Tray item using Private ObjC API reflection
        if let NSTouchBarItemClass = NSClassFromString("NSTouchBarItem") as? NSObject.Type {
            let selector = NSSelectorFromString("addSystemTrayItem:")
            if NSTouchBarItemClass.responds(to: selector) {
                NSTouchBarItemClass.perform(selector, with: trayItem)
                logToFile("Private addSystemTrayItem: call succeeded.")
            } else {
                logToFile("Private addSystemTrayItem: selector not found on NSTouchBarItem.")
            }
        }
        
        // 4. Force present it in the Control Strip via private DFRFoundation library
        setControlStripPresence(visible: true)
        
        // 5. Set up the expanded Touch Bar modal
        let touchBar = NSTouchBar()
        touchBar.customizationIdentifier = .touchBar
        touchBar.defaultItemIdentifiers = [.quotaTextItem]
        touchBar.delegate = self
        quotaTouchBar = touchBar
        
        updateQuotas()
    }
    
    @objc func handleButtonTap(_ sender: Any?) {
        logToFile("Touch Bar button tapped. Toggling Touch Bar modal...")
        toggleTouchBar()
    }

    @objc func handleCloseButtonTap(_ sender: Any?) {
        logToFile("Close button tapped. Dismissing Touch Bar modal...")
        toggleTouchBar()
    }

    @objc func toggleTouchBarFromMenu() {
        logToFile("Menu bar toggle action triggered.")
        toggleTouchBar()
    }

    func toggleTouchBar() {
        guard let touchBar = quotaTouchBar else { return }
        
        let NSTouchBarClassObj = NSClassFromString("NSTouchBar") as AnyObject
        
        if isModalPresented {
            logToFile("Dismissing Touch Bar modal...")
            
            let dismissTouchBarSel = NSSelectorFromString("dismissSystemModalTouchBar:")
            let dismissFunctionBarSel = NSSelectorFromString("dismissSystemModalFunctionBar:")
            
            if NSTouchBarClassObj.responds(to: dismissTouchBarSel) {
                let casted = unsafeBitCast(NSTouchBarClassObj, to: PrivateNSTouchBar_TouchBar.Type.self)
                casted.dismissSystemModalTouchBar(touchBar)
                logToFile("Dismissed using dismissSystemModalTouchBar:")
            } else if NSTouchBarClassObj.responds(to: dismissFunctionBarSel) {
                let casted = unsafeBitCast(NSTouchBarClassObj, to: PrivateNSTouchBar_FunctionBar.Type.self)
                casted.dismissSystemModalFunctionBar(touchBar)
                logToFile("Dismissed using dismissSystemModalFunctionBar:")
            }
            
            // Re-assert Control Strip presence to restore the button
            setControlStripPresence(visible: true)
            
            isModalPresented = false
        } else {
            logToFile("Presenting Touch Bar modal...")
            var presented = false
            
            let presentTouchBar3Sel = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
            let presentFunctionBar3Sel = NSSelectorFromString("presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:")
            
            let presentTouchBar2Sel = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
            let presentFunctionBar2Sel = NSSelectorFromString("presentSystemModalFunctionBar:systemTrayItemIdentifier:")
            
            logToFile("Checking responds(to:) for presentation selectors...")
            let respTouchBar3 = NSTouchBarClassObj.responds(to: presentTouchBar3Sel)
            let respFunctionBar3 = NSTouchBarClassObj.responds(to: presentFunctionBar3Sel)
            let respTouchBar2 = NSTouchBarClassObj.responds(to: presentTouchBar2Sel)
            let respFunctionBar2 = NSTouchBarClassObj.responds(to: presentFunctionBar2Sel)
            
            logToFile("Selectors response: TouchBar3=\(respTouchBar3), FunctionBar3=\(respFunctionBar3), TouchBar2=\(respTouchBar2), FunctionBar2=\(respFunctionBar2)")
            
            if respTouchBar3 {
                let casted = unsafeBitCast(NSTouchBarClassObj, to: PrivateNSTouchBar_TouchBar.Type.self)
                casted.presentSystemModalTouchBar(touchBar, placement: 1, systemTrayItemIdentifier: "com.ampamp.agy-touchbar.systemTray")
                logToFile("Presented using presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
                presented = true
            }
            
            if !presented && respFunctionBar3 {
                let casted = unsafeBitCast(NSTouchBarClassObj, to: PrivateNSTouchBar_FunctionBar.Type.self)
                casted.presentSystemModalFunctionBar(touchBar, placement: 1, systemTrayItemIdentifier: "com.ampamp.agy-touchbar.systemTray")
                logToFile("Presented using presentSystemModalFunctionBar:placement:systemTrayItemIdentifier:")
                presented = true
            }
            
            if !presented && respTouchBar2 {
                let casted = unsafeBitCast(NSTouchBarClassObj, to: PrivateNSTouchBar_Legacy.Type.self)
                casted.presentSystemModalTouchBar(touchBar, systemTrayItemIdentifier: "com.ampamp.agy-touchbar.systemTray")
                logToFile("Presented using presentSystemModalTouchBar:systemTrayItemIdentifier:")
                presented = true
            }
            
            if !presented && respFunctionBar2 {
                let casted = unsafeBitCast(NSTouchBarClassObj, to: PrivateNSTouchBar_Legacy.Type.self)
                casted.presentSystemModalFunctionBar(touchBar, systemTrayItemIdentifier: "com.ampamp.agy-touchbar.systemTray")
                logToFile("Presented using presentSystemModalFunctionBar:systemTrayItemIdentifier:")
                presented = true
            }
            
            if presented {
                isModalPresented = true
                updateQuotas()
            } else {
                logToFile("Error: All presentation selectors failed or not found on NSTouchBar.")
            }
        }
    }
    
    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        logToFile("makeItemForIdentifier called for \(identifier.rawValue)")
        if identifier == .quotaTextItem {
            let item = NSCustomTouchBarItem(identifier: identifier)
            
            let mainStack = NSStackView()
            mainStack.orientation = .horizontal
            mainStack.spacing = 16
            mainStack.alignment = .centerY
            
            // Close Button (Allows toggling dismissal)
            let closeButton = NSButton(title: "✕", target: self, action: #selector(handleCloseButtonTap(_:)))
            closeButton.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            closeButton.bezelStyle = .rounded
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.widthAnchor.constraint(equalToConstant: 32).isActive = true
            
            // Gemini Section (Vertical stack containing Weekly and 5h)
            let gStack = NSStackView()
            gStack.orientation = .vertical
            gStack.spacing = 2
            gStack.alignment = .leading
            
            // Gemini Weekly Row
            let gwRow = NSStackView()
            gwRow.orientation = .horizontal
            gwRow.spacing = 6
            
            let gwIcon = makeIconImageView()
            let gwTitle = NSTextField(labelWithString: "Gemini Weekly:")
            gwTitle.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            gwTitle.textColor = NSColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 1.0)
            gwTitle.widthAnchor.constraint(equalToConstant: 95).isActive = true
            
            let gwBar = NSProgressIndicator()
            gwBar.isIndeterminate = false
            gwBar.minValue = 0
            gwBar.maxValue = 100
            gwBar.controlSize = .small
            gwBar.style = .bar
            gwBar.translatesAutoresizingMaskIntoConstraints = false
            gwBar.widthAnchor.constraint(equalToConstant: 120).isActive = true
            
            let gwLabel = NSTextField(labelWithString: "100%")
            gwLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            gwLabel.textColor = NSColor.white
            
            gwRow.addArrangedSubview(gwIcon)
            gwRow.addArrangedSubview(gwTitle)
            gwRow.addArrangedSubview(gwBar)
            gwRow.addArrangedSubview(gwLabel)
            
            // Gemini 5h Row
            let g5Row = NSStackView()
            g5Row.orientation = .horizontal
            g5Row.spacing = 6
            
            let g5Icon = makeIconImageView()
            let g5Title = NSTextField(labelWithString: "Gemini 5-Hour:")
            g5Title.font = NSFont.systemFont(ofSize: 10, weight: .bold)
            g5Title.textColor = NSColor(red: 0.7, green: 0.5, blue: 1.0, alpha: 1.0)
            g5Title.widthAnchor.constraint(equalToConstant: 95).isActive = true
            
            let g5Bar = NSProgressIndicator()
            g5Bar.isIndeterminate = false
            g5Bar.minValue = 0
            g5Bar.maxValue = 100
            g5Bar.controlSize = .small
            g5Bar.style = .bar
            g5Bar.translatesAutoresizingMaskIntoConstraints = false
            g5Bar.widthAnchor.constraint(equalToConstant: 120).isActive = true
            
            let g5Label = NSTextField(labelWithString: "100%")
            g5Label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            g5Label.textColor = NSColor.white
            
            g5Row.addArrangedSubview(g5Icon)
            g5Row.addArrangedSubview(g5Title)
            g5Row.addArrangedSubview(g5Bar)
            g5Row.addArrangedSubview(g5Label)
            
            gStack.addArrangedSubview(gwRow)
            gStack.addArrangedSubview(g5Row)
            
            geminiWeeklyBar = gwBar
            geminiWeeklyLabel = gwLabel
            gemini5hBar = g5Bar
            gemini5hLabel = g5Label
            
            mainStack.addArrangedSubview(closeButton)
            mainStack.addArrangedSubview(gStack)
            
            item.view = mainStack
            return item
        }
        return nil
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.updateQuotas()
        }
    }
    
    @objc func updateQuotas() {
        logToFile("Updating quotas...")
        let task = Process()
        task.launchPath = "/bin/zsh"
        task.arguments = ["-c", "/usr/local/bin/agy-touchbar --json"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        task.launch()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let rawOutput = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawOutput.isEmpty {
            logToFile("Parsed JSON output: \(rawOutput)")
            
            if let jsonData = rawOutput.data(using: .utf8) {
                if let decoded = try? JSONDecoder().decode(QuotaData.self, from: jsonData) {
                    DispatchQueue.main.async {
                        self.updateUI(with: decoded)
                    }
                    return
                }
            }
        }
        
        logToFile("Error parsing JSON output. Falling back.")
        DispatchQueue.main.async {
            self.trayButton?.title = "Offline"
            self.statusItem?.button?.title = "Offline"
        }
    }

    func getQuotaColor(_ percent: Double) -> NSColor {
        if percent >= 50.0 {
            return NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0) // Green
        } else if percent >= 30.0 {
            return NSColor(red: 0.9, green: 0.8, blue: 0.1, alpha: 1.0) // Yellow
        } else {
            return NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 1.0) // Red
        }
    }

    func updateUI(with data: QuotaData) {
        if data.status == "online" {
            cachedWeekly = data.gemini_weekly
            cachedFiveHour = data.gemini_5h
        }
        
        let displayWeekly = (data.status == "offline" ? cachedWeekly : nil) ?? data.gemini_weekly
        let displayFiveHour = (data.status == "offline" ? cachedFiveHour : nil) ?? data.gemini_5h
        
        // 1. Update Control Strip button title (shows the cumulative daily cost)
        if data.status == "offline" {
            trayButton?.title = "Offline | $\(String(format: "%.2f", data.cost))"
        } else {
            trayButton?.title = "$\(String(format: "%.2f", data.cost))"
        }
        
        // 2. Color range percentages for Menu Bar (attributed title based on the lowest current limit)
        let lowestPercent = min(displayWeekly, displayFiveHour)
        let color = getQuotaColor(lowestPercent)
        let titleText = " \(Int(displayWeekly))% | \(Int(displayFiveHour))%"
        let attrTitle = NSMutableAttributedString(string: titleText)
        attrTitle.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: titleText.count))
        statusItem?.button?.attributedTitle = attrTitle
        
        // 3. Update the progress bars (values are remaining %)
        geminiWeeklyBar?.doubleValue = displayWeekly
        gemini5hBar?.doubleValue = displayFiveHour
        
        // 4. Update Touch Bar labels and their color indicators
        var gwText = "\(Int(displayWeekly))%"
        if data.status == "offline" {
            gwText += " (Offline)"
        } else if data.gemini_weekly_reset != "Available" && data.gemini_weekly_reset != "N/A" {
            gwText += " (\(data.gemini_weekly_reset))"
        }
        geminiWeeklyLabel?.stringValue = gwText
        geminiWeeklyLabel?.textColor = getQuotaColor(displayWeekly)
        
        var g5Text = "\(Int(displayFiveHour))%"
        if data.status == "offline" {
            g5Text += " (Offline)"
        } else if data.gemini_5h_reset != "Available" && data.gemini_5h_reset != "N/A" {
            g5Text += " (\(data.gemini_5h_reset))"
        }
        gemini5hLabel?.stringValue = g5Text
        gemini5hLabel?.textColor = getQuotaColor(displayFiveHour)
        
        logToFile("Updated UI elements. TouchBar Gemini Wk: \(gwText), 5h: \(g5Text)")
    }
}

logToFile("================ START OF LOG ================")
let app = NSApplication.shared
let delegateInstance = AppDelegate()
globalDelegate = delegateInstance
app.delegate = delegateInstance
app.run()
