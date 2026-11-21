#import <XCTest/XCTest.h>

#import "AbsoluteTouchHandler.h"
#import "AppDelegate.h"
#import "RelativeTouchHandler.h"
#import "StreamConfiguration.h"
#import "Connection.h"
#import "StreamFrameViewController.h"
#import "KeyboardInputField.h"
#import "KeyboardSupport.h"
#import "MainFrameViewController.h"
#import "StreamView.h"
#import "StreamManager.h"
#import "SettingsViewController.h"
#import "TemporaryApp.h"
#import "UIComputerView.h"
#include <Limelight.h>

static TemporaryHost *shortcutHost(NSString *uuid, NSArray<NSString *> *appNames) {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    host.uuid = uuid;
    host.activeAddress = @"streamdesk.test:48189";
    host.pairState = PairStatePaired;
    host.serverCert = [@"test certificate" dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableSet<TemporaryApp *> *apps = [NSMutableSet set];
    for (NSString *name in appNames) {
        TemporaryApp *app = [[TemporaryApp alloc] init];
        app.id = [NSString stringWithFormat:@"%lu", (unsigned long)(apps.count + 1)];
        app.name = name;
        app.host = host;
        [apps addObject:app];
    }
    host.appList = apps;
    return host;
}

@interface LMPreviewComputer : NSObject
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *uuid;
@end

@implementation LMPreviewComputer
@end

@interface LMTrackingStreamView : StreamView
@property (nonatomic) BOOL cancelledOnMainThread;
@property (nonatomic) BOOL keyboardReleasedOnMainThread;
@property (nonatomic) BOOL brightnessRestoredOnMainThread;
@property (nonatomic, copy) void (^cleanupCompleted)(void);
@end

@implementation LMTrackingStreamView

- (void)restoreDesktopBrightness {
    self.brightnessRestoredOnMainThread = [NSThread isMainThread];
    [super restoreDesktopBrightness];
}

- (void)cancelAllTouches {
    self.cancelledOnMainThread = [NSThread isMainThread];
    [super cancelAllTouches];
}

- (void)releaseKeyboardActions {
    self.keyboardReleasedOnMainThread = [NSThread isMainThread];
    if (self.cancelledOnMainThread && self.keyboardReleasedOnMainThread && self.cleanupCompleted != nil) {
        void (^completion)(void) = self.cleanupCompleted;
        self.cleanupCompleted = nil;
        completion();
    }
}

@end

@interface StreamView (KeyboardTestAccess)
- (void)onKeyboardPressed:(UITextField *)textField;
- (void)sendKeystroke:(struct KeyEvent)event flags:(char)flags;
@end

@interface LMKeyboardTrackingStreamView : StreamView
@property (nonatomic, strong) NSMutableArray<NSArray<NSNumber *> *> *keystrokes;
@end

@implementation LMKeyboardTrackingStreamView

- (void)sendKeystroke:(struct KeyEvent)event flags:(char)flags {
    [self.keystrokes addObject:@[@(event.keycode), @(event.modifier), @(flags)]];
}

@end

@interface TouchInputTests : XCTestCase
@end

@implementation TouchInputTests

- (void)testComputerTileKeepsArtworkInsideCardAndClearOfCaption {
    TemporaryHost *host = [[TemporaryHost alloc] init];
    host.name = @"A very long computer name that must fit its card";
    host.state = StateOffline;
    UIComputerView *add = [[UIComputerView alloc] initForAddWithCallback:nil];
    UIComputerView *offline = [[UIComputerView alloc] initWithComputer:host andCallback:nil];

    for (UIComputerView *tile in @[add, offline]) {
        UILabel *caption = nil;
        for (UIView *view in tile.subviews) {
            if ([view isKindOfClass:UILabel.class]) {
                caption = (UILabel *)view;
                break;
            }
        }
        XCTAssertNotNil(caption);
        XCTAssertTrue(CGRectContainsRect(tile.bounds, caption.frame));

        NSInteger visibleImages = 0;
        NSMutableArray<UIView *> *views = [tile.subviews mutableCopy];
        while (views.count > 0) {
            UIView *view = views.lastObject;
            [views removeLastObject];
            [views addObjectsFromArray:view.subviews];
            if (![view isKindOfClass:UIImageView.class] || ((UIImageView *)view).image == nil) {
                continue;
            }
            visibleImages++;
            CGRect artwork = [tile convertRect:view.bounds fromView:view];
            XCTAssertEqual(view.contentMode, UIViewContentModeScaleAspectFit);
            XCTAssertTrue(CGRectContainsRect(tile.bounds, artwork));
            XCTAssertLessThan(CGRectGetMaxY(artwork), CGRectGetMinY(caption.frame));
        }
        XCTAssertEqual(visibleImages, tile == add ? 1 : 2);
    }

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:add.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [add.layer renderInContext:context.CGContext];
    }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = @"Add computer tile";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

- (void)testDesktopBrightnessRestoresOnlyWhileTheDimValueIsStillApplied {
    XCTAssertTrue(LMShouldRestoreDesktopBrightness(0.30, 0.30));
    XCTAssertTrue(LMShouldRestoreDesktopBrightness(0.301, 0.30));
    XCTAssertFalse(LMShouldRestoreDesktopBrightness(0.45, 0.30));
    XCTAssertFalse(LMShouldRestoreDesktopBrightness(0.15, 0.30));
}

- (void)testSecondDisplayShortcutAcceptsOnlyTheDocumentedURL {
    XCTAssertTrue(LMIsSecondDisplayShortcutURL([NSURL URLWithString:@"streamdesk://second-display"]));
    XCTAssertFalse(LMIsSecondDisplayShortcutURL([NSURL URLWithString:@"https://second-display"]));
    XCTAssertFalse(LMIsSecondDisplayShortcutURL([NSURL URLWithString:@"streamdesk://second-display?host=example.test"]));
    XCTAssertFalse(LMIsSecondDisplayShortcutURL([NSURL URLWithString:@"streamdesk://second-display/extra"]));
    XCTAssertFalse(LMIsSecondDisplayShortcutURL([NSURL URLWithString:@"streamdesk://second-display#extra"]));
    XCTAssertFalse(LMIsSecondDisplayShortcutURL([NSURL URLWithString:@"streamdesk://other@second-display"]));
}

- (void)testSecondDisplayShortcutSelectsConfiguredHostAndPrefersStreamDeskApp {
    TemporaryHost *first = shortcutHost(@"first", @[@"Desktop", @"StreamDesk Display", @"iPad Air"]);
    TemporaryHost *second = shortcutHost(@"second", @[@"iPad Air"]);
    XCTAssertNil(LMSecondDisplayShortcutApp(@[first, second], nil));
    XCTAssertEqualObjects(LMSecondDisplayShortcutApp(@[first, second], @"first").name, @"StreamDesk Display");
    XCTAssertEqualObjects(LMSecondDisplayShortcutApp(@[first, second], @"second").name, @"iPad Air");
    XCTAssertNil(LMSecondDisplayShortcutApp(@[first, second], @"removed"));
    XCTAssertEqualObjects(LMSecondDisplayShortcutApp(@[first], nil).host, first);
}

- (void)testSecondDisplayShortcutSkipsUnpairedHiddenAndAmbiguousApps {
    TemporaryHost *unpaired = shortcutHost(@"unpaired", @[@"StreamDesk Display"]);
    unpaired.pairState = PairStateUnpaired;
    TemporaryHost *hidden = shortcutHost(@"hidden", @[@"StreamDesk Display", @"Desktop"]);
    for (TemporaryApp *app in hidden.appList) {
        if ([app.name isEqualToString:@"StreamDesk Display"]) {
            app.hidden = YES;
        }
    }
    TemporaryHost *ambiguous = shortcutHost(@"ambiguous", @[@"StreamDesk Display", @"streamdesk display"]);
    XCTAssertNil(LMSecondDisplayShortcutApp(@[unpaired, hidden, ambiguous], nil));
    XCTAssertNil(LMSecondDisplayShortcutApp(@[unpaired, hidden, ambiguous], @"ambiguous"));
    XCTAssertNil(LMSecondDisplayShortcutApp(@[unpaired, hidden], @"hidden"));
    XCTAssertNil(LMSecondDisplayShortcutApp(@[unpaired], nil));
}

- (void)testSecondDisplayShortcutPreservesAppMatchWhenCopyingConfiguration {
    StreamConfiguration *config = [[StreamConfiguration alloc] init];
    XCTAssertFalse(config.requireMatchingAppOnResume);
    config.requireMatchingAppOnResume = YES;
    StreamConfiguration *copy = [config copy];
    XCTAssertTrue(copy.requireMatchingAppOnResume);
}

- (void)testSecondDisplayFormSheetLayout {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    LMPreviewComputer *host = [[LMPreviewComputer alloc] init];
    host.name = @"Workstation";
    host.uuid = @"preview-host";
    UINavigationController *navigation = LMCreateSecondMonitorSettingsNavigationController(
        @[host], host.uuid, profile, NO, nil);
    navigation.view.frame = CGRectMake(0, 0, 540, 660);
    [navigation.view setNeedsLayout];
    [navigation.view layoutIfNeeded];
    UIViewController *settings = navigation.topViewController;
    XCTAssertEqualObjects(settings.title, @"Second display");

    UIScrollView *scroll = nil;
    for (UIView *subview in settings.view.subviews) {
        if ([subview isKindOfClass:UIScrollView.class]) {
            scroll = (UIScrollView *)subview;
            break;
        }
    }
    XCTAssertNotNil(scroll);
    [settings.view layoutIfNeeded];
    XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.size.height);
    XCTAssertEqualWithAccuracy(scroll.contentSize.width, scroll.bounds.size.width, 1);

    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithBounds:navigation.view.bounds];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [navigation.view.layer renderInContext:context.CGContext];
    }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
    attachment.name = @"Second display settings";
    attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment];
}

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

