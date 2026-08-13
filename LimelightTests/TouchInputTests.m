#import <XCTest/XCTest.h>

#import "AbsoluteTouchHandler.h"
#import "RelativeTouchHandler.h"
#import "StreamConfiguration.h"

@interface TouchInputTests : XCTestCase
@end

@implementation TouchInputTests

- (void)testAspectFitVideoMapsTheDisplayedCenter {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(0, 96, 1024, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(512, 384),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.5, 0.0001);
}

- (void)testCroppedVideoMapsTheVisibleViewportIntoTheVideo {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(-128, -64, 1280, 896);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(0, 0),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.1, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 64.0 / 896.0, 0.0001);
}

- (void)testLandscapeVideoUsesTheDisplayedRectAfterRotation {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(128, 0, 768, 768);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(512, 192),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.5, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.25, 0.0001);
}

- (void)testPointOutsideDisplayedVideoClampsToTheNearestVideoEdge {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(128, 96, 768, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(0, 0),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.0, 0.0001);
}

- (void)testVideoEdgesClampNormalizedCoordinatesToUnitRange {
    CGRect videoBounds = CGRectMake(0, 0, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(128, 96, 768, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(1024, 768),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 1.0, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 1.0, 0.0001);
}

- (void)testDisplayedRectMappingHonorsNonZeroVideoBoundsOrigin {
    CGRect videoBounds = CGRectMake(10, 20, 1024, 768);
    CGRect displayedVideoRect = CGRectMake(138, 116, 768, 576);

    CGPoint normalized = LMNormalizedPointForTouch(CGPointMake(10, 20),
                                                    videoBounds,
                                                    displayedVideoRect);

    XCTAssertEqualWithAccuracy(normalized.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(normalized.y, 0.0, 0.0001);
}

- (void)testTwoFingerScrollUsesTheCenterMovementDelta {
    CGPoint delta = LMScrollDeltaForTouchMovement(CGPointMake(100, 200),
                                                   CGPointMake(100, 224));

    XCTAssertEqualWithAccuracy(delta.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(delta.y, 24.0, 0.0001);
}

- (void)testHybridRoutesSingleTouchToNativeAndMultiTouchToMouse {
    XCTAssertEqual(LMInputRouteForMode(LMInputModeHybrid, 1, YES), LMInputRouteNativeTouch);
    XCTAssertEqual(LMInputRouteForMode(LMInputModeHybrid, 2, YES), LMInputRouteMouseCompatibility);
    XCTAssertEqual(LMInputRouteForMode(LMInputModeHybrid, 3, YES), LMInputRouteMouseCompatibility);
}

- (void)testNativeHostFallbackRoutesEveryTouchToMouse {
    XCTAssertEqual(LMInputRouteForMode(LMInputModeNativeTouch, 1, NO), LMInputRouteMouseCompatibility);
    XCTAssertEqual(LMInputRouteForMode(LMInputModeNativeTouch, 2, NO), LMInputRouteMouseCompatibility);
}

- (void)testLongPressOnlyStartsWithExactlyOneActiveTouch {
    XCTAssertTrue(LMShouldStartLongPressForTouchCount(1));
    XCTAssertFalse(LMShouldStartLongPressForTouchCount(2));
    XCTAssertFalse(LMShouldStartLongPressForTouchCount(3));
}

- (void)testLongPressCancelsWhenActiveTouchCountIsNotOne {
    XCTAssertFalse(LMShouldCancelLongPressForTouchCount(1));
    XCTAssertTrue(LMShouldCancelLongPressForTouchCount(2));
    XCTAssertTrue(LMShouldCancelLongPressForTouchCount(3));
}

- (void)testTwoFingerScrollRequiresExactlyTwoActiveTouches {
    XCTAssertFalse(LMShouldSendTwoFingerScrollForTouchCount(1));
    XCTAssertTrue(LMShouldSendTwoFingerScrollForTouchCount(2));
    XCTAssertFalse(LMShouldSendTwoFingerScrollForTouchCount(3));
}

- (void)testPointerMapKeepsStableIdsAndReleasesIndividualContacts {
    LMActiveTouchPointerMap *map = [[LMActiveTouchPointerMap alloc] init];
    NSObject *firstTouch = [[NSObject alloc] init];
    NSObject *secondTouch = [[NSObject alloc] init];

    uint32_t firstId = [map pointerIdForTouch:firstTouch create:YES];
    XCTAssertEqual(firstId, [map pointerIdForTouch:firstTouch create:NO]);
    XCTAssertNotEqual(firstId, [map pointerIdForTouch:secondTouch create:YES]);
    XCTAssertEqual(map.activePointerIds.count, 2U);

    [map releaseTouch:firstTouch];
    XCTAssertEqual(map.activePointerIds.count, 1U);
    XCTAssertEqual([map pointerIdForTouch:firstTouch create:NO], 0U);
}

- (void)testPointerMapCancelClearsEveryActiveContact {
    LMActiveTouchPointerMap *map = [[LMActiveTouchPointerMap alloc] init];
    [map pointerIdForTouch:[[NSObject alloc] init] create:YES];
    [map pointerIdForTouch:[[NSObject alloc] init] create:YES];

    [map cancelAllTouches];

    XCTAssertEqual(map.activePointerIds.count, 0U);
}

- (void)testStreamConfigurationPropagatesSelectedInputMode {
    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];
    configuration.inputMode = LMInputModeHybrid;

    XCTAssertEqual(configuration.inputMode, LMInputModeHybrid);
}

- (void)testStreamConfigurationDefaultsToNativeForDesktopProfiles {
    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];

    XCTAssertEqual(configuration.inputMode, LMInputModeNativeTouch);
}

- (void)testMouseCompatibilityTwoFingerGestureInitializesScrollAndCleansUp {
    LMCompatibilityGestureState state = LMCompatibilityGestureStateBegin(2, CGPointMake(100, 200));
    CGPoint delta = LMCompatibilityGestureStateMove(&state, 2, CGPointMake(100, 224));

    XCTAssertEqualWithAccuracy(delta.x, 0.0, 0.0001);
    XCTAssertEqualWithAccuracy(delta.y, 24.0, 0.0001);
    XCTAssertTrue(state.moved);
    XCTAssertFalse(LMCompatibilityGestureStateShouldTap(&state));

    LMCompatibilityGestureStateReset(&state);

    XCTAssertEqual(state.peakTouchCount, 0U);
    XCTAssertFalse(state.hasScrollCenter);
    XCTAssertFalse(state.moved);
}

- (void)testMouseCompatibilityTwoFingerTapInitializesAndResetsWithoutScroll {
    LMCompatibilityGestureState state = LMCompatibilityGestureStateBegin(2, CGPointMake(100, 200));

    XCTAssertTrue(state.hasScrollCenter);
    XCTAssertTrue(LMCompatibilityGestureStateShouldTap(&state));

    LMCompatibilityGestureStateReset(&state);

    XCTAssertFalse(LMCompatibilityGestureStateShouldTap(&state));
    XCTAssertEqual(state.peakTouchCount, 0U);
}

- (void)testIPadAirSecondMonitorProfileUsesSafeDefaults {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];

    XCTAssertEqual(profile.mode, LMStreamModeSecondMonitor);
    XCTAssertEqual(profile.resolution.width, 1280);
    XCTAssertEqual(profile.resolution.height, 720);
    XCTAssertEqual(profile.fps, 30);
    XCTAssertEqual(profile.codec, LMStreamCodecH264);
    XCTAssertEqual(profile.audioPolicy, LMAudioPolicyDisabled);
    XCTAssertEqual(profile.inputMode, LMInputModeNativeTouch);
    XCTAssertTrue(profile.reconnectEnabled);
}

