//
//  StreamView.m
//  Moonlight
//
//  Created by Cameron Gutman on 10/19/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "StreamView.h"
#include <Limelight.h>
#import "DataManager.h"
#import "ControllerSupport.h"
#import "KeyboardSupport.h"
#import "RelativeTouchHandler.h"
#import "AbsoluteTouchHandler.h"
#import "KeyboardInputField.h"

static const double X1_MOUSE_SPEED_DIVISOR = 2.5;
static const void *LMKeyboardActionAssociationKey = &LMKeyboardActionAssociationKey;

BOOL LMShouldShowDesktopToolbarForStreamConfiguration(StreamConfiguration *streamConfig) {
    return streamConfig.profile != nil && streamConfig.profile.mode == LMStreamModeSecondMonitor;
}

BOOL LMShouldShowGamepadOverlayForStreamConfiguration(StreamConfiguration *streamConfig) {
    return !LMShouldShowDesktopToolbarForStreamConfiguration(streamConfig);
}

@protocol StreamDeskTouchCancellation <NSObject>
- (void)cancelAllTouches;
@end

@implementation StreamView {
    OnScreenControls* onScreenControls;
    
    KeyboardInputField* keyInputField;
    BOOL isInputingText;
    NSMutableSet* keysDown;
    
    float streamAspectRatio;
    
    // iOS 13.4 mouse support
    NSInteger lastMouseButtonMask;
    float lastMouseX;
    float lastMouseY;
    CGPoint lastScrollTranslation;
    
    // Citrix X1 mouse support
    X1Mouse* x1mouse;
    double accumulatedMouseDeltaX;
    double accumulatedMouseDeltaY;
    
    UIResponder* touchHandler;
    
    id<UserInteractionDelegate> interactionDelegate;
    NSTimer* interactionTimer;
    BOOL hasUserInteracted;
    
    NSDictionary<NSString *, NSNumber *> *dictCodes;

    StreamConfiguration *streamConfig;
    UIView *desktopToolbar;
    UISegmentedControl *desktopInputModeSelector;
    BOOL desktopToolbarVisible;
    BOOL desktopMode;
    BOOL keyboardTargetInstalled;
}

- (void) setupStreamView:(ControllerSupport*)controllerSupport
     interactionDelegate:(id<UserInteractionDelegate>)interactionDelegate
                   config:(StreamConfiguration*)streamConfig {
    self->interactionDelegate = interactionDelegate;
    self->streamConfig = streamConfig;
    self->desktopMode = LMShouldShowDesktopToolbarForStreamConfiguration(streamConfig);
    self->streamAspectRatio = (float)streamConfig.width / (float)streamConfig.height;
    
    TemporarySettings* settings = [[[DataManager alloc] init] getSettings];
    
    keysDown = [[NSMutableSet alloc] init];
    keyInputField = [[KeyboardInputField alloc] initWithFrame:CGRectZero];
    [keyInputField setKeyboardType:UIKeyboardTypeDefault];
    [keyInputField setAutocorrectionType:UITextAutocorrectionTypeNo];
    [keyInputField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [keyInputField setSpellCheckingType:UITextSpellCheckingTypeNo];
    [self addSubview:keyInputField];

    if (desktopMode) {
        [self installDesktopToolbar];
    }
    
#if TARGET_OS_TV
    // tvOS requires RelativeTouchHandler to manage Apple Remote input
    self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
#else
    // Keep the legacy game gestures behind the compatibility mode. Desktop profiles
    // use native touch or hybrid mode explicitly through StreamConfiguration.
    if (desktopMode) {
        self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self inputMode:streamConfig.inputMode];
    }
    else if (streamConfig.inputMode == LMInputModeMouseCompatibility) {
        if (settings.absoluteTouchMode) {
            self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self inputMode:LMInputModeMouseCompatibility];
        }
        else {
            self->touchHandler = [[RelativeTouchHandler alloc] initWithView:self];
        }
    }
    else {
        self->touchHandler = [[AbsoluteTouchHandler alloc] initWithView:self inputMode:streamConfig.inputMode];
    }
    
    onScreenControls = [[OnScreenControls alloc] initWithView:self controllerSup:controllerSupport streamConfig:streamConfig];
    OnScreenControlsLevel level = (OnScreenControlsLevel)[settings.onscreenControls integerValue];
    if (desktopMode || streamConfig.inputMode != LMInputModeMouseCompatibility) {
        Log(LOG_I, @"On-screen controls disabled in native touch mode");
        [onScreenControls setLevel:OnScreenControlsLevelOff];
    }
    else if (level == OnScreenControlsLevelAuto) {
        [controllerSupport initAutoOnScreenControlMode:onScreenControls];
    }
    else {
        Log(LOG_I, @"Setting manual on-screen controls level: %d", (int)level);
        [onScreenControls setLevel:level];
    }
    
    // It would be nice to just use GCMouse on iOS 14+ and the older API on iOS 13
    // but unfortunately that isn't possible today. GCMouse doesn't recognize many
    // mice correctly, but UIKit does. We will register for both and ignore UIKit
    // events if a GCMouse is connected.
    if (@available(iOS 13.4, *)) {
        [self addInteraction:[[UIPointerInteraction alloc] initWithDelegate:self]];
        
        UIPanGestureRecognizer *discreteMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedDiscrete:)];
        discreteMouseWheelRecognizer.maximumNumberOfTouches = 0;
        discreteMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskDiscrete;
        discreteMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:discreteMouseWheelRecognizer];
        
        UIPanGestureRecognizer *continuousMouseWheelRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mouseWheelMovedContinuous:)];
        continuousMouseWheelRecognizer.maximumNumberOfTouches = 0;
        continuousMouseWheelRecognizer.allowedScrollTypesMask = UIScrollTypeMaskContinuous;
        continuousMouseWheelRecognizer.allowedTouchTypes = @[@(UITouchTypeIndirectPointer)];
        [self addGestureRecognizer:continuousMouseWheelRecognizer];
    }
    
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        UIHoverGestureRecognizer *stylusHoverRecognizer = [[UIHoverGestureRecognizer alloc] initWithTarget:self action:@selector(sendStylusHoverEvent:)];
        stylusHoverRecognizer.allowedTouchTypes = @[@(UITouchTypePencil)];
        [self addGestureRecognizer:stylusHoverRecognizer];
    }
