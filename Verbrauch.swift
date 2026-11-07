// Verbrauch – Menüleisten-App: zeigt, welche Programme Energie, CPU und RAM verbrauchen,
// und erlaubt, sie direkt aus dem Menü zu beenden. Ergänzung zum Apple-Batteriemenü,
// das nur „Erheblicher Energieverbrauch“ ohne Zahlen und ohne Beenden zeigt.
import Cocoa
import ServiceManagement

struct Proc { let pid: Int32; let cpu: Double; let memMB: Double; let power: Double; let path: String; let uid: uid_t; let cmd: String }

struct AppGroup {
    let name: String
    let app: NSRunningApplication?     // nil = kein GUI-Programm (Hintergrundprozess)
    var pids: [Int32] = []
    var cpu = 0.0, memMB = 0.0, power = 0.0
    var ownUser = true                 // alle Prozesse gehören dem angemeldeten Benutzer
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let menu = NSMenu()
    var timer: Timer?
    var groups: [AppGroup] = []
    var sysLine = "Messe …"
    var sampling = false
    var menuOpen = false
    let loginItem = NSMenuItem(title: "Bei Anmeldung starten", action: #selector(toggleLogin), keyEquivalent: "")
    let sortItem = NSMenuItem(title: "Nach CPU sortieren", action: #selector(toggleSort), keyEquivalent: "")
    var sortByCPU: Bool {
        get { UserDefaults.standard.bool(forKey: "sortCPU") }
        set { UserDefaults.standard.set(newValue, forKey: "sortCPU") }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.autosaveName = "Verbrauch"
        item.button?.image = NSImage(systemSymbolName: "gauge.with.needle", accessibilityDescription: "Verbrauch")
        item.button?.imagePosition = .imageLeading
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        menu.delegate = self
        item.menu = menu
        loginItem.target = self
        sortItem.target = self
        if !UserDefaults.standard.bool(forKey: "autostartEingerichtet") {
            UserDefaults.standard.set(true, forKey: "autostartEingerichtet")
            try? SMAppService.mainApp.register()
        }
        rebuildMenu()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sample() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    // MARK: Messung

    func sample() {
        guard !sampling else { return }
        sampling = true
        DispatchQueue.global(qos: .utility).async {
            let procs = self.readTop()
            let g = self.group(procs)
            let sys = self.systemLine()
            DispatchQueue.main.async {
                self.groups = g
                self.sysLine = sys
                self.sampling = false
                // Summe aller Prozesse geteilt durch Kerne = Gesamtauslastung wie in der Aktivitätsanzeige
                let cpu = g.reduce(0) { $0 + $1.cpu } / Double(ProcessInfo.processInfo.activeProcessorCount)
                self.item.button?.title = String(format: " %.0f %%", min(cpu, 100))
                // Bei offenem Menü nie umbauen: sonst verrutschen die Zeilen unter dem Mauszeiger
                // und man beendet das falsche Programm. Neue Werte kommen beim nächsten Öffnen.
                if !self.menuOpen { self.rebuildMenu() }
            }
        }
    }

    // top liefert dieselbe Energiespalte (POWER) wie die Aktivitätsanzeige. Zwei Durchläufe,
    // weil der erste keine CPU-Differenz kennt; nur der zweite wird ausgewertet.
    func readTop() -> [Proc] {
        let out = run("/usr/bin/top", ["-l", "2", "-s", "1", "-stats", "pid,cpu,mem,power,uid,ppid,command"])
        guard let second = out.components(separatedBy: "\nProcesses:").last else { return [] }
        var res: [Proc] = []
        for line in second.components(separatedBy: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 7, let pid = Int32(f[0]), let cpu = Double(f[1]), let pw = Double(f[3]), let uid = UInt32(f[4]) else { continue }
            guard pid != ProcessInfo.processInfo.processIdentifier else { continue }
            if f[5] == String(ProcessInfo.processInfo.processIdentifier) { continue }   // eigener Messprozess (top)
            res.append(Proc(pid: pid, cpu: cpu, memMB: memMB(f[2]), power: pw, path: pidPath(pid), uid: uid, cmd: f[6...].joined(separator: " ")))
        }
        return res
    }

    func memMB(_ s: String) -> Double {
        var t = s
        if t.hasSuffix("+") || t.hasSuffix("-") { t.removeLast() }
        guard let unit = t.last, let v = Double(t.dropLast()) else { return 0 }
        switch unit { case "K": return v / 1024; case "M": return v; case "G": return v * 1024; case "B": return v / 1048576; default: return 0 }
    }

    func pidPath(_ pid: Int32) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : ""
    }

    // Prozesse den Programmen zuordnen: alles, was im Bundle-Ordner eines laufenden Programms
    // liegt (Helper, Renderer, …), zählt zu diesem Programm. Der Rest wird nach Namen gebündelt.
    func group(_ procs: [Proc]) -> [AppGroup] {
        let me = getuid()
        var apps: [(prefix: String, app: NSRunningApplication)] = []
        for a in NSWorkspace.shared.runningApplications where a.activationPolicy != .prohibited {
            if let u = a.bundleURL { apps.append((u.path + "/", a)) }
        }
        // Kürzeste Pfade zuerst: Helper-Bundles (z. B. Claude Helper.app in Claude.app) zählen zum Hauptprogramm
        apps.sort { $0.prefix.count < $1.prefix.count }
        var dict: [String: AppGroup] = [:]
        for p in procs {
            var key: String, name: String, app: NSRunningApplication? = nil
            if let hit = apps.first(where: { p.path.hasPrefix($0.prefix) }) {
                app = hit.app; name = hit.app.localizedName ?? hit.prefix; key = "app:" + hit.prefix
            } else if let a = NSRunningApplication(processIdentifier: p.pid), a.activationPolicy != .prohibited {
                app = a; name = a.localizedName ?? "?"; key = "pid:\(p.pid)"
            } else if p.path.contains("/Claude/claude-code/") {
                name = "Claude Code"; key = "sys:claudecode"
            } else {
                name = (p.path as NSString).lastPathComponent
                if name.isEmpty { name = p.cmd.isEmpty ? "pid \(p.pid)" : p.cmd }
                if name.hasPrefix("node") || name == "npm" { name = "node (Hintergrund)" }
                key = "sys:" + name
            }
            var g = dict[key] ?? AppGroup(name: name, app: app)
            g.pids.append(p.pid); g.cpu += p.cpu; g.memMB += p.memMB; g.power += p.power
            if p.uid != me { g.ownUser = false }
            dict[key] = g
        }
        return Array(dict.values)
    }

    func systemLine() -> String {
        let m = run("/usr/sbin/sysctl", ["-n", "vm.swapusage"])
        var swap = ""
        if let r = m.range(of: "used = "), let e = m[r.upperBound...].firstIndex(of: " ") {
            swap = "Swap " + String(m[r.upperBound..<e]).replacingOccurrences(of: ".00", with: "")
        }
        let vm = run("/usr/bin/vm_stat", [])
        var freeMB = 0.0
        for l in vm.components(separatedBy: "\n") where l.hasPrefix("Pages free:") || l.hasPrefix("Pages inactive:") {
            let n = Double(l.split(separator: ":")[1].trimmingCharacters(in: CharacterSet(charactersIn: " .\t"))) ?? 0
            freeMB += n * 16384 / 1048576
        }
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1073741824
        return String(format: "RAM %.1f GB belegt von %.0f GB · %@", total - freeMB / 1024, total, swap)
    }

    func run(_ path: String, _ args: [String]) -> String {
        let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    // MARK: Menü

    func menuWillOpen(_ menu: NSMenu) { menuOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false; rebuildMenu() }

    func fmtMem(_ mb: Double) -> String { mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb) }

    func row(_ g: AppGroup) -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.tabStops = [NSTextTab(textAlignment: .right, location: 250), NSTextTab(textAlignment: .right, location: 320),
                       NSTextTab(textAlignment: .right, location: 390)]
        ps.lineBreakMode = .byTruncatingTail
        let font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        let s = NSMutableAttributedString(string: g.name + "\t", attributes: [.font: font, .paragraphStyle: ps])
        let hot = g.power >= 20
        let dim = NSColor.secondaryLabelColor
        let vals = [String(format: "%.0f", g.power), String(format: "%.0f %%", g.cpu), fmtMem(g.memMB)]
        for (i, v) in vals.enumerated() {
            s.append(NSAttributedString(string: v + (i < 2 ? "\t" : ""),
                                        attributes: [.font: font, .paragraphStyle: ps,
                                                     .foregroundColor: (i == 0 && hot) ? NSColor.systemOrange : dim]))
        }
        return s
    }

    func rebuildMenu() {
        menu.removeAllItems()
        let head = NSMenuItem(title: sysLine, action: nil, keyEquivalent: ""); head.isEnabled = false
        menu.addItem(head)
        let ps = NSMutableParagraphStyle()
        ps.tabStops = [NSTextTab(textAlignment: .right, location: 250), NSTextTab(textAlignment: .right, location: 320),
                       NSTextTab(textAlignment: .right, location: 390)]
        let cols = NSMenuItem(title: "", action: nil, keyEquivalent: ""); cols.isEnabled = false
        cols.attributedTitle = NSAttributedString(string: "Programm\tEnergie\tCPU\tRAM",
            attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .paragraphStyle: ps,
                         .foregroundColor: NSColor.secondaryLabelColor])
        menu.addItem(cols)
        menu.addItem(.separator())
        let sorted = groups.sorted { sortByCPU ? $0.cpu > $1.cpu : $0.power > $1.power }
        var shown = 0
        for g in sorted {
            // Nur, was spürbar verbraucht: GUI-Programme immer, Hintergrund nur ab 1 % oder 1 Energie
            let relevant = g.app != nil || g.cpu >= 1 || g.power >= 1 || g.memMB >= 200
            guard relevant, shown < 25 else { continue }
            shown += 1
            let mi = NSMenuItem(title: g.name, action: nil, keyEquivalent: "")
            mi.attributedTitle = row(g)
            if let a = g.app, let ic = a.icon { ic.size = NSSize(width: 16, height: 16); mi.image = ic }
            else { mi.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil) }
            let sub = NSMenu()
            let info = NSMenuItem(title: "\(g.pids.count) Prozess\(g.pids.count == 1 ? "" : "e") · PID \(g.pids.prefix(4).map(String.init).joined(separator: ", "))\(g.pids.count > 4 ? " …" : "")", action: nil, keyEquivalent: "")
            info.isEnabled = false; sub.addItem(info)
            sub.addItem(.separator())
            if g.app != nil {
                sub.addItem(mk("Beenden", #selector(quitApp(_:)), g))
                sub.addItem(mk("Sofort beenden (erzwingen)", #selector(forceQuit(_:)), g))
            } else if g.ownUser {
                sub.addItem(mk("Prozess beenden", #selector(quitApp(_:)), g))
                sub.addItem(mk("Sofort beenden (erzwingen)", #selector(forceQuit(_:)), g))
            } else {
                let x = NSMenuItem(title: "Systemprozess – nicht beendbar", action: nil, keyEquivalent: ""); x.isEnabled = false
                sub.addItem(x)
            }
            if g.app != nil { sub.addItem(mk("Im Vordergrund zeigen", #selector(showApp(_:)), g)) }
            mi.submenu = sub
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        sortItem.state = sortByCPU ? .on : .off
        menu.addItem(sortItem)
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)
        let act = NSMenuItem(title: "Aktivitätsanzeige öffnen", action: #selector(openActivity), keyEquivalent: ""); act.target = self
        menu.addItem(act)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Verbrauch beenden", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
    }

    func mk(_ t: String, _ sel: Selector, _ g: AppGroup) -> NSMenuItem {
        let m = NSMenuItem(title: t, action: sel, keyEquivalent: ""); m.target = self; m.representedObject = g.pids; return m
    }

    // MARK: Aktionen

    @objc func quitApp(_ s: NSMenuItem) {
        guard let pids = s.representedObject as? [Int32] else { return }
        var graceful = false
        for pid in pids { if let a = NSRunningApplication(processIdentifier: pid), a.terminate() { graceful = true } }
        if !graceful { for pid in pids { kill(pid, SIGTERM) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.sample() }
    }

    @objc func forceQuit(_ s: NSMenuItem) {
        guard let pids = s.representedObject as? [Int32] else { return }
        let a = NSAlert()
        a.messageText = "„\(s.parent?.title ?? "Programm")“ sofort beenden?"
        a.informativeText = "Ungesicherte Änderungen gehen verloren."
        a.addButton(withTitle: "Sofort beenden"); a.addButton(withTitle: "Abbrechen")
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        for pid in pids { kill(pid, SIGKILL) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.sample() }
    }

    @objc func showApp(_ s: NSMenuItem) {
        guard let pids = s.representedObject as? [Int32] else { return }
        for pid in pids { if let a = NSRunningApplication(processIdentifier: pid), a.activationPolicy == .regular {
            a.activate(options: [.activateIgnoringOtherApps]); return } }
    }

    @objc func openActivity() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"),
                                           configuration: .init(), completionHandler: nil)
    }

    @objc func toggleSort() { sortByCPU.toggle(); rebuildMenu() }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do { if svc.status == .enabled { try svc.unregister() } else { try svc.register() } }
        catch {
            let a = NSAlert(); a.messageText = "Autostart ließ sich nicht ändern"
            a.informativeText = "\(error.localizedDescription)\n\nTipp: Verbrauch erst in den Ordner „Programme“ ziehen."
            a.runModal()
        }
        loginItem.state = svc.status == .enabled ? .on : .off
    }
}

let me = ProcessInfo.processInfo.processIdentifier
if NSRunningApplication.runningApplications(withBundleIdentifier: "de.openkairo.verbrauch")
    .contains(where: { $0.processIdentifier != me }) { exit(0) }

// Erster Start: rechts neben NetSpeed, nahe am Batteriesymbol. Danach per ⌘-Ziehen verschiebbar.
let posKey = "NSStatusItem Preferred Position Verbrauch"
if UserDefaults.standard.object(forKey: posKey) == nil {
    UserDefaults.standard.set(120.0, forKey: posKey)
    UserDefaults.standard.set(true, forKey: "NSStatusItem Visible Verbrauch")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
