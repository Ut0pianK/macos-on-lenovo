
import Foundation
import CoreAudio
import AppKit

let once = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Scripts/headset-ctia-once.sh").path
let safety = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 15) : 15
let q = DispatchQueue(label: "ctia")
func run(_ why: String) {
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/bash"); p.arguments = [once, why]
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    try? p.run(); p.waitUntilExit()
}
func fire(_ why: String) { for d in [0.3, 1.5, 4.0] { q.asyncAfter(deadline: .now() + d) { run(why) } } }

var watched: [AudioObjectID] = []
let devListener: AudioObjectPropertyListenerBlock = { _, _ in fire("event") }

func isRunning(_ d: AudioObjectID) -> Bool {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v: UInt32 = 0; var sz = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectGetPropertyData(d, &a, 0, nil, &sz, &v) == noErr && v != 0
}
var lastRunning = false
func runningChanged() {
    let r = watched.contains { isRunning($0) }
    if r == lastRunning { return }
    lastRunning = r
    if r { q.asyncAfter(deadline: .now() + 0.25) { if lastRunning { run("hp-high") } } } else { run("hp-low") }
}

let runListener: AudioObjectPropertyListenerBlock = { _, _ in
    runningChanged()
    for d in [30.3, 31.0, 32.5, 36.0] { q.asyncAfter(deadline: .now() + d) { run("idle") } }
}
func addr(_ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func rewatch() {
    var a1 = addr(kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput), a2 = addr(kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyScopeOutput)
    var a3 = addr(kAudioDevicePropertyDeviceIsRunningSomewhere)
    for d in watched { AudioObjectRemovePropertyListenerBlock(d, &a1, q, devListener); AudioObjectRemovePropertyListenerBlock(d, &a2, q, devListener); AudioObjectRemovePropertyListenerBlock(d, &a3, q, runListener) }
    watched.removeAll()
    var a = addr(kAudioHardwarePropertyDevices); var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return }
    for d in ids {
        AudioObjectAddPropertyListenerBlock(d, &a1, q, devListener); AudioObjectAddPropertyListenerBlock(d, &a2, q, devListener)
        AudioObjectAddPropertyListenerBlock(d, &a3, q, runListener)
        watched.append(d)
    }
    lastRunning = watched.contains { isRunning($0) }
    if !lastRunning { run("hp-low") }
}
var h1 = addr(kAudioHardwarePropertyDefaultOutputDevice), h2 = addr(kAudioHardwarePropertyDevices)
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &h1, q) { _, _ in fire("event") }
AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &h2, q) { _, _ in q.async { rewatch() }; fire("event") }
q.async { rewatch() }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in fire("wake") }
NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: nil) { _ in fire("wake") }
let t = DispatchSource.makeTimerSource(queue: q)
t.schedule(deadline: .now() + 2, repeating: safety, leeway: .seconds(Int(max(1, safety / 5))))
t.setEventHandler { run("timer") }
t.resume()
RunLoop.main.run()