- (void)testIPadAirRejectsUnsupportedCodec {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.codec = LMStreamCodecAV1;
    NSError *error = nil;

    XCTAssertFalse([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:&error]);
    XCTAssertEqual(error.code, LMProfileValidationErrorUnsupportedCodec);
    XCTAssertEqualObjects(error.userInfo[LMProfileValidationFieldKey], @"codec");
}

- (void)testIPadAirRejectsHEVC {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.codec = LMStreamCodecHEVC;
    NSError *error = nil;

    XCTAssertFalse([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:&error]);
    XCTAssertEqual(error.code, LMProfileValidationErrorUnsupportedCodec);
}

- (void)testIPadAirRejectsHDR {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.hdrEnabled = YES;
    NSError *error = nil;

    XCTAssertFalse([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:&error]);
    XCTAssertEqual(error.code, LMProfileValidationErrorUnsupportedHDR);
}

- (void)testIPadAirRejects120FPS {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.fps = 120;
    NSError *error = nil;

    XCTAssertFalse([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:&error]);
    XCTAssertEqual(error.code, LMProfileValidationErrorUnsupportedFrameRate);
}

- (void)testExperimental1080p30RequiresExplicitOptIn {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.resolution = CGSizeMake(1920, 1080);
    NSError *error = nil;

    XCTAssertFalse([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:&error]);
    XCTAssertEqual(error.code, LMProfileValidationErrorExperimentalResolutionDisabled);

    profile.experimental1080pEnabled = YES;
    error = nil;
    XCTAssertTrue([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:&error]);
    XCTAssertNil(error);
}

- (void)testReconnectStateRetainsHostAndProfileWithBoundedBackoff {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    LMReconnectStateMachine *state = [[LMReconnectStateMachine alloc] initWithHost:@"host-uuid"
                                                                              profile:profile];

    XCTAssertEqual(state.state, LMStreamStateConnecting);
    XCTAssertTrue([state beginReconnect]);
    XCTAssertEqual(state.state, LMStreamStateReconnecting);
    XCTAssertEqualObjects(state.host, @"host-uuid");
    XCTAssertEqualObjects(state.profile, profile);
    XCTAssertGreaterThan(state.retryDelay, 0.0);

    NSTimeInterval firstDelay = state.retryDelay;
    XCTAssertTrue([state beginReconnect]);
    XCTAssertGreaterThan(state.retryDelay, firstDelay);
    XCTAssertLessThanOrEqual(state.retryDelay, LMReconnectMaximumDelay);
}

- (void)testReconnectStateReachesUserVisibleFailureAfterRetryBudget {
    LMReconnectStateMachine *state = [[LMReconnectStateMachine alloc] initWithHost:@"host-uuid"
                                                                              profile:[LMStreamProfile defaultSecondMonitorProfile]];

    while ([state beginReconnect]) {
    }

    XCTAssertEqual(state.state, LMStreamStateFailed);
    XCTAssertEqual(state.retryCount, LMReconnectRetryBudget);
}

@end
