// logi-watch — event-driven half of logi-ondemand.
//
// launchd starts this only when a Logitech HID device appears (LaunchEvents /
// com.apple.iokit.matching) and at login. It starts Logi Options+, then sleeps on
// IOHIDManager callbacks until the last Logitech mouse/keyboard has been gone for
// the grace period, stops Options+ and exits. While nothing Logitech is connected,
// nothing runs at all.
//
// With --oneshot (light mode) it never stays running: it is started on login, on
// device arrival and on sleep/wake, starts or stops Options+, and exits at once.
//
// Debug overrides (env): LOGI_VENDOR_ID, LOGI_TRANSPORTS (regex), LOGI_GRACE_SECONDS.

import AppKit
import Foundation
import IOKit.hid
import XPC

let home = FileManager.default.homeDirectoryForCurrentUser.path
let stateDir = "\(home)/Library/Application Support/logi-ondemand"
let logFile = "\(home)/Library/Logs/logi-ondemand.log"
let configFile = "\(home)/.config/logi-ondemand/config"
let agentApp = "/Library/Application Support/Logitech.localized/LogiOptionsPlus/logioptionsplus_agent.app"
let agentBundleID = "com.logi.cp-dev-mgr"
let uiBundleID = "com.logi.optionsplus"

let env = ProcessInfo.processInfo.environment
let vendorID = Int(env["LOGI_VENDOR_ID"].map { $0.replacingOccurrences(of: "0x", with: "") } ?? "46d", radix: 16) ?? 0x46d
let transportPattern = env["LOGI_TRANSPORTS"] ?? "USB|Bluetooth"

func log(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    let line = "\(f.string(from: Date())) \(msg)\n"
    if let h = FileHandle(forWritingAtPath: logFile) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
}

func graceSeconds() -> TimeInterval {
    if let s = env["LOGI_GRACE_SECONDS"], let v = Double(s) { return v }
    var minutes = 10.0
    if let text = try? String(contentsOfFile: configFile, encoding: .utf8) {
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2, parts[0] == "GRACE_MINUTES",
               let v = Double(parts[1].split(separator: "#").first?.trimmingCharacters(in: .whitespaces) ?? "") {
                minutes = v
            }
        }
    }
    return minutes * 60
}

func mode() -> String {
    let m = (try? String(contentsOfFile: "\(stateDir)/mode", encoding: .utf8))?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (m?.isEmpty == false) ? m! : "auto"
}

// MARK: Options+ control

func running(_ bundleID: String) -> [NSRunningApplication] {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
}

func agentRunning() -> Bool { !running(agentBundleID).isEmpty }

