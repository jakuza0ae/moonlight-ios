//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "AbsoluteTouchHandler.h"
#import "RelativeTouchHandler.h"
#import "StreamView.h"

#include <Limelight.h>
#include <math.h>

// How long the fingers must be stationary to start a right click
#define LONG_PRESS_ACTIVATION_DELAY 0.650f

// How far the finger can move before it cancels a right click
#define LONG_PRESS_ACTIVATION_DELTA 0.01f

// How long the double tap deadzone stays in effect between touch up and touch down
#define DOUBLE_TAP_DEAD_ZONE_DELAY 0.250f

// How far the finger can move before it can override the double tap deadzone
#define DOUBLE_TAP_DEAD_ZONE_DELTA 0.025f

CGPoint LMNormalizedPointForTouch(CGPoint point, CGRect videoBounds, CGRect displayedVideoRect) {
    if (CGRectIsEmpty(videoBounds) || CGRectIsEmpty(displayedVideoRect)) {
        return CGPointZero;
    }

    CGFloat boundedX = MIN(MAX(point.x, CGRectGetMinX(videoBounds)), CGRectGetMaxX(videoBounds));
    CGFloat boundedY = MIN(MAX(point.y, CGRectGetMinY(videoBounds)), CGRectGetMaxY(videoBounds));
    CGFloat normalizedX = (boundedX - CGRectGetMinX(displayedVideoRect)) / CGRectGetWidth(displayedVideoRect);
    CGFloat normalizedY = (boundedY - CGRectGetMinY(displayedVideoRect)) / CGRectGetHeight(displayedVideoRect);

    return CGPointMake(MIN(MAX(normalizedX, 0.0), 1.0),
                       MIN(MAX(normalizedY, 0.0), 1.0));
}

LMInputRoute LMInputRouteForMode(LMInputMode inputMode,
                                 NSUInteger activeTouchCount,
                                 BOOL nativeTouchAvailable) {
    if (!nativeTouchAvailable || activeTouchCount == 0 || inputMode == LMInputModeMouseCompatibility) {
        return LMInputRouteMouseCompatibility;
    }
    if (inputMode == LMInputModeHybrid && activeTouchCount != 1) {
        return LMInputRouteMouseCompatibility;
    }
    return LMInputRouteNativeTouch;
}

BOOL LMShouldStartLongPressForTouchCount(NSUInteger activeTouchCount) {
    return activeTouchCount == 1;
}

BOOL LMShouldCancelLongPressForTouchCount(NSUInteger activeTouchCount) {
    return activeTouchCount != 1;
}

BOOL LMShouldSendTwoFingerScrollForTouchCount(NSUInteger activeTouchCount) {
    return activeTouchCount == 2;
}

LMCompatibilityGestureState LMCompatibilityGestureStateBegin(NSUInteger activeTouchCount,
                                                              CGPoint center) {
    LMCompatibilityGestureState state = {0};
    state.peakTouchCount = activeTouchCount;
    state.scrollCenter = center;
    state.hasScrollCenter = LMShouldSendTwoFingerScrollForTouchCount(activeTouchCount);
    return state;
}

CGPoint LMCompatibilityGestureStateMove(LMCompatibilityGestureState *state,
                                         NSUInteger activeTouchCount,
                                         CGPoint currentCenter) {
    if (!LMShouldSendTwoFingerScrollForTouchCount(activeTouchCount)) {
        state->hasScrollCenter = NO;
        return CGPointZero;
    }

    CGPoint delta = CGPointZero;
    if (state->hasScrollCenter) {
        delta = LMScrollDeltaForTouchMovement(state->scrollCenter, currentCenter);
        if (delta.x != 0.0f || delta.y != 0.0f) {
            state->moved = YES;
        }
    }
    state->scrollCenter = currentCenter;
    state->hasScrollCenter = YES;
    return delta;
}

BOOL LMCompatibilityGestureStateShouldTap(const LMCompatibilityGestureState *state) {
    return state->peakTouchCount == 2 && !state->moved;
}

void LMCompatibilityGestureStateReset(LMCompatibilityGestureState *state) {
    *state = (LMCompatibilityGestureState){0};
}

@implementation LMActiveTouchPointerMap {
    NSMapTable *pointerIds;
    uint32_t nextPointerId;
}

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        pointerIds = [[NSMapTable alloc] initWithKeyOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality
                                               valueOptions:NSPointerFunctionsStrongMemory
                                                   capacity:0];
        nextPointerId = 1;
    }
    return self;
}

