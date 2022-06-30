import Foundation

let activity = ProcessInfo.processInfo.beginActivity(
    options: [
        .automaticTerminationDisabled,
        .idleSystemSleepDisabled,
        .idleDisplaySleepDisabled],
    reason: "Timer needs to run"
)

DispatchQueue.global(qos: .utility).async {
    let mouse = MouseMove()
    DispatchQueue.main.async {
        mouse.circulate()
    }
}

print("You will never be idle again...")
print("Press CTRL+C or kill the process to exit. pid:", getpid())

while true && RunLoop.current.run(mode: .default, before: .distantFuture) { }
