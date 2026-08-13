//
//  StreamManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import "Connection.h"

FOUNDATION_EXPORT NSString * const LMSecondMonitorDiagnosticUnavailable;
FOUNDATION_EXPORT NSUInteger const LMSecondMonitorDiagnosticFieldMaximumLength;
FOUNDATION_EXPORT NSUInteger const LMSecondMonitorDiagnosticOverlayMaximumLength;

@interface LMStreamDiagnostics : NSObject

@property (nonatomic, copy) NSString *state;
@property (nonatomic, copy, nullable) NSString *hostDisplayID;
@property (nonatomic, copy, nullable) NSString *mappedOutput;
@property (nonatomic, copy, nullable) NSString *captureBackend;
@property (nonatomic, copy, nullable) NSString *encoder;
@property (nonatomic, copy, nullable) NSString *codec;
@property (nonatomic, copy, nullable) NSString *resolution;
@property (nonatomic, copy, nullable) NSNumber *fps;
@property (nonatomic, copy, nullable) NSNumber *bitrateKbps;
@property (nonatomic, copy, nullable) NSNumber *rttMs;
@property (nonatomic, copy, nullable) NSNumber *droppedFrames;
@property (nonatomic, copy, nullable) NSNumber *reconnectCount;
@property (nonatomic, copy, nullable) NSString *lastError;

@end

FOUNDATION_EXPORT NSString *LMFormatSecondMonitorDiagnostics(LMStreamDiagnostics *diagnostics);
FOUNDATION_EXPORT NSString *LMFormatLegacyStatsOverlay(NSInteger width,
                                                        NSInteger height,
                                                        double fps,
                                                        NSString *codec,
                                                        double droppedPercent,
                                                        NSString *latency,
                                                        NSString *hostProcessing);

@interface StreamManager : NSOperation

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callback;

- (void) stopStream;
- (void) stopStreamWithCompletion:(void (^)(void))completion;
- (LMStreamDiagnostics *)getDiagnostics;
- (void)setDiagnosticState:(NSString *)state;
- (void)setReconnectCount:(NSInteger)reconnectCount;
- (void)setLastError:(NSString *)lastError;

- (NSString*) getStatsOverlayText;

@end
