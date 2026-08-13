//
//  AbsoluteTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "../Database/TemporarySettings.h"

@class StreamView;

FOUNDATION_EXPORT CGPoint LMNormalizedPointForTouch(CGPoint point,
                                                     CGRect videoBounds,
                                                     CGRect displayedVideoRect);

NS_ASSUME_NONNULL_BEGIN

@interface AbsoluteTouchHandler : UIResponder

- (instancetype)initWithView:(StreamView *)view;
- (instancetype)initWithView:(StreamView *)view inputMode:(LMInputMode)inputMode;
- (void)cancelAllTouches;

@end

NS_ASSUME_NONNULL_END
