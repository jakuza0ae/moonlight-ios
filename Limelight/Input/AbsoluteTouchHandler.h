//
//  AbsoluteTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "InputMode.h"

@class StreamView;

FOUNDATION_EXPORT CGPoint LMNormalizedPointForTouch(CGPoint point,
                                                     CGRect videoBounds,
                                                     CGRect displayedVideoRect);
FOUNDATION_EXPORT LMInputRoute LMInputRouteForMode(LMInputMode inputMode,
                                                    NSUInteger activeTouchCount,
                                                    BOOL nativeTouchAvailable);
FOUNDATION_EXPORT BOOL LMShouldStartLongPressForTouchCount(NSUInteger activeTouchCount);
FOUNDATION_EXPORT BOOL LMShouldCancelLongPressForTouchCount(NSUInteger activeTouchCount);
FOUNDATION_EXPORT BOOL LMShouldSendTwoFingerScrollForTouchCount(NSUInteger activeTouchCount);

typedef struct {
    NSUInteger peakTouchCount;
    CGPoint scrollCenter;
    BOOL hasScrollCenter;
    BOOL moved;
} LMCompatibilityGestureState;

FOUNDATION_EXPORT LMCompatibilityGestureState LMCompatibilityGestureStateBegin(NSUInteger activeTouchCount,
                                                                                 CGPoint center);
FOUNDATION_EXPORT CGPoint LMCompatibilityGestureStateMove(LMCompatibilityGestureState *state,
                                                           NSUInteger activeTouchCount,
                                                           CGPoint currentCenter);
FOUNDATION_EXPORT BOOL LMCompatibilityGestureStateShouldTap(const LMCompatibilityGestureState *state);
FOUNDATION_EXPORT void LMCompatibilityGestureStateReset(LMCompatibilityGestureState *state);

@interface LMActiveTouchPointerMap : NSObject
- (uint32_t)pointerIdForTouch:(id)touch create:(BOOL)create;
- (void)releaseTouch:(id)touch;
- (NSArray<NSNumber *> *)activePointerIds;
- (void)cancelAllTouches;
@end

NS_ASSUME_NONNULL_BEGIN

@interface AbsoluteTouchHandler : UIResponder

- (instancetype)initWithView:(StreamView *)view;
- (instancetype)initWithView:(StreamView *)view inputMode:(LMInputMode)inputMode;
- (void)cancelAllTouches;

@end

NS_ASSUME_NONNULL_END
