//
//  AbsoluteTouchHandler.m
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import "AbsoluteTouchHandler.h"
#import "StreamView.h"
#import "RelativeTouchHandler.h"

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

@implementation AbsoluteTouchHandler {
    StreamView *view;
    LMInputMode inputMode;
    NSMutableDictionary<UITouch *, NSNumber *> *pointerIds;
    uint32_t nextPointerId;
    BOOL nativeTouchUnavailable;

    NSTimer *longPressTimer;
    UITouch *lastTouchDown;
    CGPoint lastTouchDownLocation;
    UITouch *lastTouchUp;
    CGPoint lastTouchUpLocation;
    BOOL compatibilityLeftButtonDown;
    BOOL compatibilityRightButtonDown;
    CGPoint scrollCenter;
    BOOL hasScrollCenter;
}

- (instancetype)initWithView:(StreamView *)view {
    return [self initWithView:view inputMode:LMInputModeNativeTouch];
}

- (instancetype)initWithView:(StreamView *)view inputMode:(LMInputMode)mode {
    self = [super init];
    if (self != nil) {
        self->view = view;
        self->inputMode = mode;
        self->pointerIds = [[NSMutableDictionary alloc] init];
        self->nextPointerId = 1;
    }
    return self;
}

- (void)invalidateLongPressTimer {
    [longPressTimer invalidate];
    longPressTimer = nil;
}

- (NSNumber *)pointerIdForTouch:(UITouch *)touch create:(BOOL)create {
    NSNumber *pointerId = pointerIds[touch];
    if (pointerId != nil || !create) {
        return pointerId;
    }

    if (nextPointerId == 0) {
        nextPointerId = 1;
    }
    pointerId = @(nextPointerId++);
    pointerIds[touch] = pointerId;
    return pointerId;
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

    NSNumber *pointerId = [self pointerIdForTouch:touch create:eventType == LI_TOUCH_EVENT_DOWN];
    if (pointerId == nil) {
        return YES;
    }

    if (eventType == LI_TOUCH_EVENT_CANCEL) {
        LiSendTouchEvent(eventType, pointerId.unsignedIntValue, 0.0f, 0.0f, 0.0f,
                         0.0f, 0.0f, LI_ROT_UNKNOWN);
        [pointerIds removeObjectForKey:touch];
        return YES;
    }

    CGRect displayedVideoRect = [view displayedVideoRect];
    CGPoint normalizedPoint = [view normalizedPointForTouch:[touch locationInView:view]];
    float contactAreaMajor = [self normalizedRadius:touch.majorRadius
                                              onAxis:CGRectGetWidth(displayedVideoRect)];
    float contactAreaMinor = [self normalizedRadius:touch.minorRadius
                                              onAxis:CGRectGetHeight(displayedVideoRect)];
    if (contactAreaMinor == 0.0f) {
        contactAreaMinor = contactAreaMajor;
    }

    int result = LiSendTouchEvent(eventType,
                                  pointerId.unsignedIntValue,
                                  normalizedPoint.x,
                                  normalizedPoint.y,
                                  [self pressureForTouch:touch],
                                  contactAreaMajor,
                                  contactAreaMinor,
                                  LI_ROT_UNKNOWN);
    if (result == LI_ERR_UNSUPPORTED) {
        nativeTouchUnavailable = YES;
        [pointerIds removeAllObjects];
        return NO;
    }

    if (eventType == LI_TOUCH_EVENT_UP) {
        [pointerIds removeObjectForKey:touch];
    }
    return YES;
}

- (void)onLongPressStart:(NSTimer *)timer {
    if (inputMode == LMInputModeMouseCompatibility || nativeTouchUnavailable) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        compatibilityLeftButtonDown = NO;
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
        compatibilityRightButtonDown = YES;
    }
    else if (!nativeTouchUnavailable) {
        LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, BUTTON_RIGHT);
        compatibilityRightButtonDown = YES;
    }
}

- (BOOL)usesCompatibilityFallback {
    return inputMode == LMInputModeMouseCompatibility || nativeTouchUnavailable;
}

- (CGPoint)centerForEvent:(UIEvent *)event {
    NSArray<UITouch *> *activeTouches = [[event allTouches] allObjects];
    if (activeTouches.count < 2) {
        return CGPointZero;
    }
    CGPoint first = [activeTouches[0] locationInView:view];
    CGPoint second = [activeTouches[1] locationInView:view];
    return CGPointMake((first.x + second.x) / 2.0,
                       (first.y + second.y) / 2.0);
}

- (void)sendTwoFingerScrollForEvent:(UIEvent *)event {
    if ([[event allTouches] count] < 2) {
        hasScrollCenter = NO;
        return;
    }

    CGPoint currentCenter = [self centerForEvent:event];
    if (hasScrollCenter) {
        CGPoint delta = LMScrollDeltaForTouchMovement(scrollCenter, currentCenter);
        if (delta.y != 0.0f) {
            LiSendHighResScrollEvent(delta.y * 10.0f);
        }
    }
    scrollCenter = currentCenter;
    hasScrollCenter = YES;
}

