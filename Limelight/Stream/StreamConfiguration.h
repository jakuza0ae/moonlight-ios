//
//  StreamConfiguration.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "../Input/InputMode.h"
#import <CoreGraphics/CoreGraphics.h>

typedef NS_ENUM(NSInteger, LMStreamMode) {
    LMStreamModeGame = 0,
    LMStreamModeSecondMonitor,
};

typedef NS_ENUM(NSInteger, LMStreamCodec) {
    LMStreamCodecH264 = 0,
    LMStreamCodecHEVC,
    LMStreamCodecAV1,
};

typedef NS_ENUM(NSInteger, LMAudioPolicy) {
    LMAudioPolicyDisabled = 0,
    LMAudioPolicyHost,
    LMAudioPolicyStream,
};

typedef NS_ENUM(NSInteger, LMDeviceCapabilityProfile) {
    LMDeviceCapabilityProfileGeneric = 0,
    LMDeviceCapabilityProfileIPadAir,
};

typedef NS_ENUM(NSInteger, LMStreamState) {
    LMStreamStateConnecting = 0,
    LMStreamStateWaitingForDisplay,
    LMStreamStateStreaming,
    LMStreamStateReconnecting,
    LMStreamStateFailed,
    LMStreamStateStopped,
};

typedef NS_ENUM(NSInteger, LMProfileValidationErrorCode) {
    LMProfileValidationErrorInvalidValue = 1,
    LMProfileValidationErrorUnsupportedCodec,
    LMProfileValidationErrorUnsupportedHDR,
    LMProfileValidationErrorUnsupportedFrameRate,
    LMProfileValidationErrorExperimentalResolutionDisabled,
};

FOUNDATION_EXPORT NSString * const LMProfileValidationDomain;
FOUNDATION_EXPORT NSString * const LMProfileValidationFieldKey;
FOUNDATION_EXPORT NSInteger const LMReconnectRetryBudget;
FOUNDATION_EXPORT NSTimeInterval const LMReconnectMaximumDelay;

@interface LMStreamProfile : NSObject <NSCopying>

@property (nonatomic) LMStreamMode mode;
@property (nonatomic) CGSize resolution;
@property (nonatomic) NSInteger fps;
@property (nonatomic) NSInteger bitrate;
@property (nonatomic) LMStreamCodec codec;
@property (nonatomic) LMAudioPolicy audioPolicy;
@property (nonatomic) LMInputMode inputMode;
@property (nonatomic) BOOL reconnectEnabled;
@property (nonatomic) BOOL hdrEnabled;
@property (nonatomic) BOOL experimental1080pEnabled;

+ (instancetype)defaultSecondMonitorProfile;
+ (LMDeviceCapabilityProfile)currentDeviceCapabilityProfile;
+ (LMDeviceCapabilityProfile)capabilityProfileForMachineIdentifier:(NSString *)machineIdentifier;
+ (NSArray<NSValue *> *)supportedResolutionsForCapabilityProfile:(LMDeviceCapabilityProfile)capabilityProfile
                                           experimental1080pEnabled:(BOOL)experimental1080pEnabled;
+ (instancetype)profileWithDictionary:(NSDictionary *)dictionary;
- (NSDictionary *)dictionaryRepresentation;
- (BOOL)validateForCapabilityProfile:(LMDeviceCapabilityProfile)capabilityProfile error:(NSError **)error;

@end

@interface LMStreamProfileStore : NSObject

+ (NSString *)defaultsKeyForHost:(NSString *)hostUuid profileName:(NSString *)profileName;
+ (LMStreamProfile *)loadProfileForHost:(NSString *)hostUuid profileName:(NSString *)profileName;
+ (void)saveProfile:(LMStreamProfile *)profile forHost:(NSString *)hostUuid profileName:(NSString *)profileName;

@end

@interface LMReconnectStateMachine : NSObject

@property (nonatomic, readonly) NSString *host;
@property (nonatomic, readonly) LMStreamProfile *profile;
@property (nonatomic, readonly) LMStreamState state;
@property (nonatomic, readonly) NSInteger retryCount;
@property (nonatomic, readonly) NSTimeInterval retryDelay;

- (instancetype)initWithHost:(NSString *)host profile:(LMStreamProfile *)profile;
- (BOOL)beginReconnect;
- (void)connectionStarted;
- (void)fail;
- (void)stop;

@end

@interface StreamConfiguration : NSObject <NSCopying>

@property NSString* host;
@property unsigned short httpsPort;
@property NSString* appVersion;
@property NSString* gfeVersion;
@property NSString* appID;
@property NSString* appName;
@property NSString* rtspSessionUrl;
@property int serverCodecModeSupport;
@property int width;
@property int height;
@property int frameRate;
@property int bitRate;
@property int riKeyId;
@property NSData* riKey;
@property int gamepadMask;
@property BOOL optimizeGameSettings;
@property BOOL playAudioOnPC;
@property BOOL swapABXYButtons;
@property int audioConfiguration;
@property int supportedVideoFormats;
@property BOOL multiController;
@property BOOL useFramePacing;
@property NSData* serverCert;
@property LMInputMode inputMode;
@property (nonatomic, copy) LMStreamProfile *profile;

- (BOOL)applyProfile:(LMStreamProfile *)profile error:(NSError **)error;
- (BOOL)applyProfile:(LMStreamProfile *)profile
forCapabilityProfile:(LMDeviceCapabilityProfile)capabilityProfile
               error:(NSError **)error;

@end
