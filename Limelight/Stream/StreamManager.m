//
//  StreamManager.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamManager.h"
#import "CryptoManager.h"
#import "HttpManager.h"
#import "Utils.h"

#import "StreamView.h"
#import "ServerInfoResponse.h"
#import "HttpResponse.h"
#import "HttpRequest.h"
#import "IdManager.h"

#include <Limelight.h>

@interface LMStreamCallbackProxy : NSObject <ConnectionCallbacks>

@property (nonatomic, weak) id<ConnectionCallbacks> target;
@property (nonatomic) BOOL active;

- (instancetype)initWithTarget:(id<ConnectionCallbacks>)target;

@end

@implementation LMStreamCallbackProxy

- (instancetype)initWithTarget:(id<ConnectionCallbacks>)target {
    self = [super init];
    if (self != nil) {
        _target = target;
        _active = YES;
    }
    return self;
}

- (BOOL)shouldForward {
    return self.active && self.target != nil;
}

- (void)connectionStarted { if ([self shouldForward]) [self.target connectionStarted]; }
- (void)connectionTerminated:(int)errorCode { if ([self shouldForward]) [self.target connectionTerminated:errorCode]; }
- (void)stageStarting:(const char *)stageName { if ([self shouldForward]) [self.target stageStarting:stageName]; }
- (void)stageComplete:(const char *)stageName { if ([self shouldForward]) [self.target stageComplete:stageName]; }
- (void)stageFailed:(const char *)stageName withError:(int)errorCode portTestFlags:(int)portTestFlags {
    if ([self shouldForward]) [self.target stageFailed:stageName withError:errorCode portTestFlags:portTestFlags];
}
- (void)launchFailed:(NSString *)message { if ([self shouldForward]) [self.target launchFailed:message]; }
- (void)rumble:(unsigned short)controllerNumber lowFreqMotor:(unsigned short)lowFreqMotor highFreqMotor:(unsigned short)highFreqMotor {
    if ([self shouldForward]) [self.target rumble:controllerNumber lowFreqMotor:lowFreqMotor highFreqMotor:highFreqMotor];
}
- (void)connectionStatusUpdate:(int)status { if ([self shouldForward]) [self.target connectionStatusUpdate:status]; }
- (void)setHdrMode:(bool)enabled { if ([self shouldForward]) [self.target setHdrMode:enabled]; }
- (void)rumbleTriggers:(uint16_t)controllerNumber leftTrigger:(uint16_t)leftTrigger rightTrigger:(uint16_t)rightTrigger {
    if ([self shouldForward]) [self.target rumbleTriggers:controllerNumber leftTrigger:leftTrigger rightTrigger:rightTrigger];
}
- (void)setMotionEventState:(uint16_t)controllerNumber motionType:(uint8_t)motionType reportRateHz:(uint16_t)reportRateHz {
    if ([self shouldForward]) [self.target setMotionEventState:controllerNumber motionType:motionType reportRateHz:reportRateHz];
}
- (void)setControllerLed:(uint16_t)controllerNumber r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b {
    if ([self shouldForward]) [self.target setControllerLed:controllerNumber r:r g:g b:b];
}
- (void)videoContentShown { if ([self shouldForward]) [self.target videoContentShown]; }

@end

NSString * const LMSecondMonitorDiagnosticUnavailable = @"unavailable";
NSUInteger const LMSecondMonitorDiagnosticFieldMaximumLength = 128;
NSUInteger const LMSecondMonitorDiagnosticOverlayMaximumLength = 2048;

@implementation LMStreamDiagnostics
@end

static NSString *LMBoundedDiagnosticString(NSString *value) {
    if (value.length == 0) {
        return LMSecondMonitorDiagnosticUnavailable;
    }

    NSMutableString *sanitized = [[NSMutableString alloc] initWithCapacity:MIN(value.length, LMSecondMonitorDiagnosticFieldMaximumLength)];
    NSUInteger characterCount = MIN(value.length, LMSecondMonitorDiagnosticFieldMaximumLength);
    for (NSUInteger index = 0; index < characterCount; index++) {
        unichar character = [value characterAtIndex:index];
        if (character < 0x20 || character == 0x7f) {
            [sanitized appendString:@"?"];
        }
        else {
            [sanitized appendFormat:@"%C", character];
        }
    }

    NSString *lowercase = [sanitized lowercaseString];
    NSArray<NSString *> *dangerousTerms = @[@"password", @"pairing", @"secret", @"private key", @"command", @"whoami", @"powershell", @"cmd.exe"];
    for (NSString *term in dangerousTerms) {
        if ([lowercase containsString:term]) {
            return @"redacted";
        }
    }
    for (NSString *symbol in @[@";", @"|", @"&", @"$", @"`"]) {
        if ([sanitized containsString:symbol]) {
            return @"redacted";
        }
    }

    if (value.length > LMSecondMonitorDiagnosticFieldMaximumLength) {
        return [[sanitized substringToIndex:LMSecondMonitorDiagnosticFieldMaximumLength - 3] stringByAppendingString:@"..."];
    }
    return sanitized;
}

