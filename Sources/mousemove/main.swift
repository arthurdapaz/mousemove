import Foundation

let activity = ProcessInfo.processInfo.beginActivity(
    options: [
        .automaticTerminationDisabled,
        .idleSystemSleepDisabled,
        .idleDisplaySleepDisabled],
    reason: "Timer needs to run"
)

let mouse = MouseMove()
// `MouseMove` schedules its own timer and runs animations on a background queue.
// Do not call `circulate()` here to avoid blocking the main thread.

print("Press CTRL+C or kill the process to exit. pid:", getpid())

while true && RunLoop.current.run(mode: .default, before: .distantFuture) { }
