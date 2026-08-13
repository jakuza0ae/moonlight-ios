# Second-Monitor Validation Matrix

This matrix covers the existing VDD-only second-monitor path across Sunshine and Moonlight. A check is `PASS` only when the stated environment and evidence are available. `BLOCKED/NOT RUN` means the environment or live hardware was unavailable; it is never a pass or a failure.

## Diagnostic Contract

The shared diagnostic record uses these fields and JSON spellings:

```json
{
  "state": "capturing",
  "host_display_id": "{vdd-guid}",
  "mapped_output": "\\\\.\\DISPLAY2",
  "capture_backend": "ddx",
  "encoder": "h264_nvenc",
  "codec": "h264",
  "resolution": "1280x720",
  "fps": 30,
  "bitrate_kbps": 5000,
  "rtt_ms": null,
  "dropped_frames": null,
  "reconnect_count": null,
  "last_error": null
}
```

- `state` is one of `waiting_for_vdd`, `display_configuring`, `capturing`, `capture_reinitializing`, `display_restore_pending`, `display_restore_failed`, `connecting`, `waiting_for_display`, `streaming`, `reconnecting`, `failed`, or `stopped`.
- `rtt_ms`, `dropped_frames`, and `reconnect_count` are nullable on Sunshine because this host status path has no host-side telemetry source for those values. Sunshine must return JSON `null`, not zero, when unavailable.
- Moonlight's local record contains client-side RTT, dropped-frame, and reconnect values. Its host display, mapped output, capture backend, and encoder fields remain null unless an authenticated host status source is added; the overlay renders null as `unavailable`.
- Sunshine and Moonlight bound diagnostic text fields to 128 characters and the formatted Moonlight overlay to 2048 characters. Dangerous or command-like text is rendered as `redacted`.
- Sunshine preserves the existing lifecycle state names, and Moonlight preserves its existing stream state names. The union above is the compatibility contract; a consumer must not infer a host state from a client state.

## Target Profile

- Baseline: `1280x720 @ 30 FPS`, H.264, conservative bitrate, host audio disabled.
- Experimental mode: `1920x1080 @ 30 FPS` only after a measured iPad Air 1 run shows stable decode, memory, Wi-Fi, and dropped-frame behavior.
- No `1080p60` target is claimed. The stable iPad Air 1 mode remains `NOT MEASURED` until a physical device run records it.
- Sunshine must bind the selected existing VDD by stable device ID with `vdd_only`; it must not fall back to a physical monitor.

## Automated Checks

| Check | Repository | What is actually covered | Execution status |
| --- | --- | --- | --- |
| Diagnostic JSON schema, nullability, and redaction | Sunshine | Unit tests for state, stable identity, nullable metrics, metadata sanitization, and secret/command absence | BLOCKED/NOT RUN: CTest/toolchain unavailable on the current Windows session |
| Display selection and lifecycle gates | Sunshine | Unit tests for VDD availability, wrong identity, selection order, retry state, owner counting, and restore request gating; no OS hotplug or display-restore side effect | BLOCKED/NOT RUN: CTest/toolchain unavailable on the current Windows session |
| Diagnostic formatter and legacy overlay formatter | Moonlight | XCTest coverage for nullable host fields, state, per-field/total bounds, redaction, and legacy game-mode format | BLOCKED/NOT RUN: Xcode is unavailable on the current Windows session |
| iOS 12 Simulator build and smoke tests | Moonlight | `xcodebuild` Simulator build/test output | BLOCKED/NOT RUN: macOS/Xcode unavailable |
| Unsigned device archive | Moonlight | macOS `xcodebuild archive` output with signing disabled | BLOCKED/NOT RUN: macOS/Xcode unavailable |

## Manual Matrix

| ID | Scenario | Existing automated coverage | Simulator/manual check | iPad Air 1 + live Windows check | Current status |
| --- | --- | --- | --- | --- | --- |
| VDD-01 | VDD present and selected | Selection unit tests only; no live VDD enumeration | No physical VDD available | Enumerate the existing VDD, select its positive virtual identity, launch baseline | BLOCKED/NOT RUN: live Windows host and device unavailable |
| VDD-02 | VDD missing at launch | Waiting-state unit test only; no driver removal/reappearance | No live host state | Remove/disable VDD before launch, restore it, and confirm stable GUID | BLOCKED/NOT RUN: live Windows host and device unavailable |
| VDD-03 | Wrong GUID | Wrong/missing selection unit tests | Profile validation only; no live host | Configure nonexistent GUID with a physical monitor present | BLOCKED/NOT RUN: live Windows host and device unavailable |
| VDD-04 | Physical-monitor fallback prevention | Physical/unknown identity rejection unit tests | No physical fallback available | Keep a physical monitor active and verify capture does not use it | BLOCKED/NOT RUN: live Windows host and device unavailable |
| VDD-05 | VDD hotplug and remapping | Selection/lifecycle logic only; no OS hotplug simulation | No live host state | Remove/re-add VDD and verify stable ID, mapped output, and reinitialization state | BLOCKED/NOT RUN: live Windows host and device unavailable |
| MODE-01 | 720p30 baseline | Profile serialization and formatter unit coverage | No decoder/performance evidence | Run `1280x720 @ 30 FPS` and record client metrics; host RTT/drops/reconnect remain nullable | BLOCKED/NOT RUN: iPad Air 1 unavailable |
| MODE-02 | 1080p30 opt-in | Profile opt-in validation unit coverage | No decoder/performance evidence | Run `1920x1080 @ 30 FPS` and compare measured stability with MODE-01 | BLOCKED/NOT RUN: iPad Air 1 unavailable |
| TOUCH-01 | Touch lifecycle | Existing touch unit coverage; no device smoke | Simulator interaction only after Xcode is available | Repeat tap, drag, long press, and interrupted contact on the physical session | BLOCKED/NOT RUN: Xcode/device unavailable |
| TOUCH-02 | Multi-touch cancellation | Existing cancellation unit coverage; no device smoke | Simulator interaction only after Xcode is available | Repeat multi-touch and cancellation during disconnect/reconnect | BLOCKED/NOT RUN: Xcode/device unavailable |
| NET-01 | Wi-Fi interruption | Reconnect state-machine unit coverage; no network interruption | No Wi-Fi interruption evidence | Interrupt Wi-Fi, restore it, and observe bounded retry/reconnect count | BLOCKED/NOT RUN: live host/device unavailable |
| NET-02 | Final restore | Restore-request gate unit coverage; no display restore side effect | No physical display state | End final session after normal stop, failed launch, and retry exhaustion | BLOCKED/NOT RUN: live Windows host unavailable |
| DIAG-01 | Diagnostic response safety | Serializer/formatter unit coverage; no authenticated endpoint integration test | Formatter only after Xcode is available | Fetch authenticated status endpoint while active and inspect allowlist | BLOCKED/NOT RUN: live host/device unavailable |
| DIAG-02 | Bounded video-path diagnostics | No automated sampling-rate assertion | Overlay timing only after Xcode is available | Leave overlay visible during a sustained session and inspect sampling/log volume | BLOCKED/NOT RUN: live host/device unavailable |

## Run Notes

For every physical run, record the iPad Air 1 model identifier, iOS version, Sunshine build, VDD provider/driver, host GPU/encoder, Wi-Fi band, requested profile, measured stable mode, client reconnect count, client dropped frames, nullable host metrics, and final restore result. Mark missing host/device access as `BLOCKED/NOT RUN` and include the prerequisite needed to run it.
