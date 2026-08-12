# Second Monitor Design

## Goal

Turn the Moonlight iOS fork and its Sunshine fork into a reliable remote second-monitor solution for an iPad Air 1 running iOS 12.5.8 and an HP Laptop 15s-eq1xxx running Windows 11 IoT LTSC build 26100.

The iPad must receive the Windows virtual display created by Virtual Display Driver (VDD). The default interaction model is native touch, with configurable mouse compatibility mode. This is not a gaming-first feature.

## Constraints

- iOS deployment target remains 12.0.
- iPad Air 1 is limited to H.264 hardware decoding and legacy UIKit input APIs.
- HEVC, AV1, HDR, modern pointer APIs, Pencil APIs, and 120 FPS are not target features.
- The laptop uses Ryzen 7 4700U, AMD integrated graphics, 16 GB RAM, Realtek RTL8821CE Wi-Fi 5, and VDD 11.30.4.434.
- Sunshine must never silently fall back from a requested VDD to a physical monitor.
- Jailbreak-specific behavior is optional and isolated from the core application.

## Architecture

### Moonlight iOS

Add a dedicated `Second Monitor` profile and presentation path around the existing streaming pipeline.

- Keep the existing H.264/VideoToolbox path and select H.264-only for the iPad Air profile.
- Default to 1280x720 at 30 FPS and a conservative bitrate; expose 1080p30 only after runtime validation.
- Disable game overlays by default and provide a compact, hideable desktop toolbar.
- Replace the current absolute-touch-to-mouse behavior with real touch packets where the protocol and host support it.
- Retain `Mouse` and `Hybrid` modes for applications that do not consume touch input.
- Normalize touch coordinates against the actual displayed video rectangle, including letterboxing, rotation, VDD offset, and DPI.
- Support multi-touch IDs, begin/move/end/cancel, long press, scrolling, pinch, and configurable gesture mappings.
- Provide a legacy keyboard path usable on iOS 12, including an on-screen modifier/function toolbar.
- Add per-host/per-profile settings for resolution, FPS, bitrate, audio, input mode, gestures, and reconnect behavior.
- Add reconnect without returning to the host list and surface stream diagnostics: FPS, bitrate, latency, dropped frames, decoder, and termination reason.
- Replace fragile fixed-frame settings expansion with an iPad layout that remains usable on the 9.7-inch display.
- Remove or hide unsupported codec, HDR, resolution, and refresh-rate options for this device profile.
- Replace decoder `abort()` behavior with a recoverable user-visible error and an IDR recovery attempt.

### Sunshine

Extend the existing display and input abstractions rather than bypassing them.

- Add an opt-in VDD-only display policy for second-monitor sessions.
- Bind the selected display by stable VDD `device_id`, remapping it after display enumeration changes.
- If the VDD disappears, report a retryable `waiting_for_vdd` state instead of selecting the first physical display.
- Expose display/session diagnostics through a small authenticated API: devices, active mapping, capture backend, encoder, resolution, FPS, and reinitialization reason.
- Add per-profile display configuration for VDD ID, resolution, FPS, HDR, capture backend, audio, and restore policy.
- Preserve and reliably restore the previous Windows display state after disconnect, failed handshake, and process termination.
- Verify native touch injection for VDD offsets, negative desktop coordinates, DPI scaling, rotation, multi-touch cancellation, and session cleanup.
- Prefer Desktop Duplication for the AMD iGPU baseline; retain WGC only as an explicit fallback.
- Add validation for app/profile API input before persisting commands and preparation actions.
- Add integration coverage for VDD enumeration, GUID-to-output mapping, hotplug, reconnect, native touch, and no-fallback behavior.

### Optional Windows companion

Do not make VDD.Control a hard runtime dependency in the first vertical slice. Add a companion only if the existing VDD API cannot reliably provide profile activation and restoration.

The companion may later:

- enable or disable the VDD profile;
- apply resolution and refresh rate;
- wait for device enumeration;
- report stable device identity;
- restore the previous state.

Automatic creation/destruction of the driver device is explicitly deferred because it can race Windows display enumeration and risk driver instability.

### Optional jailbreak integration

Keep jailbreak support in a separate package. Candidate features are preventing sleep, locking landscape orientation, suppressing system gestures and notifications, and exposing extra diagnostics. The core stream, input, and display protocol must not depend on private APIs or jailbreak state.

## User Flows

### First setup

1. User pairs the iPad with Sunshine.
2. Moonlight discovers available host display profiles.
3. User selects `Second Monitor` and the VDD profile.
4. Sunshine validates the VDD identity and configures it without selecting a physical-display fallback.
5. Moonlight starts an H.264 desktop stream with the selected profile.
6. The stream screen opens in landscape with native touch enabled and the compact toolbar hidden.

### VDD unavailable

1. Sunshine reports `waiting_for_vdd`.
2. Moonlight shows the display name and retry state.
3. Sunshine retries enumeration without changing the selected display to a physical monitor.
4. The user can cancel and restore the previous display state.

### Disconnect and reconnect

1. Input is cancelled and no touch contacts remain stuck.
2. The stream enters reconnecting state while preserving the selected host/profile.
3. Sunshine keeps display ownership consistent with active sessions.
4. On final disconnect, the prior Windows display configuration is restored.

## Performance Targets

- Baseline: stable 720p30 H.264 stream on the iPad Air 1.
- Experimental: 1080p30 only when decoder, memory, Wi-Fi, and dropped-frame measurements pass.
- No audio by default for second-monitor mode, with an explicit host/iPad audio choice.
- Display selection must remain bound to the requested VDD across hotplug and reconnect.
- Touch input must not degrade into mouse input unless the user selects compatibility mode or the host reports that native touch is unavailable.
- Diagnostics must make latency, dropped frames, reconnect cause, and active display visible.

## Delivery Order

1. Initialize and verify all required submodules and reproducible builds.
2. Implement Sunshine VDD-only binding, stable remapping, and diagnostic state.
3. Implement Moonlight native touch packet path and iOS 12 desktop input modes.
4. Add 720p30 second-monitor profile, reconnect, audio policy, and diagnostics.
5. Add tests for coordinate transforms, touch lifecycle, VDD hotplug, and no-fallback behavior.
6. Replace the old settings/stream UI with the second-monitor interface.
7. Add adaptive bitrate, 1080p30, gesture customization, and optional companion integration only after device testing.

## Explicitly Deferred

- HEVC, AV1, HDR, 4K, 120 FPS, Apple Pencil, modern iPad pointer APIs.
- Sidecar-like system display extension on iOS 12.
- Automatic VDD driver creation/destruction.
- Multiple simultaneous stream sessions.
- Replacing the entire FFmpeg/SDL/VideoToolbox stack.
- Jailbreak-only core behavior.

## Acceptance Criteria

- A selected VDD is the only capture target for second-monitor mode.
- The iPad receives real touch packets end-to-end on supported Windows paths.
- Tap, drag, long press, scrolling, multi-touch, cancel, and reconnect do not leave stuck input.
- VDD disappearance produces a retryable state and never silently captures a physical monitor.
- Disconnect restores Windows display state.
- The baseline profile is usable on iPad Air 1 with iOS 12.5.8.
- Unsupported options are not presented as selectable features.
- Build and test instructions are reproducible from the forked repositories.
