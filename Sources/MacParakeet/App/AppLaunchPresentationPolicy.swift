import AppKit
import Carbon.HIToolbox

/// Decides whether startup presents the main window. Login-item startup is the
/// only background launch mode; all explicit Open and reopen paths are handled
/// by `AppWindowCoordinator` after startup.
enum AppLaunchPresentationPolicy {
    static func shouldOpenMainWindow(
        isLoginItemLaunch: Bool,
        onboardingCompleted: Bool
    ) -> Bool {
        !isLoginItemLaunch && onboardingCompleted
    }

    static func isCurrentLaunchFromLoginItem(
        event: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> Bool {
        guard event?.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event?
            .paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
            .enumCodeValue == OSType(keyAELaunchedAsLogInItem)
    }
}
