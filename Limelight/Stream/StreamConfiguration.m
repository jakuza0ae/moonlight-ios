//
//  StreamConfiguration.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"

#include <sys/utsname.h>
#include <Limelight.h>

NSString * const LMProfileValidationDomain = @"com.moonlight.stream-profile";
NSString * const LMProfileValidationFieldKey = @"field";
NSInteger const LMReconnectRetryBudget = 3;
NSTimeInterval const LMReconnectMaximumDelay = 8.0;

BOOL LMShouldUseSecondMonitorProfile(BOOL active, LMStreamProfile *profile) {
    return active && profile != nil && profile.mode == LMStreamModeSecondMonitor;
}

BOOL LMSecondMonitorProfileSelectionIsValid(BOOL active, NSString *hostUUID, LMStreamProfile *profile) {
    return !active || (hostUUID.length != 0 && profile != nil && profile.mode == LMStreamModeSecondMonitor);
}

BOOL LMSecondMonitorProfileSupportsExplicit1080p30(BOOL optIn, CGSize resolution, NSInteger fps) {
    return optIn && CGSizeEqualToSize(resolution, CGSizeMake(1920, 1080)) && fps == 30;
}

BOOL LMShouldMarkSecondMonitorLaunch(StreamConfiguration *configuration) {
    return configuration.profile != nil && configuration.profile.mode == LMStreamModeSecondMonitor;
}

BOOL LMShouldSendCompatibilityLongPress(LMInputMode inputMode, BOOL nativeTouchAvailable) {
    return inputMode == LMInputModeMouseCompatibility || !nativeTouchAvailable;
}

BOOL LMShouldRetryStreamFailure(BOOL reconnectEnabled, BOOL stopping) {
    return reconnectEnabled && !stopping;
}

@implementation LMStreamProfile

+ (instancetype)defaultSecondMonitorProfile {
    LMStreamProfile *profile = [[self alloc] init];
    profile.mode = LMStreamModeSecondMonitor;
    profile.resolution = CGSizeMake(1280, 960);
    profile.fps = 30;
    profile.bitrate = 6000;
    profile.codec = LMStreamCodecH264;
    profile.audioPolicy = LMAudioPolicyDisabled;
    profile.inputMode = LMInputModeNativeTouch;
    profile.reconnectEnabled = YES;
    profile.hdrEnabled = NO;
    profile.experimental1080pEnabled = NO;
    return profile;
}

+ (LMDeviceCapabilityProfile)currentDeviceCapabilityProfile {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [self capabilityProfileForMachineIdentifier:[NSString stringWithUTF8String:systemInfo.machine]];
}

+ (LMDeviceCapabilityProfile)capabilityProfileForMachineIdentifier:(NSString *)machineIdentifier {
    if ([machineIdentifier isEqualToString:@"iPad4,1"] ||
        [machineIdentifier isEqualToString:@"iPad4,2"] ||
        [machineIdentifier isEqualToString:@"iPad4,3"]) {
        return LMDeviceCapabilityProfileIPadAir;
    }
    return LMDeviceCapabilityProfileGeneric;
}

+ (NSArray<NSValue *> *)supportedResolutionsForCapabilityProfile:(LMDeviceCapabilityProfile)capabilityProfile
                                           experimental1080pEnabled:(BOOL)experimental1080pEnabled {
    if (capabilityProfile == LMDeviceCapabilityProfileIPadAir) {
        NSMutableArray<NSValue *> *resolutions = [NSMutableArray arrayWithArray:@[
            [NSValue valueWithCGSize:CGSizeMake(1280, 960)],
            [NSValue valueWithCGSize:CGSizeMake(1024, 768)],
            [NSValue valueWithCGSize:CGSizeMake(1440, 1080)],
            [NSValue valueWithCGSize:CGSizeMake(1280, 720)]
        ]];
        if (experimental1080pEnabled) {
            [resolutions addObject:[NSValue valueWithCGSize:CGSizeMake(1920, 1080)]];
        }
        return resolutions;
    }

    return @[
        [NSValue valueWithCGSize:CGSizeMake(1280, 960)],
        [NSValue valueWithCGSize:CGSizeMake(1024, 768)],
        [NSValue valueWithCGSize:CGSizeMake(1440, 1080)],
        [NSValue valueWithCGSize:CGSizeMake(1280, 720)],
        [NSValue valueWithCGSize:CGSizeMake(1920, 1080)],
    ];
}

