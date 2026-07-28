import AppKit

let application = NSApplication.shared
let applicationDelegate = WhisperHotkeyApplicationDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.accessory)
application.run()
