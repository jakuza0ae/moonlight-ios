# Second Monitor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a reliable VDD-backed second-monitor mode across the Moonlight iOS fork and Sunshine fork for iPad Air 1 on iOS 12.5.8.

**Architecture:** Keep the existing Moonlight streaming and VideoToolbox pipeline, add a device/profile-aware desktop mode and native touch input, and harden Sunshine's existing display-device lifecycle so a selected VDD is stable across enumeration, disconnect, and reconnect. The two repositories remain independently buildable; integration uses the existing Moonlight protocol plus small authenticated Sunshine APIs only where existing protocol data is insufficient.

**Tech Stack:** Objective-C, Swift 4/5, UIKit/iOS 12, VideoToolbox, Core Data, C/C++23, CMake, Qt6, DXGI Desktop Duplication, Windows Synthetic Pointer Input, libdisplaydevice, GoogleTest.

## Global Constraints

- iOS deployment target remains 12.0.
- Baseline stream is H.264, 1280x720, 30 FPS, with conservative bitrate.
- HEVC, AV1, HDR, 4K, 120 FPS, modern pointer APIs, Pencil APIs, and Sidecar-like system display extensions are deferred.
- The target host is Windows 11 IoT LTSC build 26100 on Ryzen 7 4700U, AMD integrated graphics, 16 GB RAM, Wi-Fi 5, and VDD 11.30.4.434.
- Second-monitor mode must never silently fall back from the selected VDD to a physical display.
- Native touch is the default; mouse compatibility is explicit and selectable.
- Jailbreak integration is optional and cannot be a dependency of the core app or protocol.
- Do not modify or replace the VDD kernel driver in the first implementation.

---

## File Map

### Moonlight iOS

- `Limelight/Input/AbsoluteTouchHandler.m`: native touch lifecycle and compatibility mapping.
- `Limelight/Input/StreamView.m`: touch surface coordinate conversion, input routing, toolbar ownership, and keyboard entry.
- `Limelight/Input/RelativeTouchHandler.m`: configurable mouse fallback gestures and sensitivity.
- `Limelight/Input/KeyboardInputField.m`: iOS 12 keyboard capture and modifier toolbar.
- `Limelight/Database/TemporarySettings.h`: in-memory second-monitor settings contract.
- `Limelight/Database/TemporarySettings.m`: settings serialization and defaults.
- `Limelight/Database/DataManager.h`: persistence API for per-host/profile settings.
- `Limelight/Database/DataManager.m`: Core Data read/write implementation.
- `Limelight/Stream/StreamConfiguration.h`: stream profile values passed to the common library.
- `Limelight/Stream/StreamConfiguration.m`: profile defaults and validation.
- `Limelight/Stream/StreamManager.m`: desktop launch, reconnect, and diagnostics lifecycle.
- `Limelight/ViewControllers/SettingsViewController.m`: capability-filtered settings.
- `Limelight/ViewControllers/StreamFrameViewController.m`: stream state, reconnect UI, and teardown.
- `iPad.storyboard`: legacy layout surface to be replaced only after behavior is stable.
- `Limelight/Limelight-Info.plist`: iOS 12-safe capabilities and transport policy.

### Sunshine

- `src/config.h`: display policy and profile configuration types.
- `src/config.cpp`: defaults and serialization/parsing.
- `src/display_device.h`: stable VDD selection and lifecycle interface.
- `src/display_device.cpp`: device mapping, apply/retry, and restore behavior.
- `src/video.cpp`: output refresh and no-fallback capture selection.
- `src/nvhttp.cpp`: session display setup and retryable launch state.
- `src/stream.cpp`: final-session restore and disconnect handling.
- `src/input.cpp`: protocol touch normalization and dispatch.
- `src/platform/windows/input.cpp`: Windows synthetic touch injection.
- `src/platform/windows/display_base.cpp`: DXGI adapter/output selection.
- `src/confighttp.cpp`: authenticated diagnostics/profile endpoints and validation.
- `src/process.cpp`: per-profile environment and app launch values.
- `src_assets/common/assets/web/configs/tabs/audiovideo/DisplayOutputSelector.vue`: VDD selector UI.
- `tests/unit/test_display_device.cpp`: display policy and remapping tests.
- `tests/unit/test_mouse.cpp`: Windows coordinate and input cleanup coverage.
- `tests/integration/test_config_consistency.cpp`: configuration/UI consistency.
- `tests/integration/test_external_commands.cpp`: profile command validation.

---

## Task 1: Bootstrap Complete Sources and Build Gates