static NSString *LMBoundedDiagnosticStringAllowingEmpty(NSString *value) {
    return value.length == 0 ? @"" : LMBoundedDiagnosticString(value);
}

static NSString *LMRedactedDiagnosticError(NSString *error) {
    if (error.length == 0) {
        return LMSecondMonitorDiagnosticUnavailable;
    }

    NSArray<NSString *> *safeErrors = @[@"connection_terminated", @"stage_failed", @"launch_failed", @"reconnect_failed"];
    if ([safeErrors containsObject:error]) {
        return LMBoundedDiagnosticString(error);
    }
    return @"redacted";
}

NSString *LMFormatSecondMonitorDiagnostics(LMStreamDiagnostics *diagnostics) {
    if (diagnostics == nil) {
        return @"Diagnostics unavailable.";
    }

    NSString *fps = diagnostics.fps != nil ? [NSString stringWithFormat:@"%.2f", diagnostics.fps.doubleValue] : LMSecondMonitorDiagnosticUnavailable;
    NSString *bitrate = diagnostics.bitrateKbps != nil ? [NSString stringWithFormat:@"%ld kbps", (long)diagnostics.bitrateKbps.integerValue] : LMSecondMonitorDiagnosticUnavailable;
    NSString *rtt = diagnostics.rttMs != nil ? [NSString stringWithFormat:@"%ld ms", (long)diagnostics.rttMs.integerValue] : LMSecondMonitorDiagnosticUnavailable;
    NSString *droppedFrames = diagnostics.droppedFrames != nil ? [NSString stringWithFormat:@"%ld", (long)diagnostics.droppedFrames.integerValue] : LMSecondMonitorDiagnosticUnavailable;
    NSString *reconnects = diagnostics.reconnectCount != nil ? [NSString stringWithFormat:@"%ld", (long)diagnostics.reconnectCount.integerValue] : LMSecondMonitorDiagnosticUnavailable;
    NSString *formatted = [NSString stringWithFormat:@"State: %@\nHost display: %@\nMapped output: %@\nCapture backend: %@\nEncoder: %@\nCodec: %@\nResolution: %@\nFPS: %@\nBitrate: %@\nRTT: %@\nDropped frames: %@\nReconnects: %@\nLast error: %@",
                           LMBoundedDiagnosticString(diagnostics.state),
                           LMBoundedDiagnosticString(diagnostics.hostDisplayID),
                           LMBoundedDiagnosticString(diagnostics.mappedOutput),
                           LMBoundedDiagnosticString(diagnostics.captureBackend),
                           LMBoundedDiagnosticString(diagnostics.encoder),
                           LMBoundedDiagnosticString(diagnostics.codec),
                           LMBoundedDiagnosticString(diagnostics.resolution),
                           fps,
                           bitrate,
                           rtt,
                           droppedFrames,
                           reconnects,
                           LMRedactedDiagnosticError(diagnostics.lastError)];
    if (formatted.length <= LMSecondMonitorDiagnosticOverlayMaximumLength) {
        return formatted;
    }
    return [[formatted substringToIndex:LMSecondMonitorDiagnosticOverlayMaximumLength - 3] stringByAppendingString:@"..."];
}

NSString *LMFormatLegacyStatsOverlay(NSInteger width,
                                     NSInteger height,
                                     double fps,
                                     NSString *codec,
                                     double droppedPercent,
                                     NSString *latency,
                                     NSString *hostProcessing) {
    NSString *formatted = [NSString stringWithFormat:@"Video stream: %ldx%ld %.2f FPS (Codec: %@)\nFrames dropped by your network connection: %.2f%%\nAverage network latency: %@%@",
                           (long)width,
                           (long)height,
                           fps,
                           LMBoundedDiagnosticString(codec),
                           droppedPercent,
                           LMBoundedDiagnosticString(latency),
                           LMBoundedDiagnosticStringAllowingEmpty(hostProcessing)];
    if (formatted.length <= LMSecondMonitorDiagnosticOverlayMaximumLength) {
        return formatted;
    }
    return [[formatted substringToIndex:LMSecondMonitorDiagnosticOverlayMaximumLength - 3] stringByAppendingString:@"..."];
}