- (void)testSecondMonitorLaunchMarkerIsOnlySentForMarkedProfiles {
    StreamConfiguration *secondMonitor = [[StreamConfiguration alloc] init];
    secondMonitor.profile = [LMStreamProfile defaultSecondMonitorProfile];

    StreamConfiguration *game = [[StreamConfiguration alloc] init];

    XCTAssertTrue(LMShouldMarkSecondMonitorLaunch(secondMonitor));
    XCTAssertFalse(LMShouldMarkSecondMonitorLaunch(game));
}

- (void)testNativeLongPressDoesNotUseCompatibilityMouseSemantics {
    XCTAssertFalse(LMShouldSendCompatibilityLongPress(LMInputModeNativeTouch, YES));
    XCTAssertTrue(LMShouldSendCompatibilityLongPress(LMInputModeMouseCompatibility, YES));
    XCTAssertTrue(LMShouldSendCompatibilityLongPress(LMInputModeHybrid, NO));
}

- (void)testInitialReconnectCanStartFromConnectingState {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    LMReconnectStateMachine *state = [[LMReconnectStateMachine alloc] initWithHost:@"host-uuid"
                                                                               profile:profile];

    XCTAssertTrue(LMShouldRetryStreamFailure(YES, NO));
    XCTAssertTrue([state beginReconnect]);
    XCTAssertEqual(state.state, LMStreamStateReconnecting);
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
    XCTAssertEqual(profile.resolution.height, 960);
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

- (void)testSecondMonitorProfilePropagatesAllStreamValues {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];
    NSError *error = nil;

    XCTAssertTrue([configuration applyProfile:profile
                         forCapabilityProfile:LMDeviceCapabilityProfileIPadAir
                                         error:&error]);
    XCTAssertNil(error);
    XCTAssertEqual(configuration.width, 1280);
    XCTAssertEqual(configuration.height, 960);
    XCTAssertEqual(configuration.frameRate, 30);
    XCTAssertEqual(configuration.bitRate, 6000);
    XCTAssertEqual(configuration.supportedVideoFormats, VIDEO_FORMAT_H264);
    XCTAssertEqual(configuration.inputMode, LMInputModeNativeTouch);
    XCTAssertEqual(configuration.gamepadMask, 0);
    XCTAssertFalse(configuration.playAudioOnPC);
}