#endif
#endif
    
    x1mouse = [[X1Mouse alloc] init];
    x1mouse.delegate = self;
    
    if (settings.btMouseSupport) {
        [x1mouse start];
    }
    
    // This is critical to ensure keyboard events are delivered to this
    // StreamView and not our parent UIView, especially on tvOS.
    [self becomeFirstResponder];
}

- (UIButton *)desktopToolbarButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:0.19 alpha:1];
    button.contentEdgeInsets = UIEdgeInsetsMake(0, 12, 0, 12);
    button.layer.cornerRadius = 8.0;
    button.accessibilityLabel = title;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:52.0].active = YES;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
    return button;
}

- (void)installDesktopToolbar {
    desktopToolbar = [[UIView alloc] init];
    desktopToolbar.translatesAutoresizingMaskIntoConstraints = NO;
    desktopToolbar.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    desktopToolbar.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.16].CGColor;
    desktopToolbar.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    desktopToolbar.layer.cornerRadius = 10.0;
    desktopToolbar.clipsToBounds = YES;
    [self addSubview:desktopToolbar];

    NSLayoutYAxisAnchor *topAnchor = self.safeAreaLayoutGuide.topAnchor;
    [NSLayoutConstraint activateConstraints:@[
        [desktopToolbar.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8.0],
        [desktopToolbar.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8.0],
        [desktopToolbar.topAnchor constraintEqualToAnchor:topAnchor constant:8.0],
        [desktopToolbar.heightAnchor constraintEqualToConstant:60.0],
    ]];

    UIButton *hideButton = [self desktopToolbarButtonWithTitle:@"Hide" action:@selector(hideDesktopToolbar:)];
    UIButton *keyboardButton = [self desktopToolbarButtonWithTitle:@"Keyboard" action:@selector(showDesktopKeyboard:)];
    UIButton *reconnectButton = [self desktopToolbarButtonWithTitle:@"Reconnect" action:@selector(requestDesktopReconnect:)];

    desktopInputModeSelector = [[UISegmentedControl alloc] initWithItems:@[@"Touch", @"Mouse", @"Hybrid"]];
    desktopInputModeSelector.translatesAutoresizingMaskIntoConstraints = NO;
    desktopInputModeSelector.selectedSegmentIndex = streamConfig.inputMode;
    desktopInputModeSelector.accessibilityLabel = @"Input mode";
    [desktopInputModeSelector addTarget:self action:@selector(desktopInputModeChanged:) forControlEvents:UIControlEventValueChanged];
    [desktopInputModeSelector.widthAnchor constraintGreaterThanOrEqualToConstant:190.0].active = YES;
    [desktopInputModeSelector.heightAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;

    UIButton *statsButton = [self desktopToolbarButtonWithTitle:@"Stats" action:@selector(requestDesktopDiagnostics:)];
    UIButton *disconnectButton = [self desktopToolbarButtonWithTitle:@"Disconnect" action:@selector(requestDesktopDisconnect:)];
    reconnectButton.enabled = streamConfig.profile.reconnectEnabled;
    reconnectButton.hidden = !reconnectButton.enabled;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        hideButton, desktopInputModeSelector, keyboardButton, reconnectButton, statsButton, disconnectButton,
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisHorizontal;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8.0;
    stack.distribution = UIStackViewDistributionFill;
    [desktopToolbar addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:desktopToolbar.leadingAnchor constant:8.0],
        [stack.trailingAnchor constraintEqualToAnchor:desktopToolbar.trailingAnchor constant:-8.0],
        [stack.topAnchor constraintEqualToAnchor:desktopToolbar.topAnchor constant:8.0],
        [stack.bottomAnchor constraintEqualToAnchor:desktopToolbar.bottomAnchor constant:-8.0],
    ]];

    desktopToolbarVisible = NO;
    desktopToolbar.hidden = YES;
    desktopToolbar.userInteractionEnabled = NO;

    UIScreenEdgePanGestureRecognizer *revealGesture = [[UIScreenEdgePanGestureRecognizer alloc] initWithTarget:self action:@selector(revealDesktopToolbar:)];
    revealGesture.edges = UIRectEdgeTop;
    revealGesture.delaysTouchesBegan = NO;
    revealGesture.delaysTouchesEnded = NO;
    [self addGestureRecognizer:revealGesture];
}

- (void)revealDesktopToolbar:(UIScreenEdgePanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateRecognized) {
        [self setDesktopToolbarVisible:YES animated:YES];
    }
}

- (BOOL)isDesktopToolbarVisible {
    return desktopToolbarVisible;
}