- (uint32_t)pointerIdForTouch:(id)touch create:(BOOL)create {
    NSNumber *pointerId = [pointerIds objectForKey:touch];
    if (pointerId != nil || !create) {
        return pointerId.unsignedIntValue;
    }

    if (nextPointerId == 0) {
        nextPointerId = 1;
    }
    pointerId = @(nextPointerId++);
    [pointerIds setObject:pointerId forKey:touch];
    return pointerId.unsignedIntValue;
}

- (void)releaseTouch:(id)touch {
    [pointerIds removeObjectForKey:touch];
}

- (NSArray<NSNumber *> *)activePointerIds {
    NSMutableArray<NSNumber *> *activeIds = [[NSMutableArray alloc] init];
    for (NSNumber *pointerId in pointerIds.objectEnumerator) {
        [activeIds addObject:pointerId];
    }
    return activeIds;
}

- (void)cancelAllTouches {
    [pointerIds removeAllObjects];
}

@end

@implementation AbsoluteTouchHandler {
    StreamView *view;
    LMInputMode inputMode;
    LMActiveTouchPointerMap *pointerMap;
    BOOL nativeTouchUnavailable;

    NSTimer *longPressTimer;
    UITouch *lastTouchDown;
    CGPoint lastTouchDownLocation;
    UITouch *lastTouchUp;
    CGPoint lastTouchUpLocation;
    BOOL compatibilityLeftButtonDown;
    BOOL compatibilityRightButtonDown;
    LMCompatibilityGestureState compatibilityGestureState;
    BOOL hybridMouseGesture;
}

- (instancetype)initWithView:(StreamView *)view {
    return [self initWithView:view inputMode:LMInputModeNativeTouch];
}

- (instancetype)initWithView:(StreamView *)view inputMode:(LMInputMode)mode {
    self = [super init];
    if (self != nil) {
        self->view = view;
        self->inputMode = mode;
        self->pointerMap = [[LMActiveTouchPointerMap alloc] init];
    }
    return self;
}

- (void)setInputMode:(LMInputMode)mode {
    if (inputMode == mode) {
        return;
    }

    [self cancelAllTouches];
    inputMode = mode;
}

- (void)invalidateLongPressTimer {
    [longPressTimer invalidate];
    longPressTimer = nil;
}

- (NSUInteger)activeTouchCountForEvent:(UIEvent *)event {
    return event.allTouches.count;
}

- (void)cancelNativePointers {
    if (pointerMap.activePointerIds.count > 0) {
        LiSendTouchEvent(LI_TOUCH_EVENT_CANCEL_ALL, 0, 0.0f, 0.0f, 0.0f,
                         0.0f, 0.0f, LI_ROT_UNKNOWN);
        [pointerMap cancelAllTouches];
    }
}

- (float)pressureForTouch:(UITouch *)touch {
    if (touch.maximumPossibleForce <= 0.0) {
        return 0.0f;
    }
    return MIN(1.0f, MAX(0.0f, (float)(touch.force / touch.maximumPossibleForce)));
}

- (float)normalizedRadius:(CGFloat)radius onAxis:(CGFloat)axis {
    if (radius <= 0.0 || axis <= 0.0) {
        return 0.0f;
    }
    return MIN(1.0f, (float)((radius * 2.0) / axis));
}

- (BOOL)sendNativeEvent:(uint8_t)eventType forTouch:(UITouch *)touch {
    if (nativeTouchUnavailable) {
        return NO;
    }

    uint32_t pointerId = [pointerMap pointerIdForTouch:touch
                                                create:eventType == LI_TOUCH_EVENT_DOWN];
    if (pointerId == 0) {
        return YES;
    }

    if (eventType == LI_TOUCH_EVENT_CANCEL) {
        LiSendTouchEvent(eventType, pointerId, 0.0f, 0.0f, 0.0f,
                         0.0f, 0.0f, LI_ROT_UNKNOWN);
        [pointerMap releaseTouch:touch];
        return YES;
    }

    CGRect displayedVideoRect = [view displayedVideoRect];
    CGPoint normalizedPoint = [view normalizedPointForTouch:[touch locationInView:view]];
    float contactArea = [self normalizedRadius:touch.majorRadius
                                         onAxis:CGRectGetWidth(displayedVideoRect)];

    int result = LiSendTouchEvent(eventType,
                                  pointerId,
                                  normalizedPoint.x,
                                  normalizedPoint.y,
                                  [self pressureForTouch:touch],
                                  contactArea,
                                  contactArea,
                                  LI_ROT_UNKNOWN);
    if (result == LI_ERR_UNSUPPORTED) {
        // The host may have accepted earlier contacts, so cancel before dropping IDs.
        [self cancelNativePointers];
        nativeTouchUnavailable = YES;
        return NO;
    }

    if (eventType == LI_TOUCH_EVENT_UP) {
        [pointerMap releaseTouch:touch];
    }
    return YES;
}

