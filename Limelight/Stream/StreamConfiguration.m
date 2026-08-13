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

@implementation LMStreamProfile

+ (instancetype)defaultSecondMonitorProfile {
    LMStreamProfile *profile = [[self alloc] init];
    profile.mode = LMStreamModeSecondMonitor;
    profile.resolution = CGSizeMake(1280, 720);
    profile.fps = 30;
    profile.bitrate = 5000;
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
    NSString *machine = [NSString stringWithUTF8String:systemInfo.machine];
    if ([machine hasPrefix:@"iPad4,"]) {
        return LMDeviceCapabilityProfileIPadAir;
    }
    return LMDeviceCapabilityProfileGeneric;
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

    if (self.resolution.width <= 0 || self.resolution.height <= 0 || self.fps <= 0 || self.bitrate <= 0) {
        setError(LMProfileValidationErrorInvalidValue, @"resolution", @"The stream profile contains an invalid numeric value.");
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
        if (!is720p && !(isExperimental1080p && self.experimental1080pEnabled)) {
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
        _inputMode = LMInputModeNativeTouch;
    }
    return self;
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
