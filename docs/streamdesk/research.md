# StreamDesk on the first iPad Air

This design targets an extended desktop over a local network. A measurable improvement is lower input-to-photon latency or fewer missed frames at equivalent readability. An archive build, a successful RTSP handshake and a smooth stream on another iPad each cover different parts of that requirement.

## Client and display

| Finding | Product decision | Acceptance evidence |
|---|---|---|
| The first Air runs iOS 12 and has a 4:3 panel. Sending 1440×1080 instead of 2048×1536 reduces the pixels per frame by 50.6%. | Keep an arm64 iOS 12 target. Offer 1024×768 at 4 Mb/s, 1280×960 at 6 Mb/s and 1440×1080 at 8 Mb/s. All start at 30 FPS on A7. | IPA load commands and Apple-device startup. A7 decode and text legibility at each setting. |
| 1280×960 has 21% fewer pixels than 1440×1080. A lower video resolution can preserve the host's KDE work area because Sunshine can scale the capture to the requested stream size. | Start on 1280×960. Keep the KDE capture at 1440×1080 and preserve the 4:3 aspect ratio across presets. | Confirm source and encoded sizes in the same session, then measure decoder/rate drops. |
| The client already requests immediate presentation via Core Media. Its optional frame pacing keeps up to one pending frame when the screen can keep up. | Let each computer profile opt into smoother pacing. The default requests the existing low-latency behavior. At 30 FPS a queued extra frame can cost about 33 ms. | Compare with the same motion and Wi-Fi traffic, using at least 30 input-to-photon samples for each mode. |
| iOS 13 pointer APIs are unavailable on iOS 12. Native touch and relative mouse-compatible gestures use the older UIKit path. | Keep touch, mouse and hybrid profiles. Put keyboard, switching, stats and disconnect in the in-stream panel. | On the Air, verify touch hit testing across 4:3 letterboxing, button release on disconnect and software keyboard text entry. |
| A disconnect and host-side quit have different effects on an extended desktop. | Put disconnect in the toolbar and use the existing client stop path. Keep bounded reconnect for wireless drops. | Drop and restore Wi-Fi, verify a return to the same desktop. Check button-held cleanup and confirm the OS has no stuck modifiers. |