+ (instancetype)profileWithDictionary:(NSDictionary *)dictionary {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        return nil;
    }

    LMStreamProfile *profile = [[self alloc] init];
    profile.mode = [dictionary[@"mode"] integerValue];
    profile.resolution = CGSizeMake([dictionary[@"width"] doubleValue], [dictionary[@"height"] doubleValue]);
    profile.fps = [dictionary[@"fps"] integerValue];
    profile.bitrate = [dictionary[@"bitrate"] integerValue];
    profile.codec = [dictionary[@"codec"] integerValue];
    profile.audioPolicy = [dictionary[@"audioPolicy"] integerValue];
    profile.inputMode = [dictionary[@"inputMode"] integerValue];
    profile.reconnectEnabled = [dictionary[@"reconnectEnabled"] boolValue];
    profile.hdrEnabled = [dictionary[@"hdrEnabled"] boolValue];
    profile.framePacing = [dictionary[@"framePacing"] boolValue];
    profile.experimental1080pEnabled = [dictionary[@"experimental1080pEnabled"] boolValue];
    return profile;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"mode": @(self.mode),
        @"width": @(self.resolution.width),
        @"height": @(self.resolution.height),
        @"fps": @(self.fps),
        @"bitrate": @(self.bitrate),
        @"codec": @(self.codec),
        @"audioPolicy": @(self.audioPolicy),
        @"inputMode": @(self.inputMode),
        @"reconnectEnabled": @(self.reconnectEnabled),
        @"hdrEnabled": @(self.hdrEnabled),
        @"framePacing": @(self.framePacing),
        @"experimental1080pEnabled": @(self.experimental1080pEnabled),
    };
}

- (id)copyWithZone:(NSZone *)zone {
    LMStreamProfile *copy = [[[self class] allocWithZone:zone] init];
    copy.mode = self.mode;
    copy.resolution = self.resolution;
    copy.fps = self.fps;
    copy.bitrate = self.bitrate;
    copy.codec = self.codec;
    copy.audioPolicy = self.audioPolicy;
    copy.inputMode = self.inputMode;
    copy.reconnectEnabled = self.reconnectEnabled;
    copy.hdrEnabled = self.hdrEnabled;
    copy.framePacing = self.framePacing;
    copy.experimental1080pEnabled = self.experimental1080pEnabled;
    return copy;
}

- (BOOL)isEqual:(id)object {
    if (self == object) {
        return YES;
    }
    if (![object isKindOfClass:[LMStreamProfile class]]) {
        return NO;
    }

    LMStreamProfile *other = object;
    return self.mode == other.mode &&
        CGSizeEqualToSize(self.resolution, other.resolution) &&
        self.fps == other.fps &&
        self.bitrate == other.bitrate &&
        self.codec == other.codec &&
        self.audioPolicy == other.audioPolicy &&
        self.inputMode == other.inputMode &&
        self.reconnectEnabled == other.reconnectEnabled &&
        self.hdrEnabled == other.hdrEnabled &&
        self.framePacing == other.framePacing &&
        self.experimental1080pEnabled == other.experimental1080pEnabled;
}

- (NSUInteger)hash {
    return self.mode ^ self.fps ^ self.bitrate ^ self.codec ^ self.audioPolicy ^ self.inputMode;
}