- (void)testStoredProfileDictionaryRoundTripsWithoutChangingMode {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.bitrate = 7000;
    profile.framePacing = YES;
    profile.experimental1080pEnabled = YES;
    profile.resolution = CGSizeMake(1920, 1080);

    LMStreamProfile *roundTripped = [LMStreamProfile profileWithDictionary:profile.dictionaryRepresentation];

    XCTAssertEqualObjects(roundTripped, profile);
    XCTAssertEqual(roundTripped.mode, LMStreamModeSecondMonitor);
    XCTAssertEqual(roundTripped.bitrate, 7000);
    XCTAssertTrue(roundTripped.framePacing);

    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];
    XCTAssertTrue([configuration applyProfile:roundTripped forCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:nil]);
    XCTAssertTrue(configuration.useFramePacing);
    NSMutableDictionary *previousSettings = [profile.dictionaryRepresentation mutableCopy];
    [previousSettings removeObjectForKey:@"framePacing"];
    XCTAssertFalse([LMStreamProfile profileWithDictionary:previousSettings].framePacing);
}

- (void)testProfileStoreRoundTripsByHostAndProfileName {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    profile.bitrate = 9000;

    [LMStreamProfileStore saveProfile:profile forHost:@"task-6-host" profileName:@"second-monitor"];
    LMStreamProfile *loaded = [LMStreamProfileStore loadProfileForHost:@"task-6-host" profileName:@"second-monitor"];
    LMStreamProfile *otherHost = [LMStreamProfileStore loadProfileForHost:@"other-host" profileName:@"second-monitor"];

    XCTAssertEqualObjects(loaded, profile);
    XCTAssertNil(otherHost);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[LMStreamProfileStore defaultsKeyForHost:@"task-6-host" profileName:@"second-monitor"]];
}