- (void)setDesktopToolbarVisible:(BOOL)visible animated:(BOOL)animated {
    if (!desktopMode || desktopToolbarVisible == visible) {
        return;
    }

    desktopToolbarVisible = visible;
    desktopToolbar.userInteractionEnabled = visible;
    if (visible) {
        desktopToolbar.hidden = NO;
    }

    void (^changes)(void) = ^{
        self->desktopToolbar.alpha = visible ? 1.0 : 0.0;
    };
    void (^completion)(BOOL) = ^(BOOL finished) {
        if (!visible) {
            self->desktopToolbar.hidden = YES;
        }
    };
    if (animated) {
        desktopToolbar.alpha = visible ? 0.0 : 1.0;
        [UIView animateWithDuration:0.2 animations:changes completion:completion];
    }
    else {
        changes();
        completion(YES);
    }
}

- (void)hideDesktopToolbar:(UIButton *)sender {
    [self setDesktopToolbarVisible:NO animated:YES];
}

- (void)desktopInputModeChanged:(UISegmentedControl *)sender {
    [self setInputMode:(LMInputMode)sender.selectedSegmentIndex];
}

- (void)setInputMode:(LMInputMode)inputMode {
    streamConfig.inputMode = inputMode;
    if ([touchHandler respondsToSelector:@selector(setInputMode:)]) {
        [(AbsoluteTouchHandler *)touchHandler setInputMode:inputMode];
    }
    desktopInputModeSelector.selectedSegmentIndex = inputMode;
}

- (void)requestDesktopReconnect:(UIButton *)sender {
    if ([interactionDelegate respondsToSelector:@selector(streamViewDidRequestReconnect:)]) {
        [interactionDelegate streamViewDidRequestReconnect:self];
    }
}

- (void)requestDesktopDiagnostics:(UIButton *)sender {
    if ([interactionDelegate respondsToSelector:@selector(streamViewDidRequestDiagnostics:)]) {
        [interactionDelegate streamViewDidRequestDiagnostics:self];
    }
}

- (void)requestDesktopDisconnect:(UIButton *)sender {
    if ([interactionDelegate respondsToSelector:@selector(streamViewDidRequestDisconnect:)]) {
        [interactionDelegate streamViewDidRequestDisconnect:self];
    }
}

- (short)keyCodeForDesktopAction:(LMKeyboardAction)action {
    switch (action) {
        case LMKeyboardActionEscape:
            return 0x1B;
        case LMKeyboardActionTab:
            return 0x09;
        case LMKeyboardActionControl:
            return 0xA2;
        case LMKeyboardActionShift:
            return 0xA0;
        case LMKeyboardActionAlt:
            return 0xA4;
        case LMKeyboardActionWindows:
            return 0x5B;
        case LMKeyboardActionDelete:
            return 0x2E;
    }
    return 0;
}

- (void)sendDesktopKeyboardAction:(LMKeyboardAction)action pressed:(BOOL)pressed {
    LiSendKeyboardEvent([self keyCodeForDesktopAction:action],
                         pressed ? KEY_ACTION_DOWN : KEY_ACTION_UP,
                         0);
}

- (UIBarButtonItem *)desktopKeyboardButtonWithTitle:(NSString *)title action:(LMKeyboardAction)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor blackColor];
    button.layer.cornerRadius = 6.0;
    button.accessibilityLabel = title;
    button.frame = CGRectMake(0, 0, 52, 36);
    objc_setAssociatedObject(button, LMKeyboardActionAssociationKey, @(action), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:self action:@selector(desktopKeyboardActionDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(desktopKeyboardActionUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return [[UIBarButtonItem alloc] initWithCustomView:button];
}

- (LMKeyboardAction)desktopKeyboardActionForButton:(UIButton *)button {
    return [objc_getAssociatedObject(button, LMKeyboardActionAssociationKey) integerValue];
}

- (void)desktopKeyboardActionDown:(UIButton *)sender {
    [keyInputField sendKeyboardAction:[self desktopKeyboardActionForButton:sender] pressed:YES];
}

- (void)desktopKeyboardActionUp:(UIButton *)sender {
    [keyInputField sendKeyboardAction:[self desktopKeyboardActionForButton:sender] pressed:NO];
}

- (void)showDesktopKeyboard:(UIButton *)sender {
    [self releaseKeyboardActions];
    [keyInputField resignFirstResponder];
    keyInputField.delegate = self;
    keyInputField.text = @"0";
    __weak StreamView *weakSelf = self;
    keyInputField.keyboardActionHandler = ^(LMKeyboardAction action, BOOL pressed) {
        [weakSelf sendDesktopKeyboardAction:action pressed:pressed];
    };
    if (!keyboardTargetInstalled) {
        [keyInputField addTarget:self action:@selector(onKeyboardPressed:) forControlEvents:UIControlEventEditingChanged];
        keyboardTargetInstalled = YES;
    }

    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 44.0)];
    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
    toolbar.items = @[
        [self desktopKeyboardButtonWithTitle:@"Esc" action:LMKeyboardActionEscape],
        [self desktopKeyboardButtonWithTitle:@"Tab" action:LMKeyboardActionTab],
        [self desktopKeyboardButtonWithTitle:@"Ctrl" action:LMKeyboardActionControl],
        [self desktopKeyboardButtonWithTitle:@"Shift" action:LMKeyboardActionShift],
        [self desktopKeyboardButtonWithTitle:@"Alt" action:LMKeyboardActionAlt],
        [self desktopKeyboardButtonWithTitle:@"Win" action:LMKeyboardActionWindows],
        [self desktopKeyboardButtonWithTitle:@"Del" action:LMKeyboardActionDelete],
        flexibleSpace,
    ];
    keyInputField.inputAccessoryView = toolbar;
    isInputingText = YES;
    [keyInputField becomeFirstResponder];
}

