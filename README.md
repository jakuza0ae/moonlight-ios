# Moonlight iOS/tvOS


## StreamDesk for iPad

This branch focuses on using the iPad as an extended Linux desktop. Open **Second display** to configure a computer. The **StreamDesk Display** or **iPad Air** app on the host opens with a 4:3 profile. Start with 1280×960 at 30 FPS on the first-generation iPad Air.

To connect from a launcher or a Shortcuts action that opens a URL, use `streamdesk://second-display`. Pair the computer and open its app list once, then choose it in **Second display** and save. If there is only one eligible paired computer, the shortcut can use it without a saved choice. Otherwise it opens the settings to let you pick a computer. The computer must already be running the StreamDesk host.

In a second-display stream, swipe down from the top edge to show the toolbar. **Dim** reduces display brightness to 30%. **Restore** returns the previous brightness. The app also releases dimming when the stream closes or the iPad leaves the app.

The [iPad IPA workflow](https://github.com/jakuza0ae/moonlight-ios/actions/workflows/build-unsigned-ipa.yml) produces an unsigned arm64 package targeting iOS 12. Stock iPads need a development signature and a provisioning profile for the device. The bundle ID is `org.streamdesk.client`.

[Linux host setup](https://github.com/jakuza0ae/Sunshine/blob/linux-streamdesk/packaging/linux/streamdesk/README.md) · [Design and performance research](docs/streamdesk/research.md)

[![AppVeyor Build Status](https://ci.appveyor.com/api/projects/status/kwv8vpwr457lqn25/branch/master?svg=true)](https://ci.appveyor.com/project/cgutman/moonlight-ios/branch/master)

[Moonlight for iOS/tvOS](https://moonlight-stream.org) is an open source client for [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream. Moonlight for iOS/tvOS allows you to stream your full collection of games and apps from your powerful desktop computer to your iOS device or Apple TV.

Moonlight also has a [PC client](https://github.com/moonlight-stream/moonlight-qt) and [Android client](https://github.com/moonlight-stream/moonlight-android).

Check out [the Moonlight wiki](https://github.com/moonlight-stream/moonlight-docs/wiki) for more detailed project information, setup guide, or troubleshooting steps.

[![Moonlight for iOS and tvOS](https://moonlight-stream.org/images/App_Store_Badge_135x40.svg)](https://apps.apple.com/us/app/moonlight-game-streaming/id1000551566)

## Building

### Checkout
From a parent directory, clone the repository with every dependency:

```sh
git clone --recursive https://github.com/moonlight-stream/moonlight-ios.git
cd moonlight-ios
```

For an existing checkout, initialize or repair all dependencies with:

```sh
git submodule update --init --recursive
```

### Xcode
Install Xcode from the [App Store page](https://apps.apple.com/us/app/xcode/id497799835), then open `Moonlight.xcodeproj` in Xcode. The iOS targets declare an iOS 12.0 deployment target.

An iOS device build requires macOS and Xcode, even when signing and provisioning are handled separately. To run on a real device, configure the Team and a unique Bundle Identifier under the target's **Signing & Capabilities** settings, then select the device and run the app.

## Second-Monitor Validation

The second-monitor path targets an existing virtual display selected by host/profile identity. Its conservative starting profile is H.264 at `1280x720 @ 30 FPS`; `1920x1080 @ 30 FPS` is an explicit experiment, not a claimed iPad Air 1 baseline. The stable iPad Air 1 mode is `NOT MEASURED` until a physical-device run records it. Moonlight adds `secondMonitor=1` only to launches explicitly started with this profile; regular game launches do not carry the marker and keep their normal host display/audio settings.

The local diagnostic record follows the shared schema in the validation matrix. Moonlight's RTT, dropped-frame, and reconnect values are client-side metrics, not host metrics. Host display ID, mapped output, capture backend, and encoder remain nullable and render as `unavailable` unless an authenticated Sunshine status source supplies them. Sunshine host `rtt_ms`, `dropped_frames`, and `reconnect_count` are currently nullable because the host status path does not collect those metrics.

Use the validation matrix in `docs/superpowers/validation/second-monitor-test-matrix.md`. It distinguishes simulator checks from iPad Air 1 checks and records unavailable work as `BLOCKED/NOT RUN`. The simulator cannot validate VDD hotplug, Wi-Fi recovery, or physical touch behavior.

Available macOS commands are:

```sh
xcodebuild test -project Moonlight.xcodeproj -scheme Moonlight -destination 'platform=iOS Simulator,name=iPad (5th generation)'
xcodebuild -project Moonlight.xcodeproj -scheme Moonlight -configuration Debug -sdk iphonesimulator build
xcodebuild archive -project Moonlight.xcodeproj -scheme Moonlight -configuration Release -sdk iphoneos -archivePath build/Moonlight.xcarchive CODE_SIGNING_ALLOWED=NO
```

The commands above were not run on Windows when Xcode was unavailable; no simulator or device build is claimed here.