- (void)testMissingSecondMonitorProfilePreservesGameModeSelection {
    XCTAssertNil([LMStreamProfileStore loadProfileForHost:@"host-without-profile" profileName:@"second-monitor"]);
}

- (void)testDisabledAudioDoesNotInitializeRemoteAudioRenderer {
    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];
    XCTAssertTrue([configuration applyProfile:[LMStreamProfile defaultSecondMonitorProfile]
                         forCapabilityProfile:LMDeviceCapabilityProfileIPadAir
                                         error:nil]);

    XCTAssertFalse(LMShouldInitializeAudioRenderer(configuration));
}

- (void)testGameConfigurationStillInitializesAudioRenderer {
    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];

    XCTAssertNil(configuration.profile);
    XCTAssertTrue(LMShouldInitializeAudioRenderer(configuration));
}

- (void)testDecoderFailureUsesTheConnectionTerminationBoundary {
    VideoDecoderRenderer *renderer = [[VideoDecoderRenderer alloc] init];
    __block int receivedError = 0;
    renderer.decoderFailureHandler = ^(int errorCode) {
        receivedError = errorCode;
    };

    [renderer reportDecoderFailure:ML_ERROR_FRAME_CONVERSION];

    XCTAssertEqual(receivedError, ML_ERROR_FRAME_CONVERSION);
}

- (void)testIPadAirCapabilityRecognizesEveryFirstGenerationModelIdentifier {
    XCTAssertEqual([LMStreamProfile capabilityProfileForMachineIdentifier:@"iPad4,1"], LMDeviceCapabilityProfileIPadAir);
    XCTAssertEqual([LMStreamProfile capabilityProfileForMachineIdentifier:@"iPad4,2"], LMDeviceCapabilityProfileIPadAir);
    XCTAssertEqual([LMStreamProfile capabilityProfileForMachineIdentifier:@"iPad4,3"], LMDeviceCapabilityProfileIPadAir);
    XCTAssertEqual([LMStreamProfile capabilityProfileForMachineIdentifier:@"iPad4,4"], LMDeviceCapabilityProfileGeneric);
}

