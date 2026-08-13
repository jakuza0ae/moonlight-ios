# Second-Monitor Validation Matrix

This matrix covers the existing VDD-only second-monitor path across Sunshine and Moonlight. A check is `PASS` only when the stated environment and evidence are available. `BLOCKED/NOT RUN` means the environment or live hardware was unavailable; it is never a pass or a failure.

## Target Profile

- Baseline: `1280x720 @ 30 FPS`, H.264, conservative bitrate, host audio disabled.
- Experimental mode: `1920x1080 @ 30 FPS` only after a measured iPad Air 1 run shows stable decode, memory, Wi-Fi, and dropped-frame behavior.
- No `1080p60` target is claimed. The stable iPad Air 1 mode remains `NOT MEASURED` until a physical device run records it.
- Sunshine must bind the selected existing VDD by stable device ID with `vdd_only`; it must not fall back to a physical monitor.

## Automated Checks

| Check | Repository | Evidence | Current status |
| --- | --- | --- | --- |
| Diagnostic JSON allowlist and redaction | Sunshine | Unit test for state, display identity, metrics, and secret/command absence | BLOCKED/NOT RUN: CTest/toolchain unavailable on the current Windows session |
| Second-monitor lifecycle and selection tests | Sunshine | Unit tests for VDD availability, wrong identity, hotplug remapping, and final restore | BLOCKED/NOT RUN: CTest/toolchain unavailable on the current Windows session |
| Diagnostic overlay formatter | Moonlight | XCTest formatter coverage for the bounded record | BLOCKED/NOT RUN: Xcode is unavailable on the current Windows session |
| iOS 12 Simulator build and smoke tests | Moonlight | `xcodebuild` Simulator build/test output | BLOCKED/NOT RUN: macOS/Xcode unavailable |
| Unsigned device archive | Moonlight | macOS `xcodebuild archive` output with signing disabled | BLOCKED/NOT RUN: macOS/Xcode unavailable |

## Manual Matrix

| ID | Scenario | Simulator check | iPad Air 1 check | Expected evidence |
| --- | --- | --- | --- | --- |
| VDD-01 | VDD present and selected | Verify the profile requires an explicit host and device ID; no physical display is available in the simulator | Enumerate the existing VDD, select its positive virtual identity, launch the baseline profile | Sunshine status shows `capturing`, the selected host display ID, mapped output, `virtual_device=true`, and the requested mode |
| VDD-02 | VDD missing at launch | Exercise profile validation and the waiting state with the live host unavailable | Remove or disable the VDD before launch, then restore it | Launch waits with `waiting_for_vdd`; no physical output is selected; re-enumeration can proceed without changing the GUID |
| VDD-03 | Wrong GUID | Verify invalid profile selection is rejected without implicit host/device substitution | Configure a nonexistent GUID while a physical monitor is present | Launch is rejected or remains unavailable; the physical monitor is never used as fallback |
| VDD-04 | Physical-monitor fallback prevention | Confirm the UI does not offer an unverified physical display | Keep a physical monitor active and select a physical/unknown identity | Sunshine reports unavailable for the second-monitor profile; capture does not start on the physical monitor |
| VDD-05 | VDD hotplug and remapping | Exercise lifecycle state handling and reconnect UI without claiming a device result | Remove and re-add the VDD while streaming, then repeat with a changed platform output name | The stable VDD device ID remains selected, mapped output is refreshed, and the overlay/status records the reinitialization reason |
| MODE-01 | 720p30 baseline | Verify profile/settings serialization and overlay formatting | Run `1280x720 @ 30 FPS` for a sustained session | Record actual FPS, bitrate, RTT, dropped frames, codec, and last error; baseline is PASS only with device evidence |
| MODE-02 | 1080p30 opt-in | Verify the explicit opt-in and validation path | Enable the experimental switch, run `1920x1080 @ 30 FPS`, and compare stability against MODE-01 | Record memory pressure, decode stability, reconnects, and dropped frames; do not infer 1080p stability from simulator output |
| TOUCH-01 | Touch lifecycle | Exercise tap, drag, long press, and release through the simulated view | Repeat tap, drag, long press, and interrupted contact on the physical display session | Every contact ends with release or cancel; no stuck touch remains after stream stop |
| TOUCH-02 | Multi-touch cancellation | Start multiple contacts and trigger view cancellation | Repeat with two or more contacts, including disconnect/reconnect during contact | All active contacts emit cancellation/release, and the next session starts with no stale contacts |
| NET-01 | Wi-Fi interruption | Exercise reconnect state transitions with a simulated connection interruption | Disable Wi-Fi or interrupt the access point, restore it, and observe the bounded retry path | Stream shows reconnecting, retains host/profile, increments reconnect count, and either recovers or shows the bounded failure |
| NET-02 | Final restore | Verify teardown calls the restore gate once | End the final session after normal stop, failed launch, and reconnect exhaustion | Saved display configuration is restored once; status is `waiting_for_vdd` on success or `display_restore_failed` with a recorded error |
| DIAG-01 | Diagnostic response safety | Inspect formatter output with test values | Fetch authenticated `GET /api/second-monitor/status` while active | Output contains state/display/stream metrics only; it contains no password, pairing key, secret, or arbitrary command content |
| DIAG-02 | Bounded video-path diagnostics | Confirm the overlay uses the existing timer | Leave the diagnostics overlay visible during a sustained physical session | Sampling remains at the existing one-second UI timer; no per-frame diagnostic logging is added |

## Run Notes

For every physical run, record the iPad Air 1 model identifier, iOS version, Sunshine build, VDD provider/driver, host GPU/encoder, Wi-Fi band, requested profile, measured stable mode, reconnect count, dropped frames, and final restore result. Mark missing host/device access as `BLOCKED/NOT RUN` and include the prerequisite needed to run it.
