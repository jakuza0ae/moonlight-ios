# iPad Desktop Second-Monitor UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an iOS 12-safe, landscape-first second-monitor toolbar, settings panel, and keyboard modifier path without changing the existing game storyboard or game-mode behavior.

**Architecture:** Keep `iPad.storyboard` and the existing reveal/navigation flow intact. `StreamView` owns a programmatic desktop toolbar and keyboard entry only for `LMStreamModeSecondMonitor`; `StreamFrameViewController` owns the toolbar callbacks, Auto Layout stream bounds, reconnect lifecycle, and diagnostics presentation. `SettingsViewController` adds a programmatic second-monitor profile panel reachable from the existing settings navigation while leaving legacy game controls in place. The active profile choice is explicit so a stored desktop profile cannot silently convert ordinary game launches.

**Tech Stack:** Objective-C, UIKit available on iOS 12, XCTest, existing `LMStreamProfile`, `LMReconnectStateMachine`, `StreamConfiguration`, and Limelight keyboard event APIs.

## Global Constraints

- iOS deployment target remains 12.0.
- The default second-monitor stream remains H.264, 1280x720, 30 FPS, conservative bitrate, native touch, disabled audio, and reconnect enabled.
- Unsupported iPad Air codec, HDR, refresh-rate, and resolution values are omitted from the second-monitor panel rather than shown disabled.
- The second-monitor toolbar is hidden by default and must not intercept ordinary video touches while hidden.
- Every keyboard modifier/function press must have a matching release when the action ends, keyboard editing is dismissed, the stream view leaves the window, or the connection is stopped.
- Game mode keeps the existing storyboard controls, gamepad overlays, settings, and input path.
- New UIKit APIs must be available on iOS 12; no pointer, Pencil, SwiftUI, scene, or modern keyboard APIs are introduced.
- New user-facing strings use the repository's existing direct `NSString` convention; no new localization framework is introduced.
- Xcode build/test commands are documented and attempted, but an unavailable macOS/Xcode toolchain is reported rather than hidden.

---

## File Map

- `Limelight/Input/KeyboardInputField.h`: declares `LMKeyboardAction` and the held-action/release interface.
- `Limelight/Input/KeyboardInputField.m`: tracks modifier state and provides the iOS 12-safe action callback boundary.
- `Limelight/Input/StreamView.h`: exposes desktop-toolbar state, input-mode updates, and keyboard cleanup to the stream controller.
- `Limelight/Input/StreamView.m`: builds the hidden-by-default toolbar, routes toolbar actions, installs the keyboard accessory, and releases keys during teardown.
- `Limelight/Input/AbsoluteTouchHandler.h`: exposes runtime input-mode changes needed by the toolbar selector.
- `Limelight/Input/AbsoluteTouchHandler.m`: changes the mode used by subsequent touch events after toolbar selection.
- `Limelight/Input/OnScreenControls.m`: treats second-monitor profiles as permanently off for gamepad overlay drawing and touch interception.
- `Limelight/ViewControllers/StreamFrameViewController.m`: uses constraints for second-monitor stream bounds, handles toolbar reconnect/diagnostics callbacks, forces landscape-first orientation, and cleans keyboard actions on disconnect.
- `Limelight/ViewControllers/SettingsViewController.m`: adds a programmatic second-monitor profile entry point and panel, loads Task 6 defaults/profile values, filters capabilities, and saves the explicit active-mode choice.
- `Limelight/ViewControllers/MainFrameViewController.m`: applies the stored second-monitor profile only when the user selected desktop mode; otherwise preserves the existing game configuration path.
- `LimelightTests/TouchInputTests.m`: contains pure keyboard action, desktop-mode layout/overlay, profile-selection, and settings capability smoke checks.
- `docs/superpowers/plans/2026-08-13-task-7-ipad-desktop-ui.md`: records this implementation plan.
- `.superpowers/sdd/2026-08-12-second-monitor/task-7-report.md`: records implementation, verification, commit hashes, unavailable-toolchain status, and concerns.

## Interfaces

The keyboard action declaration is exactly:

```objc
typedef NS_ENUM(NSInteger, LMKeyboardAction) {
    LMKeyboardActionEscape,
    LMKeyboardActionTab,
    LMKeyboardActionControl,
    LMKeyboardActionShift,
    LMKeyboardActionAlt,
    LMKeyboardActionWindows,
    LMKeyboardActionDelete,
};
```

`KeyboardInputField` exposes:

```objc
typedef void (^LMKeyboardActionHandler)(LMKeyboardAction action, BOOL pressed);

@property (nonatomic, copy, nullable) LMKeyboardActionHandler keyboardActionHandler;
- (void)sendKeyboardAction:(LMKeyboardAction)action pressed:(BOOL)pressed;
- (void)releaseAllKeyboardActions;
- (NSSet<NSNumber *> *)activeKeyboardActions;
```

`StreamView` exposes:

```objc
- (void)setDesktopToolbarDelegate:(id)delegate;
- (BOOL)isDesktopToolbarVisible;
- (void)setDesktopToolbarVisible:(BOOL)visible animated:(BOOL)animated;
- (void)setInputMode:(LMInputMode)inputMode;
- (void)releaseKeyboardActions;
```

The existing `UserInteractionDelegate` gains optional desktop callbacks:

```objc
- (void)streamViewDidRequestReconnect:(StreamView *)streamView;
- (void)streamViewDidRequestDiagnostics:(StreamView *)streamView;
```

`AbsoluteTouchHandler` exposes `-setInputMode:`. The method cancels active contacts before changing routing, so a toolbar mode switch cannot leave native pointers or compatibility mouse buttons held.

### Task 1: Add Failing Pure Behavior and Layout Checks

**Files:**
- Modify: `LimelightTests/TouchInputTests.m`
- Modify: `Limelight/Input/KeyboardInputField.h`
- Modify: `Limelight/Input/StreamView.h`

**Interfaces:**
- Tests use `LMKeyboardAction`, `activeKeyboardActions`, `sendKeyboardAction:pressed:`, and `releaseAllKeyboardActions`.
- Tests use a pure `LMStreamProfile` second-monitor default and a public `OnScreenControls` desktop predicate.

- [ ] **Step 1: Write failing keyboard action tests.** Add tests that press Control and Shift, assert both are present in `activeKeyboardActions`, release Control, assert only Shift remains, then call `releaseAllKeyboardActions` and assert the set is empty. Add a test that pressing Escape or Delete does not leave a held modifier in the set.
- [ ] **Step 2: Write failing desktop profile/layout checks.** Add tests that assert the default profile is landscape (`width > height`), second-monitor mode is reconnect-enabled/native-touch, and the new stream-view toolbar visibility contract starts false. Add a test that a second-monitor configuration has `gamepadMask == 0` and cannot request on-screen controls.
- [ ] **Step 3: Write failing profile-selection checks.** Add a test around the new pure mode-selection helper or equivalent method showing that a saved second-monitor profile is ignored when `Moonlight.SecondMonitor.Active` is false and applied when it is true.
- [ ] **Step 4: Run the focused tests.** Run `xcodebuild test -project Moonlight.xcodeproj -scheme Moonlight -destination 'platform=iOS Simulator,name=iPad (5th generation)' -only-testing:MoonlightTests/TouchInputTests` when Xcode is available. Confirm the new symbols/checks fail before implementation; if Xcode is unavailable, record the exact command failure in the report and continue with static checks.

### Task 2: Implement Keyboard Action Ownership and Release Guarantees

**Files:**
- Modify: `Limelight/Input/KeyboardInputField.h`
- Modify: `Limelight/Input/KeyboardInputField.m`
- Modify: `Limelight/Input/StreamView.m`
- Modify: `Limelight/ViewControllers/StreamFrameViewController.m`

**Interfaces:**
- `KeyboardInputField` owns only action state and invokes its callback; `StreamView` translates actions to Limelight key codes and sends down/up packets.
- Modifier actions are held until touch-up/cancel; Escape, Tab, and Delete send a down/up pair immediately.

- [ ] **Step 1: Implement the action model minimally.** Add the exact enum to the header, retain a mutable set of currently pressed modifier actions, call the handler for every transition, ignore duplicate presses, and make `releaseAllKeyboardActions` send one release callback per held action before clearing the set.
- [ ] **Step 2: Add iOS 12-safe keyboard accessory controls.** Replace image-only assumptions in the existing accessory path with text `UIBarButtonItem` buttons labelled `Esc`, `Tab`, `Ctrl`, `Shift`, `Alt`, `Win`, and `Del`. Use `UIControlEventTouchDown`, `TouchUpInside`, `TouchUpOutside`, and `TouchCancel` on custom buttons so dismissal cannot strand a modifier.
- [ ] **Step 3: Route actions through Limelight.** Map the enum to `0x1B`, `0x09`, `0xA2`, `0xA0`, `0xA4`, `0x5B`, and `0x2E`. Send `KEY_ACTION_DOWN` on press and `KEY_ACTION_UP` on release. Keep the existing text-field character and return-key behavior unchanged.
- [ ] **Step 4: Close every cleanup boundary.** Call `releaseAllKeyboardActions` from `textFieldDidEndEditing:`, `StreamView` `didMoveToWindow` when leaving the window, `cancelAllTouches`, `dealloc`, and the stream controller's stop/disconnect paths. Keep the operation on the main thread for UIKit state and dispatch only the existing Limelight sends as needed.
- [ ] **Step 5: Run the focused tests.** Verify the action-set tests pass and no existing touch tests regress.