- (void)testIPadAirDisplayPresetsFitTheScreenAndUseThirtyFPS {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    XCTAssertTrue(CGSizeEqualToSize(profile.resolution, CGSizeMake(1280, 960)));
    NSArray<NSValue *> *modes = [LMStreamProfile supportedResolutionsForCapabilityProfile:LMDeviceCapabilityProfileIPadAir
                                                                              experimental1080pEnabled:NO];
    NSArray<NSValue *> *allModes = [LMStreamProfile supportedResolutionsForCapabilityProfile:LMDeviceCapabilityProfileIPadAir
                                                                                 experimental1080pEnabled:YES];

    XCTAssertEqual(modes.count, 4U);
    XCTAssertEqual(allModes.count, 5U);
    XCTAssertFalse([modes containsObject:[NSValue valueWithCGSize:CGSizeMake(1920, 1080)]]);
    XCTAssertTrue([allModes containsObject:[NSValue valueWithCGSize:CGSizeMake(1920, 1080)]]);
    for (NSValue *mode in [modes subarrayWithRange:NSMakeRange(0, 3)]) {
        profile.resolution = mode.CGSizeValue;
        XCTAssertEqual(profile.resolution.width * 3, profile.resolution.height * 4);
        profile.fps = 30;
        XCTAssertTrue([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:nil]);
        profile.fps = 60;
        XCTAssertFalse([profile validateForCapabilityProfile:LMDeviceCapabilityProfileIPadAir error:nil]);
    }
}