- (void)releaseKeyboardActions {
    [keyInputField releaseAllKeyboardActions];
}

- (void)startInteractionTimer {
    // Restart user interaction tracking
    hasUserInteracted = NO;
    
    BOOL timerAlreadyRunning = interactionTimer != nil;
    
    // Start/restart the timer
    [interactionTimer invalidate];
    interactionTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                        target:self
                        selector:@selector(interactionTimerExpired:)
                        userInfo:nil
                        repeats:NO];
    
    // Notify the delegate if this was a new user interaction
    if (!timerAlreadyRunning) {
        [interactionDelegate userInteractionBegan];
    }
}

- (void)interactionTimerExpired:(NSTimer *)timer {
    if (!hasUserInteracted) {
        // User has finished touching the screen
        interactionTimer = nil;
        [interactionDelegate userInteractionEnded];
    }
    else {
        // User is still touching the screen. Restart the timer.
        [self startInteractionTimer];
    }
}

- (void) showOnScreenControls {
#if !TARGET_OS_TV
    [onScreenControls show];
#endif
}

- (void) cancelAllTouches {
    if ([touchHandler respondsToSelector:@selector(cancelAllTouches)]) {
        [(id<StreamDeskTouchCancellation>)touchHandler cancelAllTouches];
    }
    [self releaseKeyboardActions];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window == nil) {
        [self cancelAllTouches];
        [keyInputField resignFirstResponder];
    }
}

- (OnScreenControlsLevel) getCurrentOscState {
    if (onScreenControls == nil) {
        return OnScreenControlsLevelOff;
    }
    else {
        return [onScreenControls getLevel];
    }
}

- (CGSize) getVideoAreaSize {
    if (self.bounds.size.width > self.bounds.size.height * streamAspectRatio) {
        return CGSizeMake(self.bounds.size.height * streamAspectRatio, self.bounds.size.height);
    } else {
        return CGSizeMake(self.bounds.size.width, self.bounds.size.width / streamAspectRatio);
    }
}

- (CGRect) displayedVideoRect {
    CGSize videoSize = [self getVideoAreaSize];
    return CGRectMake(CGRectGetMidX(self.bounds) - videoSize.width / 2.0,
                      CGRectGetMidY(self.bounds) - videoSize.height / 2.0,
                      videoSize.width,
                      videoSize.height);
}

- (CGPoint) normalizedPointForTouch:(CGPoint)point {
    return LMNormalizedPointForTouch(point, self.bounds, [self displayedVideoRect]);
}

- (CGPoint) adjustCoordinatesForVideoArea:(CGPoint)point {
    CGRect displayedVideoRect = [self displayedVideoRect];
    CGPoint normalizedPoint = [self normalizedPointForTouch:point];
    return CGPointMake(normalizedPoint.x * CGRectGetWidth(displayedVideoRect),
                       normalizedPoint.y * CGRectGetHeight(displayedVideoRect));
}

#if !TARGET_OS_TV

- (uint16_t)getRotationFromAzimuthAngle:(float)azimuthAngle {
    // iOS reports azimuth of 0 when the stylus is pointing west, but Moonlight expects
    // rotation of 0 to mean the stylus is pointing north. Rotate the azimuth angle
    // clockwise by 90 degrees to convert from iOS to Moonlight rotation conventions.
    int32_t rotationAngle = (azimuthAngle - M_PI_2) * (180.f / M_PI);
    if (rotationAngle < 0) {
        rotationAngle += 360;
    }
    return (uint16_t)rotationAngle;
}

- (uint8_t)getTiltFromAltitudeAngle:(float)altitudeAngle {
    // iOS reports an altitude of 0 when the stylus is parallel to the touch surface,
    // while Moonlight expects a tilt of 0 when the stylus is perpendicular to the surface.
    // Subtract the tilt angle from 90 to convert from iOS to Moonlight tilt conventions.
    uint8_t altitudeDegs = abs((int16_t)(altitudeAngle * (180.f / M_PI)));
    return 90 - MIN(90, altitudeDegs);
}

- (BOOL)sendStylusEvent:(UITouch*)event {
    uint8_t type;
    
    // Don't touch stylus events if the host doesn't support them. We want to pass
    // them as normal touches for legacy hosts that don't understand pen events.
    if (!(LiGetHostFeatureFlags() & LI_FF_PEN_TOUCH_EVENTS)) {
        return NO;
    }
    
    switch (event.phase) {
        case UITouchPhaseBegan:
            type = LI_TOUCH_EVENT_DOWN;
            break;
        case UITouchPhaseMoved:
            type = LI_TOUCH_EVENT_MOVE;
            break;
        case UITouchPhaseEnded:
            type = LI_TOUCH_EVENT_UP;
            break;
        case UITouchPhaseCancelled:
            type = LI_TOUCH_EVENT_CANCEL;
            break;
        default:
            return YES;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[event locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    return LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                          (event.force / event.maximumPossibleForce) / sin(event.altitudeAngle),
                          0.0f, 0.0f,
                          [self getRotationFromAzimuthAngle:[event azimuthAngleInView:self]],
                          [self getTiltFromAltitudeAngle:event.altitudeAngle]) != LI_ERR_UNSUPPORTED;
}

- (void)sendStylusHoverEvent:(UIHoverGestureRecognizer*)gesture API_AVAILABLE(ios(13.0)) {
    uint8_t type;
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            type = LI_TOUCH_EVENT_HOVER;
            break;

        case UIGestureRecognizerStateEnded:
            type = LI_TOUCH_EVENT_HOVER_LEAVE;
            break;

        default:
            return;
    }

    CGPoint location = [self adjustCoordinatesForVideoArea:[gesture locationInView:self]];
    CGSize videoSize = [self getVideoAreaSize];
    
    float distance = 0.0f;
#if defined(__IPHONE_16_1) || defined(__TVOS_16_1)
    if (@available(iOS 16.1, *)) {
        distance = gesture.zOffset;
    }
#endif
    
    uint16_t rotationAngle = LI_ROT_UNKNOWN;
    uint8_t tiltAngle = LI_TILT_UNKNOWN;
#if defined(__IPHONE_16_4) || defined(__TVOS_16_4)
    if (@available(iOS 16.4, *)) {
        rotationAngle = [self getRotationFromAzimuthAngle:[gesture azimuthAngleInView:self]];
        tiltAngle = [self getTiltFromAltitudeAngle:gesture.altitudeAngle];
    }
#endif
    
    LiSendPenEvent(type, LI_TOOL_TYPE_PEN, 0, location.x / videoSize.width, location.y / videoSize.height,
                   distance, 0.0f, 0.0f, rotationAngle, tiltAngle);
}

