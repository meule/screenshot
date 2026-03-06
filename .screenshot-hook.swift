import Cocoa

let home = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
let pendingFile = "\(home)/Screenshots/.pending_url"
let bucket = "kostya-screenshots-eu"
let region = "eu-central-1"

func onScreenshotKey() {
    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy/MM/dd/HHmmss"
    let rand = String(format: "%04x", Int.random(in: 0..<65536))
    let key = "\(fmt.string(from: Date()))-\(rand).png"
    let url = "https://\(bucket).s3.\(region).amazonaws.com/\(key)"

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url, forType: .string)
    try? url.write(toFile: pendingFile, atomically: true, encoding: .utf8)
}

// Virtual key codes: 3=20, 4=21, 5=23, 6=22
let screenshotKeys: Set<Int64> = [20, 21, 23, 22]

guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
    callback: { _, _, event, _ in
        let flags = event.flags
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        if flags.contains(.maskCommand) && flags.contains(.maskShift) && screenshotKeys.contains(key) {
            DispatchQueue.main.async(execute: onScreenshotKey)
        }
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    fputs("screenshot-hook: CGEventTap failed — grant Input Monitoring in System Settings → Privacy & Security\n", stderr)
    exit(1)
}

let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
RunLoop.main.run()
