//
//  RelativeTouchHandler.h
//  Moonlight
//
//  Created by Cameron Gutman on 11/1/20.
//  Copyright © 2020 Moonlight Game Streaming Project. All rights reserved.
//

#import <UIKit/UIKit.h>

@class StreamView;

FOUNDATION_EXPORT CGPoint LMScrollDeltaForTouchMovement(CGPoint previousCenter,
                                                         CGPoint currentCenter);

NS_ASSUME_NONNULL_BEGIN

@interface RelativeTouchHandler : UIResponder

- (instancetype)initWithView:(StreamView *)view;
- (void)cancelAllTouches;

@end

NS_ASSUME_NONNULL_END