- (void)sendCompatibilityBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([[event allTouches] count] > 1) {
        return;
    }

    UITouch *touch = [touches anyObject];
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
    if ([[event allTouches] count] > 1) {
        return;
    }

    UITouch *touch = [touches anyObject];
    CGPoint touchLocation = [touch locationInView:view];
    CGPoint currentNormalized = [view normalizedPointForTouch:touchLocation];
    CGPoint initialNormalized = [view normalizedPointForTouch:lastTouchDownLocation];
    if (hypotf(currentNormalized.x - initialNormalized.x,
               currentNormalized.y - initialNormalized.y) > LONG_PRESS_ACTIVATION_DELTA) {
        [self invalidateLongPressTimer];
    }
    [view updateCursorLocation:touchLocation isMouse:NO];
}

- (void)sendCompatibilityEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([[event allTouches] count] != [touches count]) {
        return;
    }

    [self invalidateLongPressTimer];
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
    compatibilityLeftButtonDown = NO;
    compatibilityRightButtonDown = NO;
    lastTouchUp = [touches anyObject];
    lastTouchUpLocation = [lastTouchUp locationInView:view];
    lastTouchDown = nil;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self usesCompatibilityFallback]) {
        [self sendCompatibilityBegan:touches withEvent:event];
        return;
    }

    [self invalidateLongPressTimer];
    for (UITouch *touch in touches) {
        if (![self sendNativeEvent:LI_TOUCH_EVENT_DOWN forTouch:touch]) {
            [self sendCompatibilityBegan:[NSSet setWithObject:touch] withEvent:event];
        }
    }

    [self sendTwoFingerScrollForEvent:event];

    if (touches.count == 1 && !nativeTouchUnavailable) {
        UITouch *touch = [touches anyObject];
        lastTouchDown = touch;
        lastTouchDownLocation = [touch locationInView:view];
        longPressTimer = [NSTimer scheduledTimerWithTimeInterval:LONG_PRESS_ACTIVATION_DELAY
                                                           target:self
                                                         selector:@selector(onLongPressStart:)
                                                         userInfo:nil
                                                          repeats:NO];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self usesCompatibilityFallback]) {
        [self sendCompatibilityMoved:touches withEvent:event];
        return;
    }

    [self sendTwoFingerScrollForEvent:event];

    UITouch *touch = [touches anyObject];
    if (touch != nil && lastTouchDown != nil) {
        CGPoint currentNormalized = [view normalizedPointForTouch:[touch locationInView:view]];
        CGPoint initialNormalized = [view normalizedPointForTouch:lastTouchDownLocation];
        if (hypotf(currentNormalized.x - initialNormalized.x,
                   currentNormalized.y - initialNormalized.y) > LONG_PRESS_ACTIVATION_DELTA) {
            [self invalidateLongPressTimer];
        }
    }
    for (UITouch *changedTouch in touches) {
        [self sendNativeEvent:LI_TOUCH_EVENT_MOVE forTouch:changedTouch];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self usesCompatibilityFallback]) {
        [self sendCompatibilityEnded:touches withEvent:event];
        return;
    }

    for (UITouch *touch in touches) {
        [self sendNativeEvent:LI_TOUCH_EVENT_UP forTouch:touch];
    }
    [self invalidateLongPressTimer];
    hasScrollCenter = NO;
    if (compatibilityRightButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        compatibilityRightButtonDown = NO;
    }
    lastTouchDown = nil;
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self usesCompatibilityFallback]) {
        [self sendCompatibilityEnded:touches withEvent:event];
        return;
    }

    for (UITouch *touch in touches) {
        [self sendNativeEvent:LI_TOUCH_EVENT_CANCEL forTouch:touch];
    }
    [self invalidateLongPressTimer];
    hasScrollCenter = NO;
}

- (void)cancelAllTouches {
    if (pointerIds.count > 0) {
        LiSendTouchEvent(LI_TOUCH_EVENT_CANCEL_ALL, 0, 0.0f, 0.0f, 0.0f,
                         0.0f, 0.0f, LI_ROT_UNKNOWN);
        [pointerIds removeAllObjects];
    }
    [self invalidateLongPressTimer];
    hasScrollCenter = NO;
    if (compatibilityRightButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_RIGHT);
        compatibilityRightButtonDown = NO;
    }
    if (compatibilityLeftButtonDown) {
        LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, BUTTON_LEFT);
        compatibilityLeftButtonDown = NO;
    }
}

- (void)dealloc {
    [self cancelAllTouches];
}

@end