#endif

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_PRESS
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch down");
    
    // Notify of user interaction and start expiration timer
    [self startInteractionTimer];
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchDownEvent:touches]) {
        // We still inform the touch handler even if we're going trigger the
        // keyboard activation gesture. This is important to ensure the touch
        // handler has a consistent view of touch events to correctly suppress
        // activation of one or two finger gestures when a three finger gesture
        // is triggered.
        [touchHandler touchesBegan:touches withEvent:event];
        
        if ([[event allTouches] count] == 3) {
            if (isInputingText) {
                Log(LOG_D, @"Closing the keyboard");
                [keyInputField resignFirstResponder];
                isInputingText = false;
            } else {
                Log(LOG_D, @"Opening the keyboard");
                // Prepare the textbox used to capture keyboard events.
                keyInputField.delegate = self;
                keyInputField.text = @"0";
                if (desktopMode) {
                    [self showDesktopKeyboard:nil];
                }
                else {
#if !TARGET_OS_TV
                    // Prepare the toolbar above the keyboard for more options.
                    UIToolbar *customToolbarView = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 44)];
                    UIBarButtonItem *doneBarButton = [self createButtonWithImageNamed:@"DoneIcon.png" backgroundColor:[UIColor clearColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x00 isToggleable:NO];
                    UIBarButtonItem *windowsBarButton = [self createButtonWithImageNamed:@"WindowsIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x5B isToggleable:YES];
                    UIBarButtonItem *tabBarButton = [self createButtonWithImageNamed:@"TabIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x09 isToggleable:NO];
                    UIBarButtonItem *shiftBarButton = [self createButtonWithImageNamed:@"ShiftIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0xA0 isToggleable:YES];
                    UIBarButtonItem *escapeBarButton = [self createButtonWithImageNamed:@"EscapeIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x1B isToggleable:NO];
                    UIBarButtonItem *controlBarButton = [self createButtonWithImageNamed:@"ControlIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0xA2 isToggleable:YES];
                    UIBarButtonItem *altBarButton = [self createButtonWithImageNamed:@"AltIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0xA4 isToggleable:YES];
                    UIBarButtonItem *deleteBarButton = [self createButtonWithImageNamed:@"DeleteIcon.png" backgroundColor:[UIColor blackColor] target:self action:@selector(toolbarButtonClicked:) keyCode:0x2E isToggleable:NO];
                    UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:nil action:nil];
                    [customToolbarView setItems:@[doneBarButton, windowsBarButton, escapeBarButton, tabBarButton, shiftBarButton, controlBarButton, altBarButton, deleteBarButton, flexibleSpace]];
                    keyInputField.inputAccessoryView = customToolbarView;
#endif
                    [keyInputField becomeFirstResponder];
                    [keyInputField addTarget:self action:@selector(onKeyboardPressed:) forControlEvents:UIControlEventEditingChanged];
                    isInputingText = true;
                }

                // Undo causes issues for our state management, so turn it off.
                [keyInputField.undoManager disableUndoRegistration];
            }
        }
    }
}

- (UIBarButtonItem *)createButtonWithImageNamed:(NSString *)imageName backgroundColor:(UIColor *)backgroundColor target:(id)target action:(SEL)action keyCode:(NSInteger)keyCode isToggleable:(BOOL)isToggleable {
    UIImage *image = [UIImage imageNamed:imageName];
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:image forState:UIControlStateNormal];
    button.frame = CGRectMake(0, 0, 30, 30);
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    button.imageView.backgroundColor = backgroundColor;
    button.imageView.layer.cornerRadius = 10.0;
    button.imageEdgeInsets = UIEdgeInsetsMake(6, 6, 6, 6);
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    objc_setAssociatedObject(button, "keyCode", @(keyCode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isToggleable", @(isToggleable), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(button, "isOn", @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIBarButtonItem *barButton = [[UIBarButtonItem alloc] initWithCustomView:button];
    return barButton;
}

- (void)toolbarButtonClicked:(UIButton *)sender {
    BOOL isToggleable = [objc_getAssociatedObject(sender, "isToggleable") boolValue];
    BOOL isOn = [objc_getAssociatedObject(sender, "isOn") boolValue];
    if (isToggleable){
        isOn = !isOn;
        // Update the button's appearance based on its new state
        if (isOn) {
            sender.imageView.backgroundColor = [UIColor lightGrayColor];
        } else {
            sender.imageView.backgroundColor = [UIColor blackColor];
        }
    }
    // Update the new on/off state of the button
    objc_setAssociatedObject(sender, "isOn", @(isOn), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Get the keyCode parameter and convert to short for key press event
    short keyCode = [objc_getAssociatedObject(sender, "keyCode") shortValue];
    // Close keyboard if done button clicked
    if (!keyCode) {
        [keyInputField resignFirstResponder];
        isInputingText = false;
    }
    else {
        // Send key press event using keyCode parameter, toggle if necessary
        if (isToggleable){
            if (isOn){
                LiSendKeyboardEvent(keyCode, KEY_ACTION_DOWN, 0);
                [keysDown addObject:@(keyCode)];
            } else {
                LiSendKeyboardEvent(keyCode, KEY_ACTION_UP, 0);
                [keysDown removeObject:@(keyCode)];
            }
        }
        else {
            LiSendKeyboardEvent(keyCode, KEY_ACTION_DOWN, 0);
            usleep(50 * 1000);
            LiSendKeyboardEvent(keyCode, KEY_ACTION_UP, 0);
        }
    }
}

- (BOOL)handleMouseButtonEvent:(int)buttonAction forTouches:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        UITouch* touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return YES;
                }
            }
            
            UIEventButtonMask normalizedButtonMask;
            
            // iOS 14 includes the released button in the buttonMask for the release
            // event, while iOS 13 does not. Normalize that behavior here.
            if (@available(iOS 14.0, *)) {
                if (buttonAction == BUTTON_ACTION_RELEASE) {
                    normalizedButtonMask = lastMouseButtonMask & ~event.buttonMask;
                }
                else {
                    normalizedButtonMask = event.buttonMask;
                }
            }
            else {
                normalizedButtonMask = event.buttonMask;
            }
            
            UIEventButtonMask changedButtons = lastMouseButtonMask ^ normalizedButtonMask;
                        
            for (int i = BUTTON_LEFT; i <= BUTTON_X2; i++) {
                UIEventButtonMask buttonFlag;
                
                switch (i) {
                    // Right and Middle are reversed from what iOS uses
                    case BUTTON_RIGHT:
                        buttonFlag = UIEventButtonMaskForButtonNumber(2);
                        break;
                    case BUTTON_MIDDLE:
                        buttonFlag = UIEventButtonMaskForButtonNumber(3);
                        break;
                        
                    default:
                        buttonFlag = UIEventButtonMaskForButtonNumber(i);
                        break;
                }
                
                if (changedButtons & buttonFlag) {
                    LiSendMouseButtonEvent(buttonAction, i);
                }
            }
            
            lastMouseButtonMask = normalizedButtonMask;
            return YES;
        }
    }
#endif
    
    return NO;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
        
        UITouch *touch = [touches anyObject];
        if (touch.type == UITouchTypeIndirectPointer) {
            if (@available(iOS 14.0, *)) {
                if ([GCMouse current] != nil) {
                    // We'll handle this with GCMouse. Do nothing here.
                    return;
                }
            }
            
            // We must handle this event to properly support
            // drags while the middle, X1, or X2 mouse buttons are
            // held down. For some reason, left and right buttons
            // don't require this, but we do it anyway for them too.
            // Cursor movement without a button held down is handled
            // in pointerInteraction:regionForRequest:defaultRegion.
            [self updateCursorLocation:[touch locationInView:self] isMouse:YES];
            return;
        }
    }