@implementation StreamManager {
    StreamConfiguration* _config;

    UIView* _renderView;
    id<ConnectionCallbacks> _callbacks;
    Connection* _connection;
    NSError *_configurationError;
    LMStreamCallbackProxy *_callbackProxy;
    BOOL _stopped;
    NSInteger _reconnectCount;
    NSString *_lastError;
    NSString *_diagnosticState;
}

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callbacks {
    self = [super init];
    _config = config;
    _renderView = view;
    _callbackProxy = [[LMStreamCallbackProxy alloc] initWithTarget:callbacks];
    _callbacks = _callbackProxy;
    _diagnosticState = @"connecting";
    if (_config.profile != nil) {
        NSError *configurationError = nil;
        [_config applyProfile:_config.profile error:&configurationError];
        _configurationError = configurationError;
    }
    _config.riKey = [Utils randomBytes:16];
    _config.riKeyId = arc4random();
    return self;
}

- (void)main {
    if (_stopped) {
        return;
    }

    if (_configurationError != nil) {
        [_callbacks launchFailed:_configurationError.localizedDescription];
        return;
    }

    [CryptoManager generateKeyPairUsingSSL];
    
    HttpManager* hMan = [[HttpManager alloc] initWithAddress:_config.host httpsPort:_config.httpsPort
                                                     serverCert:_config.serverCert];
    
    ServerInfoResponse* serverInfoResp = [[ServerInfoResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:serverInfoResp withUrlRequest:[hMan newServerInfoRequest:false]
                                       fallbackError:401 fallbackRequest:[hMan newHttpServerInfoRequest]]];
    NSString* pairStatus = [serverInfoResp getStringTag:@"PairStatus"];
    NSString* appversion = [serverInfoResp getStringTag:@"appversion"];
    NSString* gfeVersion = [serverInfoResp getStringTag:@"GfeVersion"];
    NSString* serverState = [serverInfoResp getStringTag:@"state"];
    if (![serverInfoResp isStatusOk]) {
        [_callbacks launchFailed:serverInfoResp.statusMessage];
        return;
    }
    else if (pairStatus == NULL || appversion == NULL || serverState == NULL) {
        [_callbacks launchFailed:@"Failed to connect to PC"];
        return;
    }
    
    if (![pairStatus isEqualToString:@"1"]) {
        // Not paired
        [_callbacks launchFailed:@"Device not paired to PC"];
        return;
    }
    
    // Only perform this check on GFE (as indicated by MJOLNIR in state value)
    if ((_config.width > 4096 || _config.height > 4096) && [serverState containsString:@"MJOLNIR"]) {
        // Pascal added support for 8K HEVC encoding support. Maxwell 2 could encode HEVC but only up to 4K.
        // We can't directly identify Pascal, but we can look for HEVC Main10 which was added in the same generation.
        NSString* codecSupport = [serverInfoResp getStringTag:@"ServerCodecModeSupport"];
        if (codecSupport == nil || !([codecSupport intValue] & 0x200)) {
            [_callbacks launchFailed:@"Your host PC's GPU doesn't support streaming video resolutions over 4K."];
            return;
        }
    }
    
    // Populate the config's version fields from serverinfo
    _config.appVersion = appversion;
    _config.gfeVersion = gfeVersion;
    
    // resumeApp and launchApp handle calling launchFailed
    NSString* sessionUrl;
    if ([serverState hasSuffix:@"_SERVER_BUSY"]) {
        if (_config.requireMatchingAppOnResume &&
            ![_config.appID isEqualToString:[[serverInfoResp getStringTag:TAG_CURRENT_GAME] trim]]) {
            [_callbacks launchFailed:@"Another app is running on this PC. Open the computer in StreamDesk to choose what to do."];
            return;
        }
        // App already running, resume it
        if (![self resumeApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    } else {
        // Start app
        if (![self launchApp:hMan receiveSessionUrl:&sessionUrl]) {
            return;
        }
    }
    
    // Populate RTSP session URL from launch/resume response
    _config.rtspSessionUrl = sessionUrl;
    
    // Initializing the renderer must be done on the main thread
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_stopped) {
            return;
        }
        VideoDecoderRenderer* renderer = [[VideoDecoderRenderer alloc] initWithView:self->_renderView callbacks:self->_callbacks streamAspectRatio:(float)self->_config.width / (float)self->_config.height useFramePacing:self->_config.useFramePacing];
        self->_connection = [[Connection alloc] initWithConfig:self->_config renderer:renderer connectionCallbacks:self->_callbacks];
        NSOperationQueue* opQueue = [[NSOperationQueue alloc] init];
        [opQueue addOperation:self->_connection];
    });
}

- (void) stopStream
{
    [self stopStreamWithCompletion:nil];
}

- (void) stopStreamWithCompletion:(void (^)(void))completion
{
    _stopped = YES;
    _callbackProxy.active = NO;
    Connection *connection = _connection;
    _connection = nil;
    if (connection != nil) {
        [connection terminateWithCompletion:completion];
    }
    else if (completion != nil) {
        dispatch_async(dispatch_get_main_queue(), completion);
    }
}