- (BOOL)validateForCapabilityProfile:(LMDeviceCapabilityProfile)capabilityProfile error:(NSError **)error {
    void (^setError)(LMProfileValidationErrorCode, NSString *, NSString *) = ^(LMProfileValidationErrorCode code, NSString *field, NSString *reason) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LMProfileValidationDomain
                                         code:code
                                     userInfo:@{
                                         LMProfileValidationFieldKey: field,
                                         NSLocalizedDescriptionKey: reason,
                                     }];
        }
    };

    if (self.resolution.width <= 0) {
        setError(LMProfileValidationErrorInvalidValue, @"width", @"The stream profile width must be positive.");
        return NO;
    }
    if (self.resolution.height <= 0) {
        setError(LMProfileValidationErrorInvalidValue, @"height", @"The stream profile height must be positive.");
        return NO;
    }
    if (self.fps <= 0) {
        setError(LMProfileValidationErrorInvalidValue, @"fps", @"The stream profile frame rate must be positive.");
        return NO;
    }
    if (self.bitrate <= 0) {
        setError(LMProfileValidationErrorInvalidValue, @"bitrate", @"The stream profile bitrate must be positive.");
        return NO;
    }
    if (self.codec < LMStreamCodecH264 || self.codec > LMStreamCodecAV1) {
        setError(LMProfileValidationErrorUnsupportedCodec, @"codec", @"The stream profile selected an unknown codec.");
        return NO;
    }

    if (capabilityProfile == LMDeviceCapabilityProfileIPadAir) {
        if (self.codec != LMStreamCodecH264) {
            setError(LMProfileValidationErrorUnsupportedCodec, @"codec", @"The iPad Air profile supports H.264 only.");
            return NO;
        }
        if (self.hdrEnabled) {
            setError(LMProfileValidationErrorUnsupportedHDR, @"hdrEnabled", @"HDR is not supported by the iPad Air profile.");
            return NO;
        }
        if (self.fps > 60) {
            setError(LMProfileValidationErrorUnsupportedFrameRate, @"fps", @"The iPad Air profile does not support this frame rate.");
            return NO;
        }
        BOOL is720p = self.resolution.width == 1280 && self.resolution.height == 720;
        BOOL isExperimental1080p = self.resolution.width == 1920 && self.resolution.height == 1080 && self.fps == 30;
        BOOL isFourByThree = CGSizeEqualToSize(self.resolution, CGSizeMake(1024, 768)) ||
            CGSizeEqualToSize(self.resolution, CGSizeMake(1280, 960)) ||
            CGSizeEqualToSize(self.resolution, CGSizeMake(1440, 1080));
        if (isFourByThree && self.fps != 30) {
            setError(LMProfileValidationErrorUnsupportedFrameRate, @"fps", @"Use 30 FPS for a 4:3 stream on the first iPad Air.");
            return NO;
        }
        if (!isFourByThree && !is720p && !(isExperimental1080p && self.experimental1080pEnabled)) {
            setError(LMProfileValidationErrorExperimentalResolutionDisabled, @"resolution", @"1080p30 must be explicitly enabled on the iPad Air profile.");
            return NO;
        }
    }

    if (error != NULL) {
        *error = nil;
    }
    return YES;
}

@end

@implementation LMStreamProfileStore

+ (NSString *)defaultsKeyForHost:(NSString *)hostUuid profileName:(NSString *)profileName {
    if (hostUuid.length == 0 || profileName.length == 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"Moonlight.StreamProfile.%@.%@", hostUuid, profileName];
}

+ (LMStreamProfile *)loadProfileForHost:(NSString *)hostUuid profileName:(NSString *)profileName {
    NSString *key = [self defaultsKeyForHost:hostUuid profileName:profileName];
    if (key == nil) {
        return nil;
    }
    return [LMStreamProfile profileWithDictionary:[[NSUserDefaults standardUserDefaults] dictionaryForKey:key]];
}

+ (void)saveProfile:(LMStreamProfile *)profile forHost:(NSString *)hostUuid profileName:(NSString *)profileName {
    NSString *key = [self defaultsKeyForHost:hostUuid profileName:profileName];
    if (key == nil || profile == nil) {
        return;
    }
    [[NSUserDefaults standardUserDefaults] setObject:profile.dictionaryRepresentation forKey:key];
}

@end

@implementation LMReconnectStateMachine {
    NSString *_host;
    LMStreamProfile *_profile;
    LMStreamState _state;
    NSInteger _retryCount;
}

@synthesize host = _host;
@synthesize profile = _profile;
@synthesize state = _state;
@synthesize retryCount = _retryCount;

- (instancetype)initWithHost:(NSString *)host profile:(LMStreamProfile *)profile {
    self = [super init];
    if (self != nil) {
        _host = [host copy];
        _profile = [profile copy];
        _state = LMStreamStateConnecting;
    }
    return self;
}