- (void)testReconnectUsesAStableConfigurationSnapshot {
    StreamConfiguration *configuration = [[StreamConfiguration alloc] init];
    configuration.host = @"original-host";
    configuration.profile = [LMStreamProfile defaultSecondMonitorProfile];
    StreamConfiguration *snapshot = [configuration copy];

    configuration.host = @"changed-host";
    configuration.profile.bitrate = 12000;

    XCTAssertEqualObjects(snapshot.host, @"original-host");
    XCTAssertEqual(snapshot.profile.bitrate, 6000);
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

- (void)testReconnectStageFailureConsumesAnotherRetryBeforeFinalFailure {
    LMReconnectStateMachine *state = [[LMReconnectStateMachine alloc] initWithHost:@"host-uuid"
                                                                              profile:[LMStreamProfile defaultSecondMonitorProfile]];

    XCTAssertTrue([state beginReconnect]);
    XCTAssertTrue([state beginReconnect]);
    XCTAssertEqual(state.state, LMStreamStateReconnecting);
    XCTAssertEqual(state.retryCount, 2);
    XCTAssertTrue([state beginReconnect]);
    XCTAssertFalse([state beginReconnect]);
    XCTAssertEqual(state.state, LMStreamStateFailed);
}

- (void)testKeyboardActionStateReleasesHeldModifiers {
    KeyboardInputField *field = [[KeyboardInputField alloc] initWithFrame:CGRectZero];

    [field sendKeyboardAction:LMKeyboardActionControl pressed:YES];
    [field sendKeyboardAction:LMKeyboardActionShift pressed:YES];
    XCTAssertEqual(field.activeKeyboardActions.count, 2U);

    [field sendKeyboardAction:LMKeyboardActionControl pressed:NO];
    XCTAssertEqualObjects(field.activeKeyboardActions, [NSSet setWithObject:@(LMKeyboardActionShift)]);

    [field releaseAllKeyboardActions];
    XCTAssertEqual(field.activeKeyboardActions.count, 0U);
}

- (void)testKeyboardFunctionActionsDoNotRemainHeld {
    KeyboardInputField *field = [[KeyboardInputField alloc] initWithFrame:CGRectZero];

    [field sendKeyboardAction:LMKeyboardActionEscape pressed:YES];
    XCTAssertEqual(field.activeKeyboardActions.count, 0U);
    [field sendKeyboardAction:LMKeyboardActionDelete pressed:YES];
    XCTAssertEqual(field.activeKeyboardActions.count, 0U);
}

- (void)testKeyboardDismissalReleasesHeldModifiers {
    KeyboardInputField *field = [[KeyboardInputField alloc] initWithFrame:CGRectZero];

    [field sendKeyboardAction:LMKeyboardActionAlt pressed:YES];
    [field resignFirstResponder];

    XCTAssertEqual(field.activeKeyboardActions.count, 0U);
}

- (void)testKeyboardReleaseSendsACompleteModifierCallbackPair {
    KeyboardInputField *field = [[KeyboardInputField alloc] initWithFrame:CGRectZero];
    NSMutableArray<NSArray<NSNumber *> *> *callbacks = [NSMutableArray array];
    field.keyboardActionHandler = ^(LMKeyboardAction action, BOOL pressed) {
        [callbacks addObject:@[@(action), @(pressed)]];
    };

    [field sendKeyboardAction:LMKeyboardActionShift pressed:YES];
    [field releaseAllKeyboardActions];

    XCTAssertEqual(callbacks.count, 2U);
    XCTAssertEqualObjects(callbacks[0], (@[@(LMKeyboardActionShift), @YES]));
    XCTAssertEqualObjects(callbacks[1], (@[@(LMKeyboardActionShift), @NO]));
}

- (void)testSecondMonitorTextBackspaceAndReturnEnqueueInEventOrder {
    LMKeyboardTrackingStreamView *streamView = [[LMKeyboardTrackingStreamView alloc] initWithFrame:CGRectZero];
    streamView.keystrokes = [NSMutableArray array];
    [streamView setValue:@YES forKey:@"desktopMode"];
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectZero];

    field.text = @"0llA";
    [streamView onKeyboardPressed:field];
    XCTAssertEqualObjects(field.text, @"0");

    field.text = @"";
    [streamView onKeyboardPressed:field];
    XCTAssertFalse([streamView textFieldShouldReturn:field]);

    XCTAssertEqualObjects(streamView.keystrokes, (@[
        @[@('L'), @0, @(SS_KBE_FLAG_NON_NORMALIZED)],
        @[@('L'), @0, @(SS_KBE_FLAG_NON_NORMALIZED)],
        @[@('A'), @(MODIFIER_SHIFT), @(SS_KBE_FLAG_NON_NORMALIZED)],
        @[@0x08, @0, @0],
        @[@0x0D, @0, @0],
    ]));
}

- (void)testSecondMonitorToolbarAndOverlayPredicatesDoNotApplyToGameMode {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];
    StreamConfiguration *desktopConfiguration = [[StreamConfiguration alloc] init];
    desktopConfiguration.profile = profile;

    StreamConfiguration *gameConfiguration = [[StreamConfiguration alloc] init];

    XCTAssertTrue(LMShouldShowDesktopToolbarForStreamConfiguration(desktopConfiguration));
    XCTAssertFalse(LMShouldShowDesktopToolbarForStreamConfiguration(gameConfiguration));
    XCTAssertFalse(LMShouldShowGamepadOverlayForStreamConfiguration(desktopConfiguration));
    XCTAssertTrue(LMShouldShowGamepadOverlayForStreamConfiguration(gameConfiguration));
}

- (void)testStoredSecondMonitorProfileRequiresExplicitActivation {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];

    XCTAssertFalse(LMShouldUseSecondMonitorProfile(NO, profile));
    XCTAssertTrue(LMShouldUseSecondMonitorProfile(YES, profile));
}

- (void)testSecondMonitorActivationRequiresAnExplicitHostAndProfile {
    LMStreamProfile *profile = [LMStreamProfile defaultSecondMonitorProfile];

    XCTAssertFalse(LMSecondMonitorProfileSelectionIsValid(YES, nil, profile));
    XCTAssertFalse(LMSecondMonitorProfileSelectionIsValid(YES, @"", profile));
    XCTAssertTrue(LMSecondMonitorProfileSelectionIsValid(YES, @"selected-host", profile));
}

