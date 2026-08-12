# Moonlight iOS/tvOS

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