func startAgent(_ reason: String) {
    guard !agentRunning() else { return }
    guard FileManager.default.fileExists(atPath: agentApp) else {
        log("Options+ agent not found at \(agentApp)"); return
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["-g", "-j", agentApp]
    try? p.run(); p.waitUntilExit()
    log("started Options+ (\(reason))")
}

func stopAgent(_ reason: String) {
    let apps = running(uiBundleID) + running(agentBundleID)
    guard !apps.isEmpty else { return }
    // The agent ignores SIGTERM but exits cleanly on SIGINT.
    let pids = apps.map { $0.processIdentifier }
    for p in pids { kill(p, SIGINT) }
    let alive = { pids.filter { kill($0, 0) == 0 } }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline, !alive().isEmpty { usleep(200_000) }
    for p in alive() { kill(p, SIGKILL) }
    log("stopped Options+ (\(reason))")
}

// MARK: Device tracking

final class Watcher {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    var devices = Set<IOHIDDevice>()
    var stopTimer: Timer?
    let grace = graceSeconds()

    func isRealDevice(_ d: IOHIDDevice) -> Bool {
        let transport = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? ""
        return transport.range(of: transportPattern, options: .regularExpression) != nil
    }

    func name(_ d: IOHIDDevice) -> String {
        IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "Logitech device"
    }

    func run() {
        let match: [String: Any] = [kIOHIDVendorIDKey: vendorID, kIOHIDPrimaryUsagePageKey: 1]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { ctx, _, _, device in
            Unmanaged<Watcher>.fromOpaque(ctx!).takeUnretainedValue().added(device)
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { ctx, _, _, device in
            Unmanaged<Watcher>.fromOpaque(ctx!).takeUnretainedValue().removed(device)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        // Monitoring only: no seize, and input-monitoring permission is not needed
        // to see device arrival/removal.
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        // Let the initial enumeration callbacks run, then decide.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        evaluate(initial: true)
        RunLoop.main.run()
    }

    func added(_ d: IOHIDDevice) {
        guard isRealDevice(d), !devices.contains(d) else { return }
        // One physical device often exposes several HID interfaces; log it once.
        if !devices.contains(where: { name($0) == name(d) }) { log("connected: \(name(d))") }
        devices.insert(d)
        evaluate(initial: false)
    }

    func removed(_ d: IOHIDDevice) {
        guard devices.remove(d) != nil else { return }
        if !devices.contains(where: { name($0) == name(d) }) { log("disconnected: \(name(d))") }
        evaluate(initial: false)
    }

    func evaluate(initial: Bool) {
        guard mode() == "auto" else { exit(0) }   // `logi on/off` took over
        if !devices.isEmpty {
            stopTimer?.invalidate(); stopTimer = nil
            startAgent("device connected")
            return
        }
        if !agentRunning() {
            if initial { exit(0) }               // nothing to do: sleep until launchd wakes us
            return scheduleStop()                // agent already gone; still exit after grace
        }
        scheduleStop()
    }

    func scheduleStop() {
        guard stopTimer == nil else { return }
        stopTimer = Timer.scheduledTimer(withTimeInterval: grace, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.stopTimer = nil
            guard self.devices.isEmpty, mode() == "auto" else { return }
            let g = self.grace >= 60 ? "\(Int(self.grace / 60))m" : "\(Int(self.grace))s"
            stopAgent("no device for \(g)")
            exit(0)
        }
    }
}

// MARK: main

// Light mode (--oneshot): no process stays around. Run on login, on device arrival
// and on every sleep/wake transition; start Options+ if a Logitech device is
// connected, otherwise stop it, then exit.
func connectedDeviceNames() -> [String] {
    let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let match: [String: Any] = [kIOHIDVendorIDKey: vendorID, kIOHIDPrimaryUsagePageKey: 1]
    IOHIDManagerSetDeviceMatching(m, match as CFDictionary)
    IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
    defer { IOHIDManagerClose(m, IOOptionBits(kIOHIDOptionsTypeNone)) }
    guard let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> else { return [] }
    return Set(set.compactMap { d -> String? in
        let t = IOHIDDeviceGetProperty(d, kIOHIDTransportKey as CFString) as? String ?? ""
        guard t.range(of: transportPattern, options: .regularExpression) != nil else { return nil }
        return IOHIDDeviceGetProperty(d, kIOHIDProductKey as CFString) as? String ?? "Logitech device"
    }).sorted()
}

var trigger = "login"

func oneshot() -> Never {
    // Give launchd a moment to hand over the triggering event.
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard mode() == "auto" else { exit(0) }
    let names = connectedDeviceNames()
    if !names.isEmpty {
        if !agentRunning() { log("connected: \(names.joined(separator: ", "))") }
        startAgent("device connected")
    } else if agentRunning() {
        stopAgent("no device at \(trigger)")
    }
    exit(0)
}

// MARK: main

try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

// launchd delivers its triggers as XPC events. They must be consumed, or launchd
// keeps relaunching this job for the same event.
xpc_set_event_stream_handler("com.apple.iokit.matching", DispatchQueue.main) { event in
    _ = xpc_dictionary_get_string(event, XPC_EVENT_KEY_NAME)
    trigger = "device event"
}
xpc_set_event_stream_handler("com.apple.notifyd.matching", DispatchQueue.main) { event in
    _ = xpc_dictionary_get_string(event, XPC_EVENT_KEY_NAME)
    trigger = "sleep/wake"
}

guard mode() == "auto" else { exit(0) }
if CommandLine.arguments.contains("--oneshot") { oneshot() }
Watcher().run()