- (void)testSecondMonitor1080p30RequiresTheExplicitOptIn {
    XCTAssertFalse(LMSecondMonitorProfileSupportsExplicit1080p30(NO, CGSizeMake(1920, 1080), 30));
    XCTAssertFalse(LMSecondMonitorProfileSupportsExplicit1080p30(YES, CGSizeMake(1920, 1080), 60));
    XCTAssertTrue(LMSecondMonitorProfileSupportsExplicit1080p30(YES, CGSizeMake(1920, 1080), 30));
}

- (void)testSecondMonitorDiagnosticsFormatterIncludesBoundedRecordWithoutSecrets {
    LMStreamDiagnostics *diagnostics = [[LMStreamDiagnostics alloc] init];
    diagnostics.state = @"streaming";
    diagnostics.hostDisplayID = nil;
    diagnostics.mappedOutput = nil;
    diagnostics.captureBackend = nil;
    diagnostics.encoder = nil;
    diagnostics.codec = @"H.264";
    diagnostics.resolution = @"1280x720";
    diagnostics.fps = @30;
    diagnostics.bitrateKbps = @5000;
    diagnostics.rttMs = @22;
    diagnostics.droppedFrames = @3;
    diagnostics.reconnectCount = @1;
    diagnostics.lastError = @"whoami --password=not-a-diagnostic-value";

    NSString *formatted = LMFormatSecondMonitorDiagnostics(diagnostics);

    XCTAssertTrue([formatted containsString:@"State: streaming"]);
    XCTAssertTrue([formatted containsString:@"Host display: unavailable"]);
    XCTAssertTrue([formatted containsString:@"Mapped output: unavailable"]);
    XCTAssertTrue([formatted containsString:@"Resolution: 1280x720"]);
    XCTAssertTrue([formatted containsString:@"Bitrate: 5000 kbps"]);
    XCTAssertTrue([formatted containsString:@"RTT: 22 ms"]);
    XCTAssertTrue([formatted containsString:@"Dropped frames: 3"]);
    XCTAssertTrue([formatted containsString:@"Reconnects: 1"]);
    XCTAssertTrue([formatted containsString:@"Last error: redacted"]);
    XCTAssertFalse([formatted containsString:@"not-a-diagnostic-value"]);
    XCTAssertFalse([formatted containsString:@"whoami"]);
    XCTAssertLessThanOrEqual(formatted.length, LMSecondMonitorDiagnosticOverlayMaximumLength);
}

- (void)testSecondMonitorDiagnosticsBoundsEveryStringAndTheWholeOverlay {
    NSString *adversarialValue = [@"whoami\r\n" stringByPaddingToLength:4096 withString:@"&password=secret" startingAtIndex:0];
    LMStreamDiagnostics *diagnostics = [[LMStreamDiagnostics alloc] init];
    diagnostics.state = adversarialValue;
    diagnostics.hostDisplayID = adversarialValue;
    diagnostics.mappedOutput = adversarialValue;
    diagnostics.captureBackend = adversarialValue;
    diagnostics.encoder = adversarialValue;
    diagnostics.codec = adversarialValue;
    diagnostics.resolution = adversarialValue;
    diagnostics.fps = @30;
    diagnostics.bitrateKbps = @5000;
    diagnostics.rttMs = @22;
    diagnostics.droppedFrames = @3;
    diagnostics.reconnectCount = @1;
    diagnostics.lastError = adversarialValue;

    NSString *formatted = LMFormatSecondMonitorDiagnostics(diagnostics);

    XCTAssertLessThanOrEqual(formatted.length, LMSecondMonitorDiagnosticOverlayMaximumLength);
    XCTAssertFalse([formatted containsString:@"whoami"]);
    XCTAssertFalse([formatted containsString:@"password=secret"]);
    XCTAssertFalse([formatted containsString:@"\r"]);
    XCTAssertTrue([formatted containsString:@"State: redacted"]);
    XCTAssertTrue([formatted containsString:@"Host display: redacted"]);
}