#endif
    
    hasUserInteracted = YES;
    
    if (![onScreenControls handleTouchMovedEvent:touches]) {
        [touchHandler touchesMoved:touches withEvent:event];
    }
}

- (void)pressesBegan:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:YES]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesBegan:presses withEvent:event];
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    BOOL handled = NO;
    
    if (@available(iOS 13.4, tvOS 13.4, *)) {
        for (UIPress* press in presses) {
            // For now, we'll treated it as handled if we handle at least one of the
            // UIPress events inside the set.
            if ([KeyboardSupport sendKeyEventForPress:press down:NO]) {
                // This will prevent the legacy UITextField from receiving the event
                handled = YES;
            }
        }
    }
    
    if (!handled) {
        [super pressesEnded:presses withEvent:event];
    }
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if ([self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                          forTouches:touches
                           withEvent:event]) {
        // If it's a mouse event, we're done
        return;
    }
    
    Log(LOG_D, @"Touch up");
    
    hasUserInteracted = YES;
    
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                if ([self sendStylusEvent:touch]) {
                    return;
                }
            }
        }
    }
#endif
    
    if (![onScreenControls handleTouchUpEvent:touches]) {
        [touchHandler touchesEnded:touches withEvent:event];
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    [touchHandler touchesCancelled:touches withEvent:event];
    [self handleMouseButtonEvent:BUTTON_ACTION_RELEASE
                      forTouches:touches
                       withEvent:event];
#if !TARGET_OS_TV
    if (@available(iOS 13.4, *)) {
        for (UITouch* touch in touches) {
            if (touch.type == UITouchTypePencil) {
                [self sendStylusEvent:touch];
            }
        }
    }
#endif
}

