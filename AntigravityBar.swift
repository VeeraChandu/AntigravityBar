import Cocoa
import Foundation

struct LimitResponse: Codable {
    struct Tier: Codable {
        let name: String?
        let id: String?
    }
    struct Bucket: Codable {
        let id: String?
        let name: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: String?
        let resetsIn: String?
        let disabled: Bool?
        let description: String?
    }
    struct Group: Codable {
        let name: String?
        let description: String?
        let buckets: [Bucket]?
    }

    let email: String?
    let tier: Tier?
    let availableCredits: Int?
    let groups: [Group]?
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var timer: Timer?
    var pythonScriptPath: String {
        if let bundled = Bundle.main.path(forResource: "antigravity_limits", ofType: "py"),
           FileManager.default.fileExists(atPath: bundled) {
            return bundled
        }
        return NSString(string: "~/.local/bin/agy-limits").expandingTildeInPath
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        setupIcon()
        
        if let button = statusItem.button {
            button.title = " Limits: ..."
        }
        
        buildInitialMenu()
        refreshLimits()
        
        // Auto refresh every 5 minutes (300 seconds)
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshLimits()
        }
    }

    func setupIcon() {
        guard let button = statusItem.button else { return }
        
        // Bundle.main.image(forResource:) automatically resolves both @1x and @2x Retina scales
        if let img = Bundle.main.image(forResource: "StatusBarIcon") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            button.image = img
            button.imagePosition = .imageLeft
        } else if let sf = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "Antigravity Limits") {
            sf.isTemplate = true
            button.image = sf
            button.imagePosition = .imageLeft
        }
    }

    func buildInitialMenu() {
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "Antigravity Limits", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Fetching quota...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }

    @objc func refreshClicked() {
        if let button = statusItem.button {
            button.title = " Fetching..."
        }
        refreshLimits()
    }

    @objc func quitClicked() {
        NSApp.terminate(nil)
    }

    func refreshLimits() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [self.pythonScriptPath, "--json"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            do {
                try process.run()
                process.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let response = try? JSONDecoder().decode(LimitResponse.self, from: data) {
                    DispatchQueue.main.async {
                        self.updateUI(with: response)
                    }
                } else {
                    DispatchQueue.main.async {
                        if let button = self.statusItem.button {
                            button.title = " Limits: Err"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if let button = self.statusItem.button {
                        button.title = " Limits: Err"
                    }
                }
            }
        }
    }

    func updateUI(with res: LimitResponse) {
        var gShort = "N/A"
        var cShort = "N/A"
        
        if let groups = res.groups {
            for g in groups {
                let name = (g.name ?? "").lowercased()
                if name.contains("gemini") {
                    if let b = g.buckets?.first(where: { $0.window == "5h" }) {
                        let pct = Int(round((b.remainingFraction ?? 0) * 100))
                        let reset = b.resetsIn ?? "N/A"
                        gShort = "\(pct)% (\(reset))"
                    }
                } else if name.contains("claude") || name.contains("gpt") {
                    if let b = g.buckets?.first(where: { $0.window == "weekly" }) {
                        let pct = Int(round((b.remainingFraction ?? 0) * 100))
                        let reset = b.resetsIn ?? "N/A"
                        cShort = "\(pct)% (\(reset))"
                    }
                }
            }
        }
        
        // Status bar button title
        if let button = statusItem.button {
            button.title = " G: \(gShort) | C: \(cShort)"
        }
        
        // Build Dropdown Menu
        let menu = NSMenu()
        
        // Account & Plan Header
        if let email = res.email {
            let emailItem = NSMenuItem(title: "👤 \(email)", action: nil, keyEquivalent: "")
            emailItem.isEnabled = false
            menu.addItem(emailItem)
        }
        
        let planName = res.tier?.name ?? "Google AI Pro"
        let planItem = NSMenuItem(title: "✦ Plan: \(planName)", action: nil, keyEquivalent: "")
        planItem.isEnabled = false
        menu.addItem(planItem)
        
        let credits = res.availableCredits ?? 0
        let creditsItem = NSMenuItem(title: "💰 Available AI Credits: \(credits)", action: nil, keyEquivalent: "")
        creditsItem.isEnabled = false
        menu.addItem(creditsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Render Groups and Buckets
        if let groups = res.groups {
            for (idx, g) in groups.enumerated() {
                let gTitle = NSMenuItem(title: g.name ?? "Quota Group", action: nil, keyEquivalent: "")
                gTitle.isEnabled = false
                menu.addItem(gTitle)
                
                if let buckets = g.buckets {
                    for b in buckets {
                        let bName = b.name ?? ""
                        let frac = b.remainingFraction ?? 0
                        let pct = Int(round(frac * 100))
                        let reset = b.resetsIn ?? "N/A"
                        let disabled = b.disabled ?? false
                        
                        let line: String
                        if disabled {
                            line = "   • \(bName): \(pct)% (Paused)"
                        } else {
                            line = "   • \(bName): \(pct)% (Resets in \(reset))"
                        }
                        
                        let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                        item.isEnabled = false
                        menu.addItem(item)
                    }
                }
                
                if idx < groups.count - 1 {
                    menu.addItem(NSMenuItem.separator())
                }
            }
        }
        
        menu.addItem(NSMenuItem.separator())
        
        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshClicked), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)
        
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