- (void)testLegacyGameModeOverlayFormatRemainsDistinctFromSecondMonitorDiagnostics {
    NSString *legacy = LMFormatLegacyStatsOverlay(1280, 720, 30.0, @"H.264", 1.5, @"22 ms", @"");

    XCTAssertTrue([legacy containsString:@"Video stream: 1280x720 30.00 FPS"]);
    XCTAssertTrue([legacy containsString:@"Frames dropped by your network connection: 1.50%"]);
    XCTAssertFalse([legacy containsString:@"Host display:"]);
}

- (void)testSecondMonitorSettingsFactoryReturnsVisibleNavigationContainer {
    UINavigationController *navigationController = LMCreateSecondMonitorSettingsNavigationController(@[],
                                                                                                       nil,
                                                                                                       [LMStreamProfile defaultSecondMonitorProfile],
                                                                                                       NO,
                                                                                                       nil);
    XCTAssertTrue([navigationController isKindOfClass:[UINavigationController class]]);
    [navigationController.topViewController loadViewIfNeeded];
    XCTAssertNotNil(navigationController.topViewController.navigationItem.leftBarButtonItem);
    XCTAssertNotNil(navigationController.topViewController.navigationItem.rightBarButtonItem);
}

- (void)testSelectedHostProfileFlowsThroughSettingsSaveCallback {
    __block NSString *savedHostUUID;
    __block LMStreamProfile *savedProfile;
    __block BOOL savedActive;
    LMPreviewComputer *host = [[LMPreviewComputer alloc] init];
    host.uuid = @"selected-host";
    host.name = @"Test PC";
    UINavigationController *navigationController = LMCreateSecondMonitorSettingsNavigationController(@[host],
                                                                                                       @"selected-host",
                                                                                                       [LMStreamProfile defaultSecondMonitorProfile],
                                                                                                       YES,
                                                                                                       ^(NSString *hostUUID, LMStreamProfile *profile, BOOL active, BOOL diagnostics) {
        savedHostUUID = hostUUID;
        savedProfile = profile;
        savedActive = active;
    });
    [navigationController.topViewController loadViewIfNeeded];
    [navigationController.topViewController performSelector:@selector(saveSettings:) withObject:nil];

    XCTAssertEqualObjects(savedHostUUID, @"selected-host");
    XCTAssertEqual(savedProfile.mode, LMStreamModeSecondMonitor);
    XCTAssertTrue(savedActive);
}

- (void)testStreamInputCleanupMarshalsToTheMainThread {
    StreamFrameViewController *viewController = [[StreamFrameViewController alloc] init];
    LMTrackingStreamView *streamView = [[LMTrackingStreamView alloc] initWithFrame:CGRectZero];
    XCTestExpectation *cleanupExpectation = [self expectationWithDescription:@"stream input cleanup"];
    streamView.cleanupCompleted = ^{
        [cleanupExpectation fulfill];
    };
    [viewController setValue:streamView forKey:@"streamView"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        [viewController performSelector:@selector(cleanupStreamInputOnMainThread)];
    });

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    XCTAssertTrue(streamView.brightnessRestoredOnMainThread);
    XCTAssertTrue(streamView.cancelledOnMainThread);
    XCTAssertTrue(streamView.keyboardReleasedOnMainThread);
}

- (void)testStatsTimerResetInvalidatesAndClearsExistingTimer {
    StreamFrameViewController *viewController = [[StreamFrameViewController alloc] init];
    NSTimer *timer = [NSTimer timerWithTimeInterval:1.0
                                              target:viewController
                                            selector:@selector(updateStatsOverlay)
                                            userInfo:nil
                                             repeats:YES];
    [viewController setValue:timer forKey:@"statsUpdateTimer"];

    [viewController performSelector:@selector(invalidateStatsUpdateTimer)];

    XCTAssertNil([viewController valueForKey:@"statsUpdateTimer"]);
    XCTAssertFalse(timer.isValid);
}

@end