#if !TARGET_OS_TV
- (void) updateCursorLocation:(CGPoint)location isMouse:(BOOL)isMouse {
    CGPoint normalizedLocation = [self adjustCoordinatesForVideoArea:location];
    CGRect displayedVideoRect = [self displayedVideoRect];
    
    // Send the mouse position relative to the video region if it has changed
    // if we're receiving coordinates from a real mouse.
    //
    // NB: It is important for functionality (not just optimization) to only
    // send it if the value has changed. We will receive one of these events
    // any time the user presses a modifier key, which can result in errant
    // mouse motion when using a Citrix X1 mouse.
    if (normalizedLocation.x != lastMouseX || normalizedLocation.y != lastMouseY || !isMouse) {
        if (lastMouseX != 0 || lastMouseY != 0 || !isMouse) {
            LiSendMousePositionEvent(normalizedLocation.x, normalizedLocation.y,
                                     displayedVideoRect.size.width, displayedVideoRect.size.height);
        }
        
        if (isMouse) {
            lastMouseX = normalizedLocation.x;
            lastMouseY = normalizedLocation.y;
        }
    }
}

- (UIPointerRegion *)pointerInteraction:(UIPointerInteraction *)interaction
                       regionForRequest:(UIPointerRegionRequest *)request
                          defaultRegion:(UIPointerRegion *)defaultRegion API_AVAILABLE(ios(13.4)) {
    if (@available(iOS 14.0, *)) {
        if ([GCMouse current] != nil) {
            // We'll handle this with GCMouse. Do nothing here.
            return nil;
        }
    }
    
    // This logic mimics what iOS does with AVLayerVideoGravityResizeAspect
    CGRect displayedVideoRect = [self displayedVideoRect];
    
    // Move the cursor on the host if no buttons are pressed.
    // Motion with buttons pressed in handled in touchesMoved:
    if (lastMouseButtonMask == 0) {
        [self updateCursorLocation:request.location isMouse:YES];
    }
    
    // The pointer interaction should cover the video region only
    return [UIPointerRegion regionWithRect:displayedVideoRect identifier:nil];
}

- (UIPointerStyle *)pointerInteraction:(UIPointerInteraction *)interaction styleForRegion:(UIPointerRegion *)region  API_AVAILABLE(ios(13.4)) {
    // Always hide the mouse cursor over our stream view
    return [UIPointerStyle hiddenPointerStyle];
}

- (void)mouseWheelMovedContinuous:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    const short translationMultiplier = 120 * 20; // WHEEL_DELTA * 20
    
    {
        short translationDeltaY = ((currentScrollTranslation.y - lastScrollTranslation.y) / self.bounds.size.height) * translationMultiplier;
        if (translationDeltaY != 0) {
            LiSendHighResScrollEvent(translationDeltaY);
            lastScrollTranslation = currentScrollTranslation;
        }
    }

    {
        short translationDeltaX = ((currentScrollTranslation.x - lastScrollTranslation.x) / self.bounds.size.width) * translationMultiplier;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHighResHScrollEvent(-translationDeltaX);
            lastScrollTranslation = currentScrollTranslation;
        }
    }
}

- (void)mouseWheelMovedDiscrete:(UIPanGestureRecognizer *)gesture {
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            break;
        
        case UIGestureRecognizerStateEnded:
        default:
            // Ignore recognition failure and other states
            lastScrollTranslation = CGPointMake(0, 0);
            return;
    }
    
    // Using velocityInView is 0 for discrete scroll events
    // when scrolling very slowly, but translationInView does work.
    CGPoint currentScrollTranslation = [gesture translationInView:self];
    
    {
        short translationDeltaY = currentScrollTranslation.y - lastScrollTranslation.y;
        if (translationDeltaY != 0) {
            LiSendScrollEvent(translationDeltaY > 0 ? 1 : -1);
        }
    }

    {
        short translationDeltaX = currentScrollTranslation.x - lastScrollTranslation.x;
        if (translationDeltaX != 0) {
            // Direction is reversed from vertical scrolling
            LiSendHScrollEvent(translationDeltaX < 0 ? 1 : -1);
        }
    }
    
    lastScrollTranslation = currentScrollTranslation;
}

#endif

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (@available(iOS 13.0, *)) {
        // Disable the 3 finger tap gestures that trigger the copy/paste/undo toolbar on iOS 13+
        return gestureRecognizer.name == nil || ![gestureRecognizer.name hasPrefix:@"kbProductivity."];
    }
    else {
        return YES;
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self sendKeystroke:(struct KeyEvent){.keycode = 0x0D} flags:0];
    return NO;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    [keyInputField releaseAllKeyboardActions];
    for (NSNumber* keyCode in keysDown) {
        LiSendKeyboardEvent([keyCode shortValue], KEY_ACTION_UP, 0);
    }
    [keysDown removeAllObjects];
}

- (void)sendKeyboardText:(NSString *)inputText {
    if ([inputText isEqualToString:@""]) {
        [self sendKeystroke:(struct KeyEvent){.keycode = 0x08} flags:0];
        return;
    }

    // The field starts with a sentinel so iOS reports Backspace on an otherwise empty field.
    for (NSUInteger i = 1; i < inputText.length; i++) {
        struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
        if (event.keycode == 0) {
            NSData *utf8 = [[inputText substringFromIndex:1] dataUsingEncoding:NSUTF8StringEncoding];
            if (utf8.length != 0) {
                LiSendUtf8TextEvent(utf8.bytes, (unsigned int)utf8.length);
            }
            return;
        }
    }

    for (NSUInteger i = 1; i < inputText.length; i++) {
        struct KeyEvent event = [KeyboardSupport translateKeyEvent:[inputText characterAtIndex:i] withModifierFlags:0];
        [self sendLowLevelEvent:event];
    }
}

- (void)onKeyboardPressed:(UITextField *)textField {
    NSString *inputText = textField.text;
    if (desktopMode) {
        [self sendKeyboardText:inputText];
    }
    else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            [self sendKeyboardText:inputText];
        });
    }
    
    // Reset text field back to known state
    textField.text = @"0";
    
    // Move the insertion point back to the end of the text box
    UITextRange *textRange = [textField textRangeFromPosition:textField.endOfDocument toPosition:textField.endOfDocument];
    [textField setSelectedTextRange:textRange];
}