- (void)releaseCompatibilityButtons {
    [self invalidateLongPressTimer];
    if (compatibilityLeftButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        compatibilityLeftButtonDown = NO;
    }
    if (compatibilityRightButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        compatibilityRightButtonDown = NO;
    }
}

- (void)onLongPressStart:(NSTimer *)timer {
    if (lastTouchDown == nil || !LMShouldStartLongPressForTouchCount(pointerMap.activePointerIds.count + (compatibilityLeftButtonDown ? 1 : 0))) {
        return;
    }

    [self invalidateLongPressTimer];
    [view updateCursorLocation:[lastTouchDown locationInView:view] isMouse:NO];
    if (inputMode == LMInputModeMouseCompatibility || nativeTouchUnavailable) {
        [self releaseCompatibilityButtons];
    }
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
    compatibilityRightButtonDown = YES;
}

- (CGPoint)centerForEvent:(UIEvent *)event {
    NSArray<UITouch *> *activeTouches = event.allTouches.allObjects;
    if (activeTouches.count < 2) {
        return CGPointZero;
    }
    CGPoint first = [activeTouches[0] locationInView:view];
    CGPoint second = [activeTouches[1] locationInView:view];
    return CGPointMake((first.x + second.x) / 2.0,
                       (first.y + second.y) / 2.0);
}

- (void)beginCompatibilityGestureForEvent:(UIEvent *)event {
    NSUInteger activeTouchCount = [self activeTouchCountForEvent:event];
    compatibilityGestureState = LMCompatibilityGestureStateBegin(activeTouchCount,
                                                                   [self centerForEvent:event]);
}

- (void)moveCompatibilityGestureForEvent:(UIEvent *)event {
    NSUInteger activeTouchCount = [self activeTouchCountForEvent:event];
    CGPoint currentCenter = [self centerForEvent:event];
    CGPoint delta = LMCompatibilityGestureStateMove(&compatibilityGestureState,
                                                    activeTouchCount,
                                                    currentCenter);
    if (delta.y != 0.0f) {
        LiSendHighResScrollEvent(delta.y * 10.0f);
    }
}

- (void)endCompatibilityGesture {
    if (LMCompatibilityGestureStateShouldTap(&compatibilityGestureState)) {
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    }
    LMCompatibilityGestureStateReset(&compatibilityGestureState);
}

- (void)sendCompatibilityBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self activeTouchCountForEvent:event] != 1) {
        [self beginCompatibilityGestureForEvent:event];
        return;
    }

    UITouch *touch = touches.anyObject;
    CGPoint touchLocation = [touch locationInView:view];
    CGPoint currentNormalized = [view normalizedPointForTouch:touchLocation];
    CGPoint lastNormalized = [view normalizedPointForTouch:lastTouchUpLocation];

    if (touch.timestamp - lastTouchUp.timestamp > DOUBLE_TAP_DEAD_ZONE_DELAY ||
        hypotf(currentNormalized.x - lastNormalized.x,
              currentNormalized.y - lastNormalized.y) > DOUBLE_TAP_DEAD_ZONE_DELTA) {
        [view updateCursorLocation:touchLocation isMouse:NO];
    }

    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_LEFT);
    compatibilityLeftButtonDown = YES;
    longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                       target:self
                                                     selector:@selector(onLongPressStart:)
                                                     userInfo:nil
                                                      repeats:NO];
    lastTouchDown = touch;
    lastTouchDownLocation = touchLocation;
}

- (void)sendCompatibilityMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    NSUInteger activeTouchCount = [self activeTouchCountForEvent:event];
    if (LMShouldCancelLongPressForTouchCount(activeTouchCount)) {
        [self invalidateLongPressTimer];
    }
    if (activeTouchCount == 1) {
        UITouch *touch = touches.anyObject;
        CGPoint touchLocation = [touch locationInView:view];
        CGPoint currentNormalized = [view normalizedPointForTouch:touchLocation];
        CGPoint initialNormalized = [view normalizedPointForTouch:lastTouchDownLocation];
        if (hypotf(currentNormalized.x - initialNormalized.x,
                   currentNormalized.y - initialNormalized.y) > LONG_PRESS_ACTIVATION_DELTA) {
            [self invalidateLongPressTimer];
        }
        [view updateCursorLocation:touchLocation isMouse:NO];
    }
    else {
        [self moveCompatibilityGestureForEvent:event];
    }
}

