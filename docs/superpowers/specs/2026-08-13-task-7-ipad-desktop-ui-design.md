# Task 7 iPad Desktop UI Design

## Scope

Task 7 adds a second-monitor-only desktop surface to the existing Moonlight iPad app. The existing storyboard, reveal controller, navigation, and game settings remain in place. New behavior is programmatic and gated by `LMStreamModeSecondMonitor`.

## Stream Surface

`StreamFrameViewController` remains the stream owner. For second-monitor profiles it pins `StreamView` with Auto Layout, presents the stream in landscape, and assigns the controller as the optional toolbar delegate. Game-mode streams keep their existing frame and scroll behavior.

`StreamView` creates a compact toolbar only for second-monitor profiles. It uses iOS 12 UIKit controls, starts hidden, and has a top-edge reveal gesture plus an explicit hide action. The visible toolbar contains an input-mode selector, keyboard button, reconnect button, diagnostics button, and visibility control. The hidden toolbar has no hit testing, so ordinary video touches are not blocked.

`OnScreenControls` receives the second-monitor profile but remains off and does not draw or intercept gamepad overlays. This is a presentation/input-overlay decision only; game-mode streams continue to use their current configuration.

## Keyboard Actions

`KeyboardInputField` owns a small action-state model using the required `LMKeyboardAction` enum. Modifier buttons send down on touch-down and up on touch-up/cancel. Function keys send a complete down/up pair. `releaseAllKeyboardActions` is called from editing dismissal, stream-view removal, touch cancellation, disconnect, reconnect, and deallocation. Limelight key events remain sent by `StreamView`, preserving the existing iOS 12 text-entry path.

## Settings and Profile Selection

The existing settings controller gains a programmatic `Desktop` entry point. It presents a constrained scroll/stack panel with profile/mode, resolution, FPS, bitrate, audio, input mode, gestures, reconnect, and diagnostics sections. It loads the per-host second-monitor profile through `DataManager`, falling back to `defaultSecondMonitorProfile` when no profile exists. iPad Air controls expose only supported values, with explicit opt-in for 1080p30.

The panel persists the profile through the existing `LMStreamProfileStore` path and persists an explicit active-mode flag. `MainFrameViewController` uses the second-monitor profile only when that flag is enabled. A stored profile by itself never changes an ordinary game launch into second-monitor mode.

## Diagnostics and Failure Handling

The diagnostics button presents the existing stream statistics text and does not create a second metrics pipeline. Reconnect delegates to the existing `LMReconnectStateMachine`; toolbar actions cancel active touches and held keyboard actions before retry. Profile validation errors are shown through `localizedDescription`. No unsupported option is presented as a disabled choice.

## Testing

Pure XCTest coverage verifies keyboard action state/release behavior, landscape profile defaults, overlay suppression, explicit profile-mode selection, and iPad Air supported-resolution filtering. Static checks verify XML/plist integrity, whitespace, iOS 12-safe API usage, and preservation of the existing storyboard. Xcode/iOS tests are attempted but are reported unavailable when run outside macOS/Xcode.

## Localization Convention

New labels follow the repository's existing direct `NSString` literals. No non-ASCII strings or new localization mechanism are introduced; the report records this convention for later localization work.