- (void)specialCharPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:0x20 withModifierFlags:[cmd modifierFlags]];
    event.keycode = [[dictCodes valueForKey:[cmd input]] intValue];
    [self sendLowLevelEvent:event];
}

- (void)keyPressed:(UIKeyCommand *)cmd {
    struct KeyEvent event = [KeyboardSupport translateKeyEvent:[[cmd input] characterAtIndex:0] withModifierFlags:[cmd modifierFlags]];
    [self sendLowLevelEvent:event];
}

- (void)sendLowLevelEvent:(struct KeyEvent)event {
    if (desktopMode) {
        [self sendKeystroke:event flags:SS_KBE_FLAG_NON_NORMALIZED];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        [self sendKeystroke:event flags:SS_KBE_FLAG_NON_NORMALIZED];
    });
}

- (void)sendKeystroke:(struct KeyEvent)event flags:(char)flags {
    if (event.modifier != 0) {
        LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_DOWN, event.modifier);
    }
    LiSendKeyboardEvent2(event.keycode, KEY_ACTION_DOWN, event.modifier, flags);
    if (!desktopMode) {
        usleep(50 * 1000);
    }
    LiSendKeyboardEvent2(event.keycode, KEY_ACTION_UP, event.modifier, flags);
    if (event.modifier != 0) {
        LiSendKeyboardEvent(event.modifierKeycode, KEY_ACTION_UP, event.modifier);
    }
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (NSArray<UIKeyCommand *> *)keyCommands
{
    NSString *charset = @"qwertyuiopasdfghjklzxcvbnm1234567890\t§[]\\'\"/.,`<>-´ç+`¡'º;ñ= ";
    
    NSMutableArray<UIKeyCommand *> * commands = [NSMutableArray<UIKeyCommand *> array];
    dictCodes = [[NSDictionary alloc] initWithObjectsAndKeys: [NSNumber numberWithInt: 0x0d], @"\r", [NSNumber numberWithInt: 0x08], @"\b", [NSNumber numberWithInt: 0x1b], UIKeyInputEscape, [NSNumber numberWithInt: 0x28], UIKeyInputDownArrow, [NSNumber numberWithInt: 0x26], UIKeyInputUpArrow, [NSNumber numberWithInt: 0x25], UIKeyInputLeftArrow, [NSNumber numberWithInt: 0x27], UIKeyInputRightArrow, nil];
    
    [charset enumerateSubstringsInRange:NSMakeRange(0, charset.length)
                                options:NSStringEnumerationByComposedCharacterSequences
                             usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:0 action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierShift action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierControl action:@selector(keyPressed:)]];
                                 [commands addObject:[UIKeyCommand keyCommandWithInput:substring modifierFlags:UIKeyModifierAlternate action:@selector(keyPressed:)]];
                             }];
    
    for (NSString *c in [dictCodes keyEnumerator]) {
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:0
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierShift | UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierControl | UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
        [commands addObject:[UIKeyCommand keyCommandWithInput:c
                                                modifierFlags:UIKeyModifierAlternate
                                                       action:@selector(specialCharPressed:)]];
    }
    
    return commands;
}

- (void)dealloc {
    [self cancelAllTouches];
    [keyInputField releaseAllKeyboardActions];
}

- (void)connectedStateDidChangeWithIdentifier:(NSUUID * _Nonnull)identifier isConnected:(BOOL)isConnected {
    NSLog(@"Citrix X1 mouse state change: %@ -> %s",
          identifier, isConnected ? "connected" : "disconnected");
}

- (void)mouseDidMoveWithIdentifier:(NSUUID * _Nonnull)identifier deltaX:(int16_t)deltaX deltaY:(int16_t)deltaY {
    accumulatedMouseDeltaX += deltaX / X1_MOUSE_SPEED_DIVISOR;
    accumulatedMouseDeltaY += deltaY / X1_MOUSE_SPEED_DIVISOR;
    
    short shortX = (short)accumulatedMouseDeltaX;
    short shortY = (short)accumulatedMouseDeltaY;
    
    if (shortX == 0 && shortY == 0) {
        return;
    }
    
    LiSendMouseMoveEvent(shortX, shortY);
    
    accumulatedMouseDeltaX -= shortX;
    accumulatedMouseDeltaY -= shortY;
}

- (int) buttonFromX1ButtonCode:(enum X1MouseButton)button {
    switch (button) {
        case X1MouseButtonLeft:
            return BUTTON_LEFT;
        case X1MouseButtonRight:
            return BUTTON_RIGHT;
        case X1MouseButtonMiddle:
            return BUTTON_MIDDLE;
        default:
            return -1;
    }
}

- (void)mouseDownWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_PRESS, [self buttonFromX1ButtonCode:button]);
}

- (void)mouseUpWithIdentifier:(NSUUID * _Nonnull)identifier button:(enum X1MouseButton)button {
    LiSendMouseButtonEvent(BUTTON_ACTION_RELEASE, [self buttonFromX1ButtonCode:button]);
}

- (void)wheelDidScrollWithIdentifier:(NSUUID * _Nonnull)identifier deltaZ:(int8_t)deltaZ {
    LiSendScrollEvent(deltaZ);
}

#if !TARGET_OS_TV
- (BOOL)isMultipleTouchEnabled {
    return YES;
}
#endif

@end