**Files:**
- Modify: `README.md` in `C:\Users\0ae\Desktop\moonlight`
- Modify: `README.md` in `C:\Users\0ae\Desktop\Sunshine`
- Modify: `AGENTS.md` in `C:\Users\0ae\Desktop\Sunshine` only if the reproducible Windows command differs from the current instructions
- Test: repository submodule status and platform build prerequisites

**Interfaces:**
- Produces a recursive checkout containing `moonlight-common-c`, `X1Kit`, `libdisplaydevice`, `inputtino`, and other Sunshine dependencies.
- Produces documented commands that fail clearly when Xcode/macOS or MSYS2/CMake dependencies are unavailable.

- [ ] **Step 1: Record the baseline.** Run `git status --short --branch`, `git submodule status --recursive`, and record the current commit IDs without changing user files.
- [ ] **Step 2: Initialize submodules.** Run `git submodule update --init --recursive` independently in both repositories and verify every required submodule has a commit ID without a leading `-`.
- [ ] **Step 3: Add a Moonlight checkout/build section.** Document the exact recursive clone/update command, the Xcode project, the iOS 12 target, and the fact that an iOS device build needs macOS/Xcode even when signing is handled separately.
- [ ] **Step 4: Add a Sunshine Windows build section.** Document MSYS2 UCRT64, CMake, C++23, Qt6, the selected build preset, and the command used for unit tests.
- [ ] **Step 5: Run the available static checks.** Verify submodule status, parse the Xcode project for deployment target `12.0`, configure Sunshine, and run the existing Sunshine unit tests if the local toolchain is present.
- [ ] **Step 6: Commit the bootstrap documentation.** Use separate commits in each repository so a build-fix can be reverted independently.

Expected evidence: no required submodule remains empty; the Moonlight project still declares iOS 12; Sunshine configuration either succeeds or reports the exact missing dependency.

## Task 2: Sunshine VDD-Only Selection and Stable Remapping

**Files:**
- Modify: `src/config.h` around display-device policy definitions
- Modify: `src/config.cpp` around display-device defaults and parsing
- Modify: `src/display_device.h`
- Modify: `src/display_device.cpp`
- Modify: `src/video.cpp`
- Modify: `src/nvhttp.cpp`
- Test: `tests/unit/test_display_device.cpp`

**Interfaces:**
- Add a persisted opt-in policy `vdd_only` alongside the existing `disabled`, `verify_only`, `ensure_active`, `ensure_primary`, and `ensure_only_display` policies.
- Add a stable selection result with `selected_device_id`, `mapped_display_name`, and an explicit `unavailable` state.
- `video::refresh_displays()` must preserve `unavailable` for a requested VDD rather than selecting index zero.

- [ ] **Step 1: Add failing policy tests.** Cover: selected VDD maps to its current `display_name`; a missing VDD returns `unavailable`; a changed physical display order does not change the selected GUID; an empty selection retains existing default behavior.
- [ ] **Step 2: Run the focused tests.** Run `ctest --test-dir build -R display_device --output-on-failure` or the repository's configured equivalent and verify the new tests fail before implementation.
- [ ] **Step 3: Implement policy parsing and serialization.** Add the opt-in policy with the existing config conventions and keep the current default behavior unchanged.
- [ ] **Step 4: Implement GUID remapping.** Resolve the saved VDD `device_id` after every enumeration and pass the resolved DXGI output name to capture selection.
- [ ] **Step 5: Remove the unsafe fallback for `vdd_only`.** Return a retryable display-unavailable result when the requested VDD is absent; do not substitute the first physical monitor.
- [ ] **Step 6: Run focused tests.** Verify policy, mapping, and fallback tests pass and existing display-device tests remain green.
- [ ] **Step 7: Commit.** Use `feat: add stable VDD-only display selection`.

## Task 3: Sunshine Display Lifecycle, Profiles, and Diagnostics

**Files:**
- Modify: `src/config.h`
- Modify: `src/config.cpp`
- Modify: `src/display_device.cpp`
- Modify: `src/nvhttp.cpp`
- Modify: `src/stream.cpp`
- Modify: `src/confighttp.cpp`
- Modify: `src/process.cpp`
- Modify: `src_assets/common/assets/web/configs/tabs/audiovideo/DisplayOutputSelector.vue`
- Test: `tests/unit/test_display_device.cpp`
- Test: `tests/integration/test_config_consistency.cpp`

**Interfaces:**
- Define a second-monitor profile with `device_id`, `resolution`, `fps`, `hdr`, `capture_backend`, `stream_audio`, `display_policy`, and `restore_on_disconnect`.
- Expose an authenticated `GET /api/second-monitor/status` response containing `state`, selected device ID, mapped output, capture backend, encoder, active resolution/FPS, and last reinitialization reason.
- Use explicit states `waiting_for_vdd`, `display_configuring`, `capturing`, `capture_reinitializing`, `display_restore_pending`, and `display_restore_failed`.