- (void)sendCompatibilityEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (event.allTouches.count == touches.count) {
        [self endCompatibilityGesture];
        [self releaseCompatibilityButtons];
        lastTouchUp = touches.anyObject;
        lastTouchUpLocation = [lastTouchUp locationInView:view];
        lastTouchDown = nil;
    }
}

- (void)beginMouseRouteForTouches:(NSSet *)touches withEvent:(UIEvent *)event {
    [self sendCompatibilityBegan:touches withEvent:event];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    NSUInteger activeTouchCount = [self activeTouchCountForEvent:event];
    if (LMShouldCancelLongPressForTouchCount(activeTouchCount)) {
        [self invalidateLongPressTimer];
    }

    if (inputMode == LMInputModeHybrid && activeTouchCount >= 2) {
        [self cancelNativePointers];
        [self releaseCompatibilityButtons];
        hybridMouseGesture = YES;
    }

    LMInputRoute route = hybridMouseGesture
        ? LMInputRouteMouseCompatibility
        : LMInputRouteForMode(inputMode, activeTouchCount, !nativeTouchUnavailable);
    if (route == LMInputRouteMouseCompatibility) {
        [self beginMouseRouteForTouches:touches withEvent:event];
        return;
    }

    for (UITouch *touch in touches) {
        if (![self sendNativeEvent:LI_TOUCH_EVENT_DOWN forTouch:touch]) {
            [self beginMouseRouteForTouches:touches withEvent:event];
            return;
        }
    }

    if (LMShouldStartLongPressForTouchCount(activeTouchCount)) {
        lastTouchDown = touches.anyObject;
        lastTouchDownLocation = [lastTouchDown locationInView:view];
        longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                           target:self
                                                         selector:@selector(onLongPressStart:)
                                                         userInfo:nil
                                                          repeats:NO];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    NSUInteger activeTouchCount = [self activeTouchCountForEvent:event];
    if (LMShouldCancelLongPressForTouchCount(activeTouchCount)) {
        [self invalidateLongPressTimer];
    }

    LMInputRoute route = hybridMouseGesture
        ? LMInputRouteMouseCompatibility
        : LMInputRouteForMode(inputMode, activeTouchCount, !nativeTouchUnavailable);
    if (route == LMInputRouteMouseCompatibility) {
        [self sendCompatibilityMoved:touches withEvent:event];
        return;
    }

    for (UITouch *touch in touches) {
        if (![self sendNativeEvent:LI_TOUCH_EVENT_MOVE forTouch:touch]) {
            [self beginMouseRouteForTouches:touches withEvent:event];
            return;
        }
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    NSUInteger activeTouchCount = [self activeTouchCountForEvent:event];
    LMInputRoute route = hybridMouseGesture
        ? LMInputRouteMouseCompatibility
        : LMInputRouteForMode(inputMode, activeTouchCount, !nativeTouchUnavailable);
    if (route == LMInputRouteMouseCompatibility) {
        [self sendCompatibilityEnded:touches withEvent:event];
    }
    else {
        for (UITouch *touch in touches) {
            [self sendNativeEvent:LI_TOUCH_EVENT_UP forTouch:touch];
        }
        [self invalidateLongPressTimer];
        [self releaseCompatibilityButtons];
        if (activeTouchCount == 1) {
            lastTouchDown = nil;
        }
    }

    if (event.allTouches.count == touches.count) {
        hybridMouseGesture = NO;
        [self invalidateLongPressTimer];
        lastTouchDown = nil;
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        [self sendNativeEvent:LI_TOUCH_EVENT_CANCEL forTouch:touch];
    }
    [self cancelNativePointers];
    [self releaseCompatibilityButtons];
    hybridMouseGesture = NO;
    LMCompatibilityGestureStateReset(&compatibilityGestureState);
    lastTouchDown = nil;
}

- (void)cancelAllTouches {
    [self cancelNativePointers];
    [self releaseCompatibilityButtons];
    hybridMouseGesture = NO;
    LMCompatibilityGestureStateReset(&compatibilityGestureState);
    lastTouchDown = nil;
}

- (void)dealloc {
    [self cancelAllTouches];
}

@end
