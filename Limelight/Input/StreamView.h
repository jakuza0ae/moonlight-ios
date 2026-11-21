//
//  StreamView.h
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "ControllerSupport.h"
#import "OnScreenControls.h"
#import "Moonlight-Swift.h"
#import "StreamConfiguration.h"

@class StreamView;

@protocol UserInteractionDelegate <NSObject>

- (void) userInteractionBegan;
- (void) userInteractionEnded;

@optional
- (void)streamViewDidRequestReconnect:(StreamView *)streamView;
- (void)streamViewDidRequestDiagnostics:(StreamView *)streamView;
- (void)streamViewDidRequestDisconnect:(StreamView *)streamView;

@end

FOUNDATION_EXPORT BOOL LMShouldShowDesktopToolbarForStreamConfiguration(StreamConfiguration *streamConfig);
FOUNDATION_EXPORT BOOL LMShouldShowGamepadOverlayForStreamConfiguration(StreamConfiguration *streamConfig);
FOUNDATION_EXPORT BOOL LMShouldRestoreDesktopBrightness(CGFloat currentBrightness, CGFloat dimmedBrightness);

#if TARGET_OS_TV
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate>
#else
@interface StreamView : UIView <X1KitMouseDelegate, UITextFieldDelegate, UIPointerInteractionDelegate>
#endif

- (void) setupStreamView:(ControllerSupport*)controllerSupport
      interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                   config:(StreamConfiguration*)streamConfig;
- (void) showOnScreenControls;
- (OnScreenControlsLevel) getCurrentOscState;
- (void) cancelAllTouches;
- (void)setInputMode:(LMInputMode)inputMode;
- (BOOL)isDesktopToolbarVisible;
- (void)setDesktopToolbarVisible:(BOOL)visible animated:(BOOL)animated;
- (void)restoreDesktopBrightness;
- (void)releaseKeyboardActions;

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse;
- (CGRect) displayedVideoRect;
- (CGPoint) normalizedPointForTouch:(CGPoint)point;
#endif

@end