### Task 3: Implement the Hidden Desktop Toolbar and Runtime Input Mode

**Files:**
- Modify: `Limelight/Input/AbsoluteTouchHandler.h`
- Modify: `Limelight/Input/AbsoluteTouchHandler.m`
- Modify: `Limelight/Input/StreamView.h`
- Modify: `Limelight/Input/StreamView.m`
- Modify: `Limelight/Input/OnScreenControls.m`

**Interfaces:**
- The toolbar is built only when `streamConfig.profile.mode == LMStreamModeSecondMonitor`.
- Toolbar controls are a visibility button/edge reveal, a three-segment input selector, keyboard, reconnect, diagnostics, and hide action.

- [ ] **Step 1: Add runtime input-mode mutation.** Implement `AbsoluteTouchHandler -setInputMode:` by cancelling active contacts/buttons and assigning the new mode. Add `StreamView -setInputMode:` to update the handler and `streamConfig.inputMode`.
- [ ] **Step 2: Add desktop-mode overlay gating.** Store a desktop-mode flag in `OnScreenControls`; initialize its level to off, make `show` a no-op for desktop mode, and make touch handlers return `NO` without drawing or intercepting gamepad controls. Keep every existing game-mode branch unchanged.
- [ ] **Step 3: Build the toolbar with Auto Layout.** Add an opaque, compact top bar with 44-point minimum controls, 52-point height, safe-area-aware margins, and a dark translucent background. Set `hidden` and `userInteractionEnabled` false during setup. Use a top-edge reveal gesture and a `Hide` button to toggle it without covering ordinary video touches.
- [ ] **Step 4: Wire callbacks.** The input selector calls `setInputMode:`. The keyboard button assigns the action handler and makes the hidden `KeyboardInputField` first responder. Reconnect and diagnostics call optional `UserInteractionDelegate` callbacks. The toolbar remains absent for game-mode streams.
- [ ] **Step 5: Run static checks and focused tests.** Check that no second-monitor path calls `show` for overlays, the toolbar starts hidden, and runtime mode switches cancel contacts before routing changes.

### Task 4: Integrate Stream Layout, Reconnect, Diagnostics, and Orientation

**Files:**
- Modify: `Limelight/ViewControllers/StreamFrameViewController.m`
- Modify: `Limelight/Input/StreamView.m` for the final delegate assignment and toolbar cleanup integration

**Interfaces:**
- `StreamFrameViewController` implements the optional toolbar callbacks and remains the owner of `_reconnectState`, `_reconnectConfig`, and `_streamMan`.

- [ ] **Step 1: Add Auto Layout only for second-monitor streams.** For `LMStreamModeSecondMonitor`, add `_streamView` with `translatesAutoresizingMaskIntoConstraints = NO` and pin it to the controller view's safe-area-aware edges. Keep the existing game-mode frame/scroll behavior untouched.
- [ ] **Step 2: Make the presentation landscape-first.** Return `UIInterfaceOrientationMaskLandscape` for second-monitor profiles and the existing orientation mask for game profiles. Do not use private orientation APIs or assume a scene delegate.
- [ ] **Step 3: Wire toolbar callbacks.** Reconnect calls `beginReconnect` when the profile allows it; diagnostics presents the existing stats string from `_streamMan` in an iOS 12-safe alert/text view and does not alter game mode.
- [ ] **Step 4: Guarantee disconnect cleanup.** Release keyboard actions and cancel touches before `_streamMan` termination, reconnect attempts, final termination alerts, parent removal, and application background handling.
- [ ] **Step 5: Run focused tests/static inspection.** Verify reconnect retains the copied profile, second-monitor layout uses constraints, and game mode still uses the existing frame path.

### Task 5: Add the Programmatic Second-Monitor Settings Panel

