//
//  UIComputerView.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/22/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "UIComputerView.h"

@implementation UIComputerView {
    TemporaryHost* _host;
    UIImageView* _hostIcon;
#if !TARGET_OS_TV
    UIView* _cardSurface;
#endif
    UILabel* _hostLabel;
    UIImageView* _hostOverlay;
    UIActivityIndicatorView* _hostSpinner;
    id<HostCallback> _callback;
    CGSize _labelSize;
    NSString *_presentedName;
    NSString *_presentedStatus;
}
static const float REFRESH_CYCLE = 2.0f;

#if TARGET_OS_TV
static const int ITEM_PADDING = 50;
static const int LABEL_DY = 40;
#else
static const int LABEL_DY = 16;
#endif

- (id) init {
    self = [super init];
        
#if TARGET_OS_TV
    self.frame = CGRectMake(0, 0, 400, 400);
#else
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        self.frame = CGRectMake(0, 0, 168, 120);
    } else {
        self.frame = CGRectMake(0, 0, 112, 84);
    }
#endif
    
    _hostIcon = [[UIImageView alloc] initWithFrame:self.frame];
    [_hostIcon setImage:[UIImage imageNamed:@"Computer"]];
    
#if TARGET_OS_TV
    self.layer.shadowColor = UIColor.blackColor.CGColor;
    self.layer.shadowOffset = CGSizeMake(5, 8);
    self.layer.shadowOpacity = 0.3;
#else
    _cardSurface = [[UIView alloc] initWithFrame:self.bounds];
    _cardSurface.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    _cardSurface.layer.cornerRadius = 12;
    _cardSurface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    _cardSurface.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _cardSurface.clipsToBounds = YES;
    _cardSurface.userInteractionEnabled = NO;
    CGFloat glyphSide = CGRectGetHeight(self.bounds) * 0.46;
    _hostIcon.frame = CGRectMake((CGRectGetWidth(self.bounds) - glyphSide) / 2,
                                 (CGRectGetHeight(self.bounds) - glyphSide) / 2,
                                 glyphSide, glyphSide);
    _hostIcon.contentMode = UIViewContentModeScaleAspectFit;
    self.isAccessibilityElement = YES;
    _hostIcon.isAccessibilityElement = NO;
    [_cardSurface addSubview:_hostIcon];