- [ ] **Step 1: Add failing profile parsing tests.** Validate required VDD ID, allowed policy values, valid resolution/FPS ranges, and rejection of unknown fields where the current config schema requires strictness.
- [ ] **Step 2: Add failing lifecycle tests.** Cover VDD missing before launch, VDD appearing during retry, failed RTSP launch, final disconnect with restore enabled, and two active sessions sharing display ownership.
- [ ] **Step 3: Implement profile parsing and defaults.** Keep regular Sunshine apps unchanged; second-monitor profile is opt-in.
- [ ] **Step 4: Implement lifecycle state transitions.** Make launch and reconnect report a retryable `waiting_for_vdd` result and make final-session cleanup restore the saved state once.
- [ ] **Step 5: Implement diagnostics endpoint.** Reuse existing authentication/CSRF rules and return JSON without exposing secrets or arbitrary process commands.
- [ ] **Step 6: Add VDD selector UI.** Show friendly name, stable ID, active state, current resolution, and whether a device is virtual; avoid making users type a GUID for normal setup.
- [ ] **Step 7: Run unit/integration tests and commit.** Use `feat: add second monitor profiles and display diagnostics`.

## Task 4: Sunshine Native Touch Reliability

**Files:**
- Modify: `src/input.cpp`
- Modify: `src/platform/windows/input.cpp`
- Modify: `tests/unit/test_mouse.cpp`
- Add: `tests/unit/test_touch_mapping.cpp`
- Add: `tests/integration/test_windows_touch.cpp` only when an interactive Windows session is available

**Interfaces:**
- Keep the protocol touch packet fields: event type, pointer ID, normalized coordinates, pressure/distance, contact area, and rotation.
- Add a pure mapping function used by tests:

```cpp
std::optional<touch_mapping_result> map_client_touch_to_monitor(
    const touch_port_t &port,
    float normalized_x,
    float normalized_y);
```

- The Windows backend must cancel all active synthetic contacts when a client context is destroyed.

- [ ] **Step 1: Write mapping tests first.** Cover normal VDD origin, negative desktop origin, letterboxed coordinates, invalid dimensions, pointer ID reuse, and rotation normalization.
- [ ] **Step 2: Run the mapping tests and verify failure.** Run `ctest --test-dir build -R touch_mapping --output-on-failure`.
- [ ] **Step 3: Extract and implement pure coordinate mapping.** Keep platform injection out of the pure function and preserve the existing monitor-local logical coordinate math.
- [ ] **Step 4: Fix native touch gating.** Ensure the configured native touch policy is checked before `platf::touch_update()` and does not accidentally depend on the mouse setting.
- [ ] **Step 5: Verify synthetic pointer cleanup.** Make disconnect and cancellation release every active slot and preserve the 50 ms keepalive requirement for active contacts.
- [ ] **Step 6: Run mapping and existing input tests.** Run the focused tests and the full Sunshine unit suite.
- [ ] **Step 7: Commit.** Use `fix: make Windows touch input safe for virtual displays`.

## Task 5: Moonlight iOS Native Touch and Desktop Input Modes

**Files:**
- Modify: `Limelight/Input/AbsoluteTouchHandler.m`
- Modify: `Limelight/Input/AbsoluteTouchHandler.h`
- Modify: `Limelight/Input/StreamView.m`
- Modify: `Limelight/Input/StreamView.h`
- Modify: `Limelight/Input/RelativeTouchHandler.m`
- Modify: `Limelight/Input/RelativeTouchHandler.h`
- Modify: `Limelight/Database/TemporarySettings.h`
- Modify: `Limelight/Database/TemporarySettings.m`
- Modify: `Limelight/Stream/StreamConfiguration.h`
- Modify: `Limelight/Stream/StreamConfiguration.m`
- Test: add an iOS unit-test target for pure coordinate/gesture mapping if the current Xcode project has no test target

**Interfaces:**
- Define an input mode enum with `nativeTouch`, `mouseCompatibility`, and `hybrid`.
- Define a pure coordinate conversion function:

```objc
CGPoint LMNormalizedPointForTouch(CGPoint point, CGRect videoBounds, CGRect displayedVideoRect);
```

- Use the exact touch packet declarations exported by the checked-out `moonlight-common-c/Limelight.h`; do not create a duplicate protocol declaration in the app.