- (BOOL)beginReconnect {
    if (_state == LMStreamStateStopped || _state == LMStreamStateFailed || _retryCount >= LMReconnectRetryBudget) {
        _state = LMStreamStateFailed;
        return NO;
    }
    _retryCount++;
    _state = LMStreamStateReconnecting;
    return YES;
}

- (NSTimeInterval)retryDelay {
    switch (_retryCount) {
        case 1:
            return 1.0;
        case 2:
            return 2.0;
        default:
            return MIN(LMReconnectMaximumDelay, 4.0);
    }
}

- (void)connectionStarted {
    _state = LMStreamStateStreaming;
}

- (void)fail {
    _state = LMStreamStateFailed;
}

- (void)stop {
    _state = LMStreamStateStopped;
}

@end

@implementation StreamConfiguration
@synthesize host, httpsPort, appID, width, height, frameRate, bitRate, riKeyId, riKey, gamepadMask, appName, optimizeGameSettings, playAudioOnPC, swapABXYButtons, audioConfiguration, supportedVideoFormats, multiController, serverCert, rtspSessionUrl, serverCodecModeSupport, inputMode, profile;

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        self.inputMode = LMInputModeNativeTouch;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    StreamConfiguration *copy = [[[self class] allocWithZone:zone] init];
    copy.host = [self.host copy];
    copy.httpsPort = self.httpsPort;
    copy.appVersion = [self.appVersion copy];
    copy.gfeVersion = [self.gfeVersion copy];
    copy.appID = [self.appID copy];
    copy.appName = [self.appName copy];
    copy.rtspSessionUrl = [self.rtspSessionUrl copy];
    copy.serverCodecModeSupport = self.serverCodecModeSupport;
    copy.width = self.width;
    copy.height = self.height;
    copy.frameRate = self.frameRate;
    copy.bitRate = self.bitRate;
    copy.riKeyId = self.riKeyId;
    copy.riKey = [self.riKey copy];
    copy.gamepadMask = self.gamepadMask;
    copy.optimizeGameSettings = self.optimizeGameSettings;
    copy.playAudioOnPC = self.playAudioOnPC;
    copy.swapABXYButtons = self.swapABXYButtons;
    copy.audioConfiguration = self.audioConfiguration;
    copy.supportedVideoFormats = self.supportedVideoFormats;
    copy.multiController = self.multiController;
    copy.useFramePacing = self.useFramePacing;
    copy.serverCert = [self.serverCert copy];
    copy.inputMode = self.inputMode;
    copy.profile = [self.profile copy];
    return copy;
}

- (BOOL)applyProfile:(LMStreamProfile *)profile error:(NSError **)error {
    return [self applyProfile:profile
        forCapabilityProfile:[LMStreamProfile currentDeviceCapabilityProfile]
                         error:error];
}

- (BOOL)applyProfile:(LMStreamProfile *)profile
forCapabilityProfile:(LMDeviceCapabilityProfile)capabilityProfile
               error:(NSError **)error {
    if (profile == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:LMProfileValidationDomain
                                         code:LMProfileValidationErrorInvalidValue
                                     userInfo:@{
                                         LMProfileValidationFieldKey: @"profile",
                                         NSLocalizedDescriptionKey: @"A stream profile is required.",
                                     }];
        }
        return NO;
    }
    if (![profile validateForCapabilityProfile:capabilityProfile error:error]) {
        return NO;
    }

    self.profile = [profile copy];
    self.width = (int)profile.resolution.width;
    self.height = (int)profile.resolution.height;
    self.frameRate = (int)profile.fps;
    self.bitRate = (int)profile.bitrate;
    self.useFramePacing = profile.framePacing;
    self.inputMode = profile.inputMode;
    self.playAudioOnPC = profile.audioPolicy == LMAudioPolicyHost;
    self.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    self.optimizeGameSettings = NO;
    self.gamepadMask = 0;
    self.multiController = NO;
    self.swapABXYButtons = NO;
    self.supportedVideoFormats = profile.codec == LMStreamCodecH264 ? VIDEO_FORMAT_H264 :
        (profile.codec == LMStreamCodecHEVC ? VIDEO_FORMAT_H265 : VIDEO_FORMAT_AV1_MAIN8);
    return YES;
}

@end