- (void)setReconnectCount:(NSInteger)reconnectCount {
    _reconnectCount = MAX(0, reconnectCount);
}

- (void)setDiagnosticState:(NSString *)state {
    _diagnosticState = [state copy];
}

- (void)setLastError:(NSString *)lastError {
    _lastError = [lastError copy];
}

- (BOOL) launchApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* launchResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:launchResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"launch" config:_config]]];
    NSString *gameSession = [launchResp getStringTag:@"gamesession"];
    if (![launchResp isStatusOk]) {
        [_callbacks launchFailed:launchResp.statusMessage];
        Log(LOG_E, @"Failed Launch Response: %@", launchResp.statusMessage);
        return FALSE;
    } else if (gameSession == NULL || [gameSession isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to launch app"];
        Log(LOG_E, @"Failed to parse game session");
        return FALSE;
    }
    
    *sessionUrl = [launchResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (BOOL) resumeApp:(HttpManager*)hMan receiveSessionUrl:(NSString**)sessionUrl {
    HttpResponse* resumeResp = [[HttpResponse alloc] init];
    [hMan executeRequestSynchronously:[HttpRequest requestForResponse:resumeResp withUrlRequest:[hMan newLaunchOrResumeRequest:@"resume" config:_config]]];
    NSString* resume = [resumeResp getStringTag:@"resume"];
    if (![resumeResp isStatusOk]) {
        [_callbacks launchFailed:resumeResp.statusMessage];
        Log(LOG_E, @"Failed Resume Response: %@", resumeResp.statusMessage);
        return FALSE;
    } else if (resume == NULL || [resume isEqualToString:@"0"]) {
        [_callbacks launchFailed:@"Failed to resume app"];
        Log(LOG_E, @"Failed to parse resume response");
        return FALSE;
    }
    
    *sessionUrl = [resumeResp getStringTag:@"sessionUrl0"];
    return TRUE;
}

- (LMStreamDiagnostics *)getDiagnostics {
    LMStreamDiagnostics *diagnostics = [[LMStreamDiagnostics alloc] init];
    diagnostics.state = _diagnosticState ?: @"connecting";
    diagnostics.resolution = _config.width > 0 && _config.height > 0 ? [NSString stringWithFormat:@"%dx%d", _config.width, _config.height] : nil;
    diagnostics.bitrateKbps = _config.bitRate > 0 ? @(_config.bitRate) : nil;
    diagnostics.reconnectCount = @(_reconnectCount);
    diagnostics.lastError = _lastError;
    diagnostics.codec = [_connection getActiveCodecName];

    video_stats_t stats;
    if (_connection == nil || ![_connection getVideoStats:&stats]) {
        return diagnostics;
    }

    CFTimeInterval interval = stats.endTime - stats.startTime;
    if (interval > 0) {
        diagnostics.fps = @(stats.totalFrames / interval);
    }
    diagnostics.droppedFrames = @(stats.networkDroppedFrames);

    uint32_t rtt, variance;
    if (LiGetEstimatedRttInfo(&rtt, &variance)) {
        diagnostics.rttMs = @((NSInteger)rtt);
    }
    return diagnostics;
}

- (NSString*) getStatsOverlayText {
    if (!_connection) {
        return nil;
    }

    if (_config.profile == nil || _config.profile.mode != LMStreamModeSecondMonitor) {
        video_stats_t stats;
        if (![_connection getVideoStats:&stats]) {
            return nil;
        }

        uint32_t rtt, variance;
        NSString *latencyString;
        if (LiGetEstimatedRttInfo(&rtt, &variance)) {
            latencyString = [NSString stringWithFormat:@"%u ms (variance: %u ms)", rtt, variance];
        }
        else {
            latencyString = @"N/A";
        }

        NSString *hostProcessingString;
        if (stats.framesWithHostProcessingLatency != 0) {
            hostProcessingString = [NSString stringWithFormat:@"\nHost processing latency min/max/avg: %.1f/%.1f/%.1f ms",
                                    stats.minHostProcessingLatency / 10.f,
                                    stats.maxHostProcessingLatency / 10.f,
                                    (float)stats.totalHostProcessingLatency / stats.framesWithHostProcessingLatency / 10.f];
        }
        else {
            hostProcessingString = @"";
        }

        float interval = stats.endTime - stats.startTime;
        return LMFormatLegacyStatsOverlay(_config.width,
                                          _config.height,
                                          stats.totalFrames / interval,
                                          [_connection getActiveCodecName],
                                          stats.networkDroppedFrames / interval,
                                          latencyString,
                                          hostProcessingString);
    }

    return LMFormatSecondMonitorDiagnostics([self getDiagnostics]);
}

@end
