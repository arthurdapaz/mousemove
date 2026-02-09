import Foundation

let activity = ProcessInfo.processInfo.beginActivity(
    options: [
        .automaticTerminationDisabled,
        .idleSystemSleepDisabled,
        .idleDisplaySleepDisabled],
    reason: "Timer needs to run"
)

let arg = CommandLine.arguments.dropFirst().first
let animType = arg != nil ? MouseMove.AnimationType.from(arg!) : MouseMove.AnimationType.circle
let mouse = MouseMove(animation: animType)

print("Press CTRL+C or kill the process to exit. pid:", getpid())

while true && RunLoop.current.run(mode: .default, before: .distantFuture) { }