**Files:**
- Modify: `Limelight/ViewControllers/SettingsViewController.m`
- Modify: `Limelight/ViewControllers/MainFrameViewController.m`
- Test: `LimelightTests/TouchInputTests.m`

**Interfaces:**
- Keep `SettingsViewController` as the existing reveal rear controller. Add a `Desktop` navigation button that presents a private programmatic `LMSecondMonitorSettingsViewController` using a scroll view and vertical stack constraints.
- Persist the selected mode at `Moonlight.SecondMonitor.Active` and the active host at `Moonlight.SecondMonitor.HostUUID`.
- Load/save the profile through `DataManager getSecondMonitorProfileForHost:` and `saveSecondMonitorProfile:forHost:`; use `[LMStreamProfile defaultSecondMonitorProfile]` when the host has no saved profile.

- [ ] **Step 1: Add the failing panel smoke test contract.** Assert that iPad Air supported resolutions are `720p` by default and add only `1080p30` after explicit opt-in; assert that the panel's profile copy starts with the Task 6 defaults and that unsupported codec/HDR/120 FPS values are absent from its control data.
- [ ] **Step 2: Add the programmatic panel entry point.** Create the button/bar item in `SettingsViewController` without deleting or rearranging storyboard game controls. Present a form/page-style controller using `UIScrollView`, `UIStackView`, `UILabel`, `UISegmentedControl`, `UISlider`, and `UISwitch`, all available on iOS 12.
- [ ] **Step 3: Implement sections and loading.** Add Profile/Mode, Resolution, FPS, Bitrate, Audio, Input Mode, Gestures, Reconnect, and Diagnostics sections. Load values from the host profile, select only capability-supported values, show the current host/profile identity, and keep diagnostic overlay off by default.
- [ ] **Step 4: Implement save/validation.** Build a profile copy from controls, set H.264 and no HDR for iPad Air, set `experimental1080pEnabled` only when 1080p30 is selected, validate with `validateForCapabilityProfile:error:`, show the localized-safe `localizedDescription` on failure, save only with a non-empty host UUID, and update `Moonlight.SecondMonitor.Active` only after a valid save.
- [ ] **Step 5: Fix profile selection in the game launch path.** In `MainFrameViewController`, record the selected app host UUID for settings, load/apply the second-monitor profile only when `Moonlight.SecondMonitor.Active` is true, and otherwise execute the existing game settings path. A stored profile alone must not switch game mode.
- [ ] **Step 6: Run settings/profile tests and static checks.** Verify profile round-trip, default loading, explicit mode selection, omission of unsupported values, and unchanged game-mode configuration.

### Task 6: Verification, Report, and Implementation Commit

**Files:**
- Modify: `LimelightTests/TouchInputTests.m` only for final smoke coverage
- Create: `.superpowers/sdd/2026-08-12-second-monitor/task-7-report.md`

- [ ] **Step 1: Run available tests.** Run the focused XCTest command and the full test command if `xcodebuild` is available. Run repository static checks available on Windows, including `git diff --check`, plist/XML parsing if an installed parser exists, and source searches for unguarded modern APIs.
- [ ] **Step 2: Attempt the requested iOS verification honestly.** Attempt the iOS 12-compatible build/test command and record the exact Xcode/macOS unavailable error when applicable. Do not claim an iPad UI build or device smoke test passed without output.
- [ ] **Step 3: Review the complete diff.** Confirm only the focused controller/input/test files and plan/report documents changed, no storyboard navigation was rewritten, and no game-mode behavior was broadened to second-monitor mode.
- [ ] **Step 4: Write the report.** Include implementation summary, profile-selection behavior, keyboard release guarantees, static/test commands and results, exact Xcode-unavailable concern, and any remaining device-validation gaps.
- [ ] **Step 5: Commit the implementation.** Stage only Task 7 implementation/test/report files and commit with exactly `feat: add iPad desktop second monitor interface`.
- [ ] **Step 6: Verify the final commit.** Run `git status --short`, `git log --oneline -2`, and `git show --stat --oneline HEAD`; include the implementation and plan commit hashes in the final response.

## Verification Commands

```powershell
git diff --check
git status --short
xcodebuild test -project Moonlight.xcodeproj -scheme Moonlight -destination 'platform=iOS Simulator,name=iPad (5th generation)' -only-testing:MoonlightTests/TouchInputTests
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug -sdk iphonesimulator build
```

The final report must distinguish passing static checks from unavailable Xcode/iOS verification and must not claim an iPad Air device smoke test occurred.
