//
//  StreamManager.h
//  Moonlight
//
//  Created by Diego Waxemberg on 10/20/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamConfiguration.h"
#import "Connection.h"

@interface LMStreamDiagnostics : NSObject

@property (nonatomic, copy) NSString *hostDisplayID;
@property (nonatomic, copy) NSString *mappedOutput;
@property (nonatomic, copy) NSString *captureBackend;
@property (nonatomic, copy) NSString *encoder;
@property (nonatomic, copy) NSString *codec;
@property (nonatomic) NSInteger width;
@property (nonatomic) NSInteger height;
@property (nonatomic) double fps;
@property (nonatomic) NSInteger bitrateKbps;
@property (nonatomic) NSInteger rttMs;
@property (nonatomic) NSInteger droppedFrames;
@property (nonatomic) NSInteger reconnectCount;
@property (nonatomic, copy) NSString *lastError;

@end

FOUNDATION_EXPORT NSString *LMFormatSecondMonitorDiagnostics(LMStreamDiagnostics *diagnostics);

@interface StreamManager : NSOperation

- (id) initWithConfig:(StreamConfiguration*)config renderView:(UIView*)view connectionCallbacks:(id<ConnectionCallbacks>)callback;

- (void) stopStream;
- (void) stopStreamWithCompletion:(void (^)(void))completion;
- (LMStreamDiagnostics *)getDiagnostics;
- (void)setReconnectCount:(NSInteger)reconnectCount;
- (void)setLastError:(NSString *)lastError;

- (NSString*) getStatsOverlayText;

@end