- [ ] **Step 1: Add failing pure mapping tests.** Cover aspect-fit video, cropped video, landscape rotation, edge clamping, and a point outside the displayed video rectangle.
- [ ] **Step 2: Run the iOS tests and verify failure.** Use `xcodebuild test -project Moonlight.xcodeproj -scheme Moonlight -destination 'platform=iOS Simulator,name=iPad (5th generation)'` with an Xcode version that supports the project.
- [ ] **Step 3: Implement native touch lifecycle.** Track touch objects by stable pointer ID, send began/moved/ended/cancelled packets, include normalized position and contact metadata available on iOS 12, and cancel every active pointer on teardown.
- [ ] **Step 4: Implement desktop gestures.** Keep native touch as the default; map long press to the configured compatibility action, use two-finger scrolling, and expose mouse fallback without silently changing the selected mode.
- [ ] **Step 5: Implement coordinate conversion.** Convert against the actual displayed video rectangle rather than the full `StreamView` bounds, then clamp to `[0, 1]`.
- [ ] **Step 6: Run focused tests and perform a simulator smoke build.** Verify mapping tests pass and that the iOS 12 target compiles without modern availability violations.
- [ ] **Step 7: Commit.** Use `feat: add native touch desktop input modes`.

## Task 6: Moonlight iOS Second-Monitor Profile and Reconnect

**Files:**
- Modify: `Limelight/Database/DataManager.h`
- Modify: `Limelight/Database/DataManager.m`
- Modify: `Limelight/Database/TemporarySettings.h`
- Modify: `Limelight/Database/TemporarySettings.m`
- Modify: `Limelight/Stream/StreamConfiguration.h`
- Modify: `Limelight/Stream/StreamConfiguration.m`
- Modify: `Limelight/Stream/StreamManager.m`
- Modify: `Limelight/ViewControllers/StreamFrameViewController.m`
- Modify: `Limelight/ViewControllers/SettingsViewController.m`
- Modify: `Limelight/Stream/VideoDecoderRenderer.m`
- Test: iOS profile validation and reconnect state tests

**Interfaces:**
- Define a profile value object containing `mode`, `resolution`, `fps`, `bitrate`, `codec`, `audioPolicy`, `inputMode`, and `reconnectEnabled`.
- Define stream states `connecting`, `waitingForDisplay`, `streaming`, `reconnecting`, `failed`, and `stopped`.
- Make profile validation return a structured error instead of presenting unsupported combinations.

- [ ] **Step 1: Add failing profile tests.** Verify iPad Air defaults to H.264/720p/30 FPS, rejects AV1/HEVC/HDR/120 FPS for the target capability profile, and accepts experimental 1080p30 only when explicitly enabled.
- [ ] **Step 2: Add failing reconnect tests.** Verify a transient connection loss retains host/profile, retries with bounded backoff, cancels touch contacts, and returns a user-visible failure after the retry budget.
- [ ] **Step 3: Implement per-host/profile persistence.** Extend the existing Core Data path without deleting the store on ordinary migration errors; preserve regular gaming settings.
- [ ] **Step 4: Implement desktop stream defaults.** Disable game controls and audio by default, select H.264, and pass the selected profile values into `StreamConfiguration`.
- [ ] **Step 5: Implement reconnect state.** Keep stream ownership in `StreamFrameViewController`, cancel input on loss, and restore the same host/profile on retry.
- [ ] **Step 6: Make decoder failure recoverable.** Replace the unknown-codec `abort()` path with a logged failure and controlled stream termination; preserve IDR recovery for recoverable decoder errors.
- [ ] **Step 7: Run tests and simulator smoke build.** Confirm regular game mode remains unchanged and commit with `feat: add iOS second monitor stream profile`.

## Task 7: iPad Desktop UI and Keyboard Toolbar

**Files:**
- Modify: `iPad.storyboard` or replace the second-monitor screen with focused programmatic UIKit views under `Limelight/ViewControllers`
- Modify: `Limelight/ViewControllers/SettingsViewController.m`
- Modify: `Limelight/Input/KeyboardInputField.m`
- Modify: `Limelight/Input/KeyboardInputField.h`
- Modify: `Limelight/Input/StreamView.m`
- Modify: `Limelight/Input/OnScreenControls.m`
- Modify: `Limelight/Limelight-Info.plist` only for iOS 12-safe capabilities
- Test: iPad UI/profile smoke tests

**Interfaces:**
- Add a desktop toolbar with visibility state, input mode selector, keyboard button, reconnect button, and diagnostics button.
- Add an iOS 12-compatible modifier action model:

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

