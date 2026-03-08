import Foundation

@main
struct GhostMouse {
    static func main() async {
        let _ = MouseMove()
        // ~584 anos — Suspende cooperativamente, cancellable, sem warnings
        try? await Task.sleep(nanoseconds: .max)
    }
}