[Apple iOS 12.5.7 device compatibility](https://support.apple.com/en-us/103015), [Apple Core Media immediate presentation](https://developer.apple.com/documentation/coremedia/kcmsampleattachmentkey_displayimmediately), [Moonlight video renderer](https://github.com/moonlight-stream/moonlight-ios/blob/master/Limelight/Stream/VideoDecoderRenderer.m), [Moonlight client implementation](https://github.com/moonlight-stream/moonlight-ios).

## Linux capture and transport

| Finding | Product decision | Acceptance evidence |
|---|---|---|
| KWin has a direct screencast protocol, and KRfb creates a compositor-owned virtual output. Physical DRM outputs and KWin virtual outputs can have different capture support. | Use KWin + PipeWire, with the exact configured virtual output. Strict selection also applies during reinitialization. Isolate KRfb's unused VNC listener in its own network namespace. | Verify capture of Virtual-StreamDesk, simultaneous physical output and loss of capture if only the physical display remains. |
| PipeWire can negotiate DMA-BUF surfaces. The encoder can still require import or conversion based on buffer format, modifiers and driver. | Prefer hardware H.264 on AMD VA-API where probing succeeds. Leave memory transport negotiated. Count actual software and hardware paths before removing any fallback. | Inspect KWin/PipeWire negotiation logs and actual encoder per stream. Compare encode time and CPU use under stationary and scrolling workloads. |
| Sunshine already paces packet batches within frames and adds FEC. More redundancy increases traffic. Peak packet bursts can overload a weak Wi-Fi hop even when average throughput looks sufficient. | Start with the lower profile on marginal Wi-Fi. Keep current FEC/packet pacing, collect loss and jitter before changing them. | Change one setting per run. Count frame loss and 95th percentile RTT with a load on the slowest hop. |
| Existing transport exposes an estimated network RTT and counters for frame loss. RTT does not measure compositor presentation, hardware decode, panel refresh or input sampling. | Make stats available without changing profile. Collect RTT variance and frame loss in follow-up instrumentation with precise labels. | Compare telemetry against packet timestamps. Measure input-to-photon separately with a camera. |
| The present codec/bitrate configuration is negotiated at launch. Blindly changing resolution or encoder settings during a session risks a black screen or forced reconnect. | Prefer explicit profiles first. Investigate verified live bitrate change with opt-in capability negotiation; keep network control and decode-pressure control separate. | Verify bounded hysteresis on fixed network traces first, then run on a first-generation iPad with a competing transfer and repeated dips. |
| A virtual screen can stay active between sessions, taking windows and space when the iPad is away. | Start and stop the extended-display host as a user service, using dependency readiness. Install in parallel on a separate port and settings tree. | Test install twice, start/stop, compositor loss, startup timeout and rollback to previous revision. |

[Sunshine settings](https://docs.lizardbyte.dev/projects/sunshine/master/md_docs_2configuration.html), [Sunshine networking source](https://github.com/SunshineStream/Sunshine/blob/master/src/stream.cpp), [Sunshine network troubleshooting](https://github.com/SunshineStream/Sunshine/blob/master/docs/troubleshooting.md), [KDE KRfb virtual output](https://github.com/KDE/krfb/blob/master/krfb/main-virtualmonitor.cpp), [Moonlight statistics definitions](https://github.com/moonlight-stream/moonlight-docs/wiki/Frequently-Asked-Questions#what-do-the-numbers-mean-in-the-on-screen-connection-statistics).

## Performance experiments in order

1. Compare 1024×768, 1280×960 and 1440×1080 at 30 FPS and H.264 using the same local test page. Record text legibility, p50/p95 input-to-photon, network drops, actual FPS and host CPU usage. Run one stationary, one scrolling and one interactive workload.
2. Hold resolution fixed and vary 4, 6 and 8 Mb/s at comparable signal strength. Repeat once with the host wired and once in its normal Wi-Fi configuration. Publish the exact signal, AP band, negotiated rate and competing load. Lab rate numbers are useful only alongside actual loss and frame delivery.
3. Toggle client frame pacing at the chosen bitrate. Look at both p95 visual response and its spread. Track whether the symptom is packet loss, uneven presentation or an encoder overload before adjusting the host.
4. Compare DMA-BUF negotiation and CPU capture only with the same scene, resolution and hardware encoder. Profile copies and queue depth before changing buffer ownership or dropping frames.
5. Prototype higher feature tiers behind per-profile switches. Candidates include a transient link-test summary, profile selection by client capability, display geometry presets, a clearer touch calibration screen, configurable shortcuts and shift-of-focus handling. Treat transport changes separately from these usability improvements.

## Publishing and signing

The IPA needs both `MinimumOSVersion = 12.0` and an arm64 Mach-O with an iOS 12 deployment command. The project verifies them after archiving. Those metadata checks cannot reveal every weak-linking failure, so launch on the A7 hardware is required. An unsigned IPA is a complete compilation artifact for subsequent signing. Installation on an unmodified iPad requires a signing identity and matching device provisioning. Pair with the Linux fork after installation, without reusing the currently connected app's bundle identifier or deleting its pairing.

[Apple Xcode compatibility tables](https://developer.apple.com/xcode/system-requirements/), [Apple development provisioning profile](https://developer.apple.com/help/glossary/development-provisioning-profile/), [Legacy iOS Kit Linux sideloading documentation](https://github.com/LukeZGD/Legacy-iOS-Kit/wiki/Sideloading-on-Linux).

## Design direction

StreamDesk presents a Linux workstation on an iPad. The interface feels quiet and practical. The monitor, transfer data and profile controls define the visual language. Graphite surfaces keep the screen content prominent, with a pale green accent on selected controls and the live format readout. The profile card shows the requested picture size, frame rate and codec together. Spacing, grouping and copy were revised using the Unslop method by Damir Sokolovsky.

### Sign the package on Linux

With a device profile covering `org.streamdesk.client` and its matching Apple development identity exported as PKCS#12, run the following command with [zsign](https://github.com/zhlynn/zsign) on the local PATH.

```sh
BuildScripts/sign-ipad-ipa-linux.sh StreamDesk-iOS12-unsigned.ipa Device.mobileprovision Development.p12 StreamDesk-signed.ipa
```

OpenSSL prompts for the identity password locally. The script checks certificate membership, bundle identifier and expiration, preserves the certificate chain, and verifies the embedded profile and package structure. The signing workflow passed a positive test with a synthetic certificate chain and rejected a mismatched profile. A stock iPad checks the Apple trust chain and its device registration at installation. Device installation and startup are still acceptance steps.