- [ ] **Step 1: Add failing layout checks.** Verify the second-monitor screen has a landscape video area, hidden-by-default toolbar, and no gamepad overlay in desktop mode.
- [ ] **Step 2: Implement the compact toolbar.** Keep controls large enough for a 9.7-inch display, make the toolbar hideable, and avoid blocking the video surface during ordinary touch use.
- [ ] **Step 3: Implement keyboard toolbar actions.** Route modifier/function actions through the existing iOS 12 keyboard capture path and ensure every press has a corresponding release on dismissal or disconnect.
- [ ] **Step 4: Add settings sections.** Add profile, resolution, FPS, bitrate, audio, input mode, gesture, reconnect, and diagnostics settings with unsupported values removed rather than merely disabled.
- [ ] **Step 5: Replace only the fragile layout portion.** Preserve existing navigation and game settings while moving second-monitor layout away from manual fixed-frame height calculations.
- [ ] **Step 6: Run iOS tests and build.** Verify the iPad storyboard/programmatic UI loads on iOS 12 and commit `feat: add iPad desktop second monitor interface`.

## Task 8: End-to-End Diagnostics and Device Validation

**Files:**
- Modify: `README.md` in both repositories
- Add: `docs/superpowers/validation/second-monitor-test-matrix.md`
- Modify: Sunshine diagnostic response and Moonlight diagnostics overlay from Tasks 3 and 6
- Test: Sunshine unit/integration tests and iOS simulator/device smoke build

**Interfaces:**
- Define a diagnostic record with host display ID, mapped output, capture backend, encoder, codec, resolution, FPS, bitrate, RTT, dropped frames, reconnect count, and last error.
- Define a manual device test matrix that distinguishes simulator checks from iPad Air 1 checks.

- [ ] **Step 1: Add failing serialization tests.** Verify diagnostic JSON contains state and display identity but no passwords, pairing keys, or arbitrary command content.
- [ ] **Step 2: Implement diagnostic collection.** Connect Sunshine session state and Moonlight stream stats without increasing logging frequency on the video path.
- [ ] **Step 3: Add the validation matrix.** Include VDD present/missing, display hotplug, 720p30, 1080p30, touch lifecycle, multi-touch cancel, Wi-Fi interruption, reconnect, final restore, wrong GUID, and physical-monitor fallback prevention.
- [ ] **Step 4: Run host tests.** Execute Sunshine unit and integration tests; run the interactive Windows touch/display tests only on the target Windows session.
- [ ] **Step 5: Run iOS checks.** Build the iOS 12 target in Simulator, then build an unsigned device archive on macOS when available; record any signing-independent compile failures.
- [ ] **Step 6: Document the target profile.** Record the measured stable mode for the iPad Air 1 instead of claiming 1080p/60 FPS without evidence.
- [ ] **Step 7: Commit.** Use `test: add second monitor validation matrix`.

## Task 9: Optional VDD.Control Companion and Jailbreak Package

**Files:**
- Add: a separate companion repository or `tools/second-monitor-companion` only after Tasks 1-8 pass
- Add: separate jailbreak tweak project only after the core app is stable
- Modify: repository README files with opt-in installation instructions

**Interfaces:**
- Companion input: selected VDD identity and requested display profile.
- Companion output: `waiting`, `active`, `failed`, and `restored` with the stable device ID.
- Jailbreak package has no compile-time or runtime dependency from Moonlight.

- [ ] **Step 1: Prove the existing VDD.Control workflow is insufficient.** Use the diagnostic endpoint and manual profile activation before adding a new executable.
- [ ] **Step 2: Add companion tests.** Verify it waits for enumeration, applies a profile once, and restores the previous state on cancellation.
- [ ] **Step 3: Keep driver lifecycle conservative.** Do not create or destroy kernel devices automatically; only configure an existing VDD.
- [ ] **Step 4: Build the optional package separately.** Ensure core Moonlight/Sunshine builds do not reference it.
- [ ] **Step 5: Commit only if needed.** Use `feat: add optional second monitor companion` or omit this task when the native Sunshine path is sufficient.

## Verification Commands

Run these after the corresponding tasks, adapting only the build directory selected by the repository's existing preset:

```powershell
git submodule status --recursive
ctest --test-dir build --output-on-failure
cmake --build build --config Release
```

On macOS with an Xcode installation that can compile the legacy project:

```bash
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug -sdk iphonesimulator build
xcodebuild test -project Moonlight.xcodeproj -scheme Moonlight -destination 'platform=iOS Simulator,name=iPad (5th generation)'
```

The final claim of success requires command output from the relevant host tests and an actual iPad Air 1 smoke test; a simulator build alone cannot validate the A7 decoder, Wi-Fi behavior, or Windows touch injection.
