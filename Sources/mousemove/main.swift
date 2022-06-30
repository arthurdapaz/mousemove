import Foundation

let activity = ProcessInfo.processInfo.beginActivity(
    options: [
        .automaticTerminationDisabled,
        .idleSystemSleepDisabled,
        .idleDisplaySleepDisabled],
    reason: "Timer needs to run"
)

let mouse = MouseMove()
mouse.circulate()

print("Press CTRL+C or kill the process to exit. pid:", getpid())

while true && RunLoop.current.run(mode: .default, before: .distantFuture) { }