#endif

    [self addTarget:self action:@selector(hostButtonSelected:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(hostButtonDeselected:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    
    _hostLabel = [[UILabel alloc] init];
    _hostLabel.textColor = [UIColor whiteColor];
#if !TARGET_OS_TV
    _hostLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    _hostLabel.textAlignment = NSTextAlignmentCenter;
    _hostLabel.lineBreakMode = NSLineBreakByTruncatingTail;
#endif
    
    _hostOverlay = [[UIImageView alloc] initWithFrame:CGRectMake(self.frame.size.width / 3, _hostIcon.frame.size.height / 4, _hostIcon.frame.size.width / 3, self.frame.size.height / 3)];
#if !TARGET_OS_TV
    _hostOverlay.frame = CGRectMake(CGRectGetWidth(self.bounds) - 34, 12, 22, 22);
    _hostOverlay.contentMode = UIViewContentModeScaleAspectFit;
#endif
    _hostSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    [_hostSpinner setFrame:_hostOverlay.frame];
    _hostSpinner.userInteractionEnabled = NO;
    _hostSpinner.hidesWhenStopped = YES;

    [self addSubview:_hostLabel];
    
#if TARGET_OS_TV
    [self addSubview:_hostIcon];
    _hostIcon.clipsToBounds = NO;
    _hostIcon.adjustsImageWhenAncestorFocused = YES;
    _hostIcon.masksFocusEffectToContents = YES;
    
    self.adjustsImageWhenHighlighted = NO;
    
    _hostOverlay.masksFocusEffectToContents = YES;
    _hostOverlay.adjustsImageWhenAncestorFocused = NO;
    
    [_hostIcon.overlayContentView addSubview:_hostOverlay];
    [_hostIcon.overlayContentView addSubview:_hostSpinner];
#else
    [self insertSubview:_cardSurface atIndex:0];
    [self addSubview:_hostOverlay];
    [self addSubview:_hostSpinner];
    
    if (@available(iOS 13.4.1, *)) {
        // Allow the button style to change when moused over
        self.pointerInteractionEnabled = YES;
    }
#endif
    
    return self;
}

- (void) hostButtonSelected:(id)sender {
#if !TARGET_OS_TV
    _cardSurface.layer.opacity = 0.65f;
#else
    _hostIcon.layer.opacity = 0.5f;
#endif
    _hostSpinner.layer.opacity = 0.5f;
    _hostOverlay.layer.opacity = 0.5f;
}
- (void) hostButtonDeselected:(id)sender {
#if !TARGET_OS_TV
    _cardSurface.layer.opacity = 1.0f;
#else
    _hostIcon.layer.opacity = 1.0f;
#endif
    _hostSpinner.layer.opacity = 1.0f;
    _hostOverlay.layer.opacity = 1.0f;
}

- (id) initForAddWithCallback:(id<HostCallback>)callback {
    self = [self init];
    _callback = callback;
    
    [self addTarget:self action:@selector(addClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    [_hostLabel setText:@"Add computer"];
    self.accessibilityLabel = @"Add computer";
    [_hostLabel sizeToFit];
    
#if TARGET_OS_TV
    [_hostOverlay setImage:[UIImage imageNamed:@"AddOverlayIcon"]];
#else
    _hostIcon.image = [[UIImage imageNamed:@"AddOverlayIcon"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    _hostIcon.tintColor = [UIColor colorWithRed:0.75 green:0.93 blue:0.79 alpha:1];
    self.accessibilityHint = @"Enter the address of a computer running Sunshine";
#endif
    
    [self updateBounds];
        
    return self;
}

- (id) initWithComputer:(TemporaryHost*)host andCallback:(id<HostCallback>)callback {
    self = [self init];
    _host = host;
    _callback = callback;
    
    // Use UIContextMenuInteraction on iOS 13.0+ and a standard UILongPressGestureRecognizer
    // for tvOS devices and iOS prior to 13.0.
#if !TARGET_OS_TV
    if (@available(iOS 13.0, *)) {
        UIContextMenuInteraction* rightClickInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:rightClickInteraction];
    }
    else
#endif
    {
        UILongPressGestureRecognizer* longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hostLongClicked:)];
        [self addGestureRecognizer:longPressRecognizer];
    }
    
    [self addTarget:self action:@selector(hostClicked) forControlEvents:UIControlEventPrimaryActionTriggered];
    
    [self updateContentsForHost:host];

    return self;
}

- (void)didMoveToSuperview {
    // Start our update loop when we are added to our cell
    if (self.superview != nil && _host != nil) {
        [self updateLoop];
    }
}

- (void) updateBounds {
#if !TARGET_OS_TV
    CGRect card = _cardSurface.frame;
    CGFloat labelHeight = ceil(_hostLabel.font.lineHeight);
    _hostLabel.frame = CGRectMake(0, CGRectGetMaxY(card) + LABEL_DY / 2,
                                  CGRectGetWidth(card), labelHeight);
    self.bounds = CGRectMake(0, 0, CGRectGetWidth(card), CGRectGetMaxY(_hostLabel.frame));
#else
    float x = FLT_MAX;
    float y = FLT_MAX;
    float width = 0;
    float height;
    
    float iconX = _hostIcon.frame.origin.x + _hostIcon.frame.size.width / 2;
    _hostLabel.center = CGPointMake(iconX, _hostIcon.frame.origin.y + _hostIcon.frame.size.height + LABEL_DY);
    
    x = MIN(x, _hostIcon.frame.origin.x);
    x = MIN(x, _hostLabel.frame.origin.x);
    
    y = MIN(y, _hostIcon.frame.origin.y);
    y = MIN(y, _hostLabel.frame.origin.y);

    width = MAX(width, _hostIcon.frame.size.width);
    width = MAX(width, _hostLabel.frame.size.width);
    
    height = _hostIcon.frame.size.height +
        _hostLabel.frame.size.height +
        LABEL_DY / 2;
    
    self.bounds = CGRectMake(x - ITEM_PADDING, y - ITEM_PADDING, width + 2 * ITEM_PADDING, height + 2 * ITEM_PADDING);
#endif
}

- (void) updateContentsForHost:(TemporaryHost*)host {
    NSString *status = @"Checking";
    if (host.state == StateOnline) {
        status = host.pairState == PairStateUnpaired ? @"Pairing needed" : @"Online";
    } else if (host.state == StateOffline) {
        status = @"Offline";
    }
    NSString *name = host.name ?: @"Computer";
    if ([_presentedName isEqualToString:name] && [_presentedStatus isEqualToString:status]) {
        return;
    }
    _presentedName = [name copy];
    _presentedStatus = status;
    self.accessibilityLabel = name;
    self.accessibilityValue = status;
    _hostLabel.text = name;
    [_hostLabel sizeToFit];
    
    if (host.state == StateOnline) {
        [_hostSpinner stopAnimating];

        if (host.pairState == PairStateUnpaired) {
            [_hostOverlay setImage:[UIImage imageNamed:@"LockedOverlayIcon"]];
        }
        else {
            [_hostOverlay setImage:nil];
        }
    }
    else if (host.state == StateOffline) {
        [_hostSpinner stopAnimating];
        [_hostOverlay setImage:[UIImage imageNamed:@"ErrorOverlayIcon"]];
    }
    else {
        [_hostOverlay setImage:nil];
        [_hostSpinner startAnimating];
    }
    
    [self updateBounds];
}

- (void) updateLoop {
    // Stop immediately if the view has been detached
    if (self.superview == nil) {
        return;
    }
    
    [self updateContentsForHost:_host];
    
    // Queue the next refresh cycle
    [self performSelector:@selector(updateLoop) withObject:self afterDelay:REFRESH_CYCLE];
}

- (void) hostLongClicked:(UILongPressGestureRecognizer*)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [_callback hostLongClicked:_host view:self];
    }
}

#if !TARGET_OS_TV
- (UIContextMenuConfiguration *)contextMenuInteraction:(UIContextMenuInteraction *)interaction
                        configurationForMenuAtLocation:(CGPoint)location {
    // We don't want to trigger the primary action at this point, so cancel
    // tracking touch on this view now. This will also have the (intended)
    // effect of removing the touch highlight on this view.
    [self cancelTrackingWithEvent:nil];
    
    [_callback hostLongClicked:_host view:self];
    return nil;
}
#endif

- (void) hostClicked {
    [_callback hostClicked:_host view:self];
}

- (void) addClicked {
    [_callback addHostClicked];
}

@end
