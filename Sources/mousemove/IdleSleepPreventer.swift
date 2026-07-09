import Foundation
import IOKit.pwr_mgt

final class IdleSleepPreventer {
    private let reason: CFString
    private var assertionID = IOPMAssertionID(0)
    private var isActive = false

    init(reason: String) {
        self.reason = reason as CFString
    }

    func start() {
        guard !isActive else { return }

        var newAssertionID = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newAssertionID
        )

        guard result == kIOReturnSuccess else {
            print("Failed to prevent idle sleep: \(result)")
            return
        }

        assertionID = newAssertionID
        isActive = true
    }

    func stop() {
        guard isActive else { return }

        let result = IOPMAssertionRelease(assertionID)
        if result != kIOReturnSuccess {
            print("Failed to release idle sleep assertion: \(result)")
        }

        assertionID = IOPMAssertionID(0)
        isActive = false
    }

    deinit {
        stop()
    }
}
