//
//  SettingsViewController.m
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "SettingsViewController.h"
#import "TemporarySettings.h"
#import "DataManager.h"
#import "../Stream/StreamConfiguration.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

typedef void (^LMSecondMonitorSettingsCompletion)(LMStreamProfile *profile, BOOL active, BOOL diagnostics);

@interface LMSecondMonitorSettingsViewController : UIViewController
@property (nonatomic, copy) NSString *hostUUID;
@property (nonatomic, copy) LMStreamProfile *profile;
@property (nonatomic) BOOL active;
@property (nonatomic, copy) LMSecondMonitorSettingsCompletion completion;
@end

@implementation LMSecondMonitorSettingsViewController {
    UIScrollView *_settingsScrollView;
    UIStackView *_settingsStack;
    UISegmentedControl *_modeSelector;
    UISegmentedControl *_resolutionSelector;
    UISegmentedControl *_fpsSelector;
    UISlider *_bitrateSlider;
    UILabel *_bitrateLabel;
    UISegmentedControl *_audioSelector;
    UISegmentedControl *_inputModeSelector;
    UISegmentedControl *_gestureSelector;
    UISwitch *_reconnectSwitch;
    UISwitch *_diagnosticsSwitch;
    NSArray<NSValue *> *_supportedResolutions;
    NSArray<NSNumber *> *_supportedFrameRates;
    LMDeviceCapabilityProfile _capabilityProfile;
}

- (UILabel *)sectionTitle:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    return label;
}

- (UILabel *)detailLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor lightGrayColor];
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    return label;
}

- (void)addSectionTitle:(NSString *)title {
    [_settingsStack addArrangedSubview:[self sectionTitle:title]];
}

- (void)addControl:(UIView *)control {
    control.translatesAutoresizingMaskIntoConstraints = NO;
    [_settingsStack addArrangedSubview:control];
}

- (NSInteger)selectedIndexForResolution:(CGSize)resolution {
    for (NSUInteger index = 0; index < _supportedResolutions.count; index++) {
        if (CGSizeEqualToSize(resolution, _supportedResolutions[index].CGSizeValue)) {
            return (NSInteger)index;
        }
    }
    return 0;
}

- (NSInteger)selectedIndexForFrameRate:(NSInteger)frameRate {
    NSUInteger index = [_supportedFrameRates indexOfObject:@(frameRate)];
    return index == NSNotFound ? 0 : (NSInteger)index;
}

- (void)updateBitrateLabel {
    _bitrateLabel.text = [NSString stringWithFormat:@"Bitrate: %.1f Mbps", _bitrateSlider.value / 1000.0];
}

- (void)bitrateChanged:(UISlider *)sender {
    [self updateBitrateLabel];
}

- (void)gestureChanged:(UISegmentedControl *)sender {
    if (sender.selectedSegmentIndex == 1) {
        _inputModeSelector.selectedSegmentIndex = LMInputModeHybrid;
    }
    else if (_inputModeSelector.selectedSegmentIndex == LMInputModeHybrid) {
        _inputModeSelector.selectedSegmentIndex = LMInputModeNativeTouch;
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Second Monitor";
    self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];

    if (self.profile == nil) {
        self.profile = [LMStreamProfile defaultSecondMonitorProfile];
    }
    _capabilityProfile = [LMStreamProfile currentDeviceCapabilityProfile];
    _supportedResolutions = [LMStreamProfile supportedResolutionsForCapabilityProfile:_capabilityProfile
                                                               experimental1080pEnabled:self.profile.experimental1080pEnabled];
    _supportedFrameRates = _capabilityProfile == LMDeviceCapabilityProfileIPadAir ? @[@30] : @[@30, @60];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                            target:self
                                                                                            action:@selector(cancelSettings:)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                             target:self
                                                                                             action:@selector(saveSettings:)];

    _settingsScrollView = [[UIScrollView alloc] init];
    _settingsScrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsScrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_settingsScrollView];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsScrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_settingsScrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_settingsScrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_settingsScrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    _settingsStack = [[UIStackView alloc] init];
    _settingsStack.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsStack.axis = UILayoutConstraintAxisVertical;
    _settingsStack.spacing = 12.0;
    [_settingsScrollView addSubview:_settingsStack];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsStack.leadingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.leadingAnchor constant:20.0],
        [_settingsStack.trailingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.trailingAnchor constant:-20.0],
        [_settingsStack.topAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.topAnchor constant:20.0],
        [_settingsStack.bottomAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.bottomAnchor constant:-20.0],
        [_settingsStack.widthAnchor constraintEqualToAnchor:_settingsScrollView.frameLayoutGuide.widthAnchor constant:-40.0],
    ]];

    [self addSectionTitle:@"Profile"];
    [self addControl:[self detailLabel:self.hostUUID.length != 0 ? [NSString stringWithFormat:@"Host profile: %@", self.hostUUID] : @"Host profile: default until a host is selected"]];
    _modeSelector = [[UISegmentedControl alloc] initWithItems:@[@"Game mode", @"Second Monitor"]];
    _modeSelector.selectedSegmentIndex = self.active ? 1 : 0;
    [self addControl:_modeSelector];

    [self addSectionTitle:@"Resolution"];
    NSMutableArray<NSString *> *resolutionTitles = [NSMutableArray array];
    for (NSValue *value in _supportedResolutions) {
        CGSize resolution = value.CGSizeValue;
        [resolutionTitles addObject:[NSString stringWithFormat:@"%ld x %ld", (long)resolution.width, (long)resolution.height]];
    }
    _resolutionSelector = [[UISegmentedControl alloc] initWithItems:resolutionTitles];
    _resolutionSelector.selectedSegmentIndex = [self selectedIndexForResolution:self.profile.resolution];
    [self addControl:_resolutionSelector];

    [self addSectionTitle:@"FPS"];
    NSMutableArray<NSString *> *frameRateTitles = [NSMutableArray array];
    for (NSNumber *frameRate in _supportedFrameRates) {
        [frameRateTitles addObject:[NSString stringWithFormat:@"%@ FPS", frameRate]];
    }
    _fpsSelector = [[UISegmentedControl alloc] initWithItems:frameRateTitles];
    _fpsSelector.selectedSegmentIndex = [self selectedIndexForFrameRate:self.profile.fps];
    [self addControl:_fpsSelector];

    [self addSectionTitle:@"Bitrate"];
    _bitrateLabel = [self detailLabel:@""];
    [self addControl:_bitrateLabel];
    _bitrateSlider = [[UISlider alloc] init];
    _bitrateSlider.minimumValue = 500.0;
    _bitrateSlider.maximumValue = 30000.0;
    _bitrateSlider.value = MAX(_bitrateSlider.minimumValue, MIN(_bitrateSlider.maximumValue, self.profile.bitrate));
    [_bitrateSlider addTarget:self action:@selector(bitrateChanged:) forControlEvents:UIControlEventValueChanged];
    [self addControl:_bitrateSlider];
    [self updateBitrateLabel];

    [self addSectionTitle:@"Audio"];
    _audioSelector = [[UISegmentedControl alloc] initWithItems:@[@"Off", @"Host", @"Stream"]];
    _audioSelector.selectedSegmentIndex = MIN(self.profile.audioPolicy, 2);
    [self addControl:_audioSelector];

    [self addSectionTitle:@"Input Mode"];
    _inputModeSelector = [[UISegmentedControl alloc] initWithItems:@[@"Touch", @"Mouse", @"Hybrid"]];
    _inputModeSelector.selectedSegmentIndex = self.profile.inputMode;
    [self addControl:_inputModeSelector];

    [self addSectionTitle:@"Gestures"];
    _gestureSelector = [[UISegmentedControl alloc] initWithItems:@[@"Native gestures", @"Compatibility gestures"]];
    _gestureSelector.selectedSegmentIndex = self.profile.inputMode == LMInputModeHybrid ? 1 : 0;
    [_gestureSelector addTarget:self action:@selector(gestureChanged:) forControlEvents:UIControlEventValueChanged];
    [self addControl:_gestureSelector];
    [self addControl:[self detailLabel:@"Native touch uses long press and two-finger scrolling. Compatibility gestures use mouse semantics."]];

    [self addSectionTitle:@"Reconnect"];
    _reconnectSwitch = [[UISwitch alloc] init];
    _reconnectSwitch.on = self.profile.reconnectEnabled;
    [self addControl:_reconnectSwitch];

    [self addSectionTitle:@"Diagnostics"];
    _diagnosticsSwitch = [[UISwitch alloc] init];
    _diagnosticsSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"Moonlight.SecondMonitor.Diagnostics"];
    [self addControl:_diagnosticsSwitch];
    [self addControl:[self detailLabel:@"Diagnostics are shown from the existing stream statistics when requested."]];
}

- (void)cancelSettings:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (LMStreamProfile *)profileFromControls {
    LMStreamProfile *profile = [self.profile copy];
    profile.mode = LMStreamModeSecondMonitor;
    profile.resolution = _supportedResolutions[_resolutionSelector.selectedSegmentIndex].CGSizeValue;
    profile.fps = _supportedFrameRates[_fpsSelector.selectedSegmentIndex].integerValue;
    profile.bitrate = (NSInteger)roundf(_bitrateSlider.value / 500.0) * 500;
    profile.audioPolicy = (LMAudioPolicy)_audioSelector.selectedSegmentIndex;
    profile.inputMode = (LMInputMode)_inputModeSelector.selectedSegmentIndex;
    profile.reconnectEnabled = _reconnectSwitch.isOn;
    profile.codec = LMStreamCodecH264;
    profile.hdrEnabled = NO;
    profile.experimental1080pEnabled = profile.resolution.width == 1920 && profile.resolution.height == 1080;
    return profile;
}

- (void)saveSettings:(id)sender {
    LMStreamProfile *profile = [self profileFromControls];
    NSError *error = nil;
    if (![profile validateForCapabilityProfile:_capabilityProfile error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invalid Profile"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (self.completion != nil) {
        self.completion(profile, _modeSelector.selectedSegmentIndex == 1, _diagnosticsSwitch.isOn);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation SettingsViewController {
    NSInteger _bitrate;
    NSInteger _lastSelectedResolutionIndex;
    BOOL _secondMonitorProfileMode;
    LMStreamProfile *_editingSecondMonitorProfile;
}

@dynamic overrideUserInterfaceStyle;

static NSString* bitrateFormat = @"Bitrate: %.1f Mbps";
static const int bitrateTable[] = {
    500,
    1000,
    1500,
    2000,
    2500,
    3000,
    4000,
    5000,
    6000,
    7000,
    8000,
    9000,
    10000,
    12000,
    15000,
    18000,
    20000,
    30000,
    40000,
    50000,
    60000,
    70000,
    80000,
    100000,
    120000,
    150000,
};

const int RESOLUTION_TABLE_SIZE = 7;
const int RESOLUTION_TABLE_CUSTOM_INDEX = RESOLUTION_TABLE_SIZE - 1;
CGSize resolutionTable[RESOLUTION_TABLE_SIZE];

-(int)getSliderValueForBitrate:(NSInteger)bitrate {
    int i;
    
    for (i = 0; i < (sizeof(bitrateTable) / sizeof(*bitrateTable)); i++) {
        if (bitrate <= bitrateTable[i]) {
            return i;
        }
    }
    
    // Return the last entry in the table
    return i - 1;
}

// This view is rooted at a ScrollView. To make it scrollable,
// we'll update content size here.
-(void)viewDidLayoutSubviews {
    CGFloat highestViewY = 0;
    
    // Enumerate the scroll view's subviews looking for the
    // highest view Y value to set our scroll view's content
    // size.
    for (UIView* view in self.scrollView.subviews) {
        // UIScrollViews have 2 default child views
        // which represent the horizontal and vertical scrolling
        // indicators. Ignore any views we don't recognize.
        if (![view isKindOfClass:[UILabel class]] &&
            ![view isKindOfClass:[UISegmentedControl class]] &&
            ![view isKindOfClass:[UISlider class]]) {
            continue;
        }
        
        CGFloat currentViewY = view.frame.origin.y + view.frame.size.height;
        if (currentViewY > highestViewY) {
            highestViewY = currentViewY;
        }
    }
    
    // Add a bit of padding so the view doesn't end right at the button of the display
    self.scrollView.contentSize = CGSizeMake(self.scrollView.contentSize.width,
                                             highestViewY + 20);
}

// Adjust the subviews for the safe area on the iPhone X.
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    
    if (@available(iOS 11.0, *)) {
        for (UIView* view in self.view.subviews) {
            // HACK: The official safe area is much too large for our purposes
            // so we'll just use the presence of any safe area to indicate we should
            // pad by 20.
            if (self.view.safeAreaInsets.left >= 20 || self.view.safeAreaInsets.right >= 20) {
                view.frame = CGRectMake(view.frame.origin.x + 20, view.frame.origin.y, view.frame.size.width, view.frame.size.height);
            }
        }
    }
}

BOOL isCustomResolution(CGSize res) {
    if (res.width == 0 && res.height == 0) {
        return NO;
    }
    
    for (int i = 0; i < RESOLUTION_TABLE_CUSTOM_INDEX; i++) {
        if (res.width == resolutionTable[i].width && res.height == resolutionTable[i].height) {
            return NO;
        }
    }
    
    return YES;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Always run settings in dark mode because we want the light fonts
    if (@available(iOS 13.0, tvOS 13.0, *)) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    }
    
    DataManager* dataMan = [[DataManager alloc] init];
    TemporarySettings* currentSettings = [dataMan getSettings];
    if (!dataMan.isAvailable || currentSettings == nil) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Settings Unavailable"
                                                                           message:dataMan.storeError.localizedDescription ?: @"Moonlight could not open its settings store."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSString *hostUuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"Moonlight.SecondMonitor.HostUUID"];
    _secondMonitorProfileMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"Moonlight.SecondMonitor.SettingsMode"];
    _editingSecondMonitorProfile = _secondMonitorProfileMode && hostUuid.length != 0 ? [dataMan getSecondMonitorProfileForHost:hostUuid] : nil;
    if (_secondMonitorProfileMode && _editingSecondMonitorProfile == nil) {
        _editingSecondMonitorProfile = [LMStreamProfile defaultSecondMonitorProfile];
    }

    // Task 7 owns the profile picker. When that picker opens this controller
    // for a second-monitor profile, remove values the iPad Air cannot use.
    if (_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
        [self.codecSelector removeAllSegments];
        [self.codecSelector insertSegmentWithTitle:@"H.264" atIndex:0 animated:NO];
        [self.codecSelector setSelectedSegmentIndex:0];
        [self.framerateSelector removeAllSegments];
        [self.framerateSelector insertSegmentWithTitle:@"30 FPS" atIndex:0 animated:NO];
        [self.framerateSelector setSelectedSegmentIndex:0];
        [self.hdrSelector removeAllSegments];
        [self.hdrSelector insertSegmentWithTitle:@"Unsupported on this device" atIndex:0 animated:NO];
        [self.hdrSelector setSelectedSegmentIndex:0];
        [self.hdrSelector setEnabled:NO];
    }
    
    // Ensure we pick a bitrate that falls exactly onto a slider notch.
    NSInteger initialBitrate = _editingSecondMonitorProfile != nil ? _editingSecondMonitorProfile.bitrate : [currentSettings.bitrate intValue];
    _bitrate = bitrateTable[[self getSliderValueForBitrate:initialBitrate]];

    // Get the size of the screen with and without safe area insets
    UIWindow *window = UIApplication.sharedApplication.windows.firstObject;
    CGFloat screenScale = window.screen.scale;
    CGFloat safeAreaWidth = (window.frame.size.width - window.safeAreaInsets.left - window.safeAreaInsets.right) * screenScale;
    CGFloat fullScreenWidth = window.frame.size.width * screenScale;
    CGFloat fullScreenHeight = window.frame.size.height * screenScale;
    
    self.resolutionDisplayView.layer.cornerRadius = 10;
    self.resolutionDisplayView.clipsToBounds = YES;
    UITapGestureRecognizer *resolutionDisplayViewTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resolutionDisplayViewTapped:)];
    [self.resolutionDisplayView addGestureRecognizer:resolutionDisplayViewTap];
    
    resolutionTable[0] = CGSizeMake(640, 360);
    resolutionTable[1] = CGSizeMake(1280, 720);
    resolutionTable[2] = CGSizeMake(1920, 1080);
    resolutionTable[3] = CGSizeMake(3840, 2160);
    resolutionTable[4] = CGSizeMake(safeAreaWidth, fullScreenHeight);
    resolutionTable[5] = CGSizeMake(fullScreenWidth, fullScreenHeight);
    resolutionTable[6] = CGSizeMake([currentSettings.width integerValue], [currentSettings.height integerValue]); // custom initial value
    
    // Don't populate the custom entry unless we have a custom resolution
    if (!isCustomResolution(resolutionTable[6])) {
        resolutionTable[6] = CGSizeMake(0, 0);
    }

    if (_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
        // The second segment is the explicit opt-in control for experimental
        // 1080p30. It is not part of the default supported resolution set.
        [self.resolutionSelector removeAllSegments];
        [self.resolutionSelector insertSegmentWithTitle:@"1280 x 720" atIndex:0 animated:NO];
        [self.resolutionSelector insertSegmentWithTitle:@"1920 x 1080 (Experimental)" atIndex:1 animated:NO];
    }
    
    NSInteger framerate;
    NSInteger initialFrameRate = _editingSecondMonitorProfile != nil ? _editingSecondMonitorProfile.fps : [currentSettings.framerate integerValue];
    switch (initialFrameRate) {
        case 30:
            framerate = 0;
            break;
        default:
        case 60:
            framerate = 1;
            break;
        case 120:
            framerate = 2;
            break;
    }
    if (_secondMonitorProfileMode) {
        framerate = 0;
    }

    CGSize initialResolution = _editingSecondMonitorProfile != nil ? _editingSecondMonitorProfile.resolution : CGSizeMake([currentSettings.width integerValue], [currentSettings.height integerValue]);
    NSInteger resolution = 1;
    if (_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
        resolution = initialResolution.width == 1920 && initialResolution.height == 1080 ? 1 : 0;
    }
    if (!(_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir)) {
        for (int i = 0; i < RESOLUTION_TABLE_SIZE; i++) {
            if ((int) resolutionTable[i].height == (int)initialResolution.height
                && (int) resolutionTable[i].width == (int)initialResolution.width) {
                resolution = i;
                break;
            }
        }
    }

    // Only show the 120 FPS option if we have a > 60-ish Hz display
    bool enable120Fps = false;
    if (@available(iOS 10.3, tvOS 10.3, *)) {
        if ([UIScreen mainScreen].maximumFramesPerSecond > 62) {
            enable120Fps = true;
        }
    }
    if (!enable120Fps && !_secondMonitorProfileMode) {
        [self.framerateSelector removeSegmentAtIndex:2 animated:NO];
    }

    // Disable codec selector segments for unsupported codecs
    if (!_secondMonitorProfileMode) {
#if defined(__IPHONE_16_0) || defined(__TVOS_16_0)
    if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1))
#endif
    {
        [self.codecSelector removeSegmentAtIndex:2 animated:NO];
    }
    if (!VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
        [self.codecSelector removeSegmentAtIndex:1 animated:NO];

        // Only enable the 4K option for "recent" devices. We'll judge that by whether
        // they support HEVC decoding (A9 or later).
        [self.resolutionSelector setEnabled:NO forSegmentAtIndex:3];
    }
    switch (currentSettings.preferredCodec) {
        case CODEC_PREF_AUTO:
            [self.codecSelector setSelectedSegmentIndex:self.codecSelector.numberOfSegments - 1];
            break;
            
        case CODEC_PREF_AV1:
            [self.codecSelector setSelectedSegmentIndex:2];
            break;
            
        case CODEC_PREF_HEVC:
            [self.codecSelector setSelectedSegmentIndex:1];
            break;
            
        case CODEC_PREF_H264:
            [self.codecSelector setSelectedSegmentIndex:0];
            break;
    }
    }
    
    if (!_secondMonitorProfileMode && (!VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) || !(AVPlayer.availableHDRModes & AVPlayerHDRModeHDR10))) {
        [self.hdrSelector removeAllSegments];
        [self.hdrSelector insertSegmentWithTitle:@"Unsupported on this device" atIndex:0 animated:NO];
        [self.hdrSelector setEnabled:NO];
    }
    else if (!_secondMonitorProfileMode) {
        [self.hdrSelector setSelectedSegmentIndex:currentSettings.enableHdr ? 1 : 0];
    }
    
    [self.touchModeSelector setSelectedSegmentIndex:currentSettings.absoluteTouchMode ? 1 : 0];
    [self.touchModeSelector addTarget:self action:@selector(touchModeChanged) forControlEvents:UIControlEventValueChanged];
    [self.statsOverlaySelector setSelectedSegmentIndex:currentSettings.statsOverlay ? 1 : 0];
    [self.btMouseSelector setSelectedSegmentIndex:currentSettings.btMouseSupport ? 1 : 0];
    [self.optimizeSettingsSelector setSelectedSegmentIndex:currentSettings.optimizeGames ? 1 : 0];
    [self.framePacingSelector setSelectedSegmentIndex:currentSettings.useFramePacing ? 1 : 0];
    [self.multiControllerSelector setSelectedSegmentIndex:currentSettings.multiController ? 1 : 0];
    [self.swapABXYButtonsSelector setSelectedSegmentIndex:currentSettings.swapABXYButtons ? 1 : 0];
    [self.audioOnPCSelector setSelectedSegmentIndex:currentSettings.playAudioOnPC ? 1 : 0];
    NSInteger onscreenControls = [currentSettings.onscreenControls integerValue];
    _lastSelectedResolutionIndex = resolution;
    [self.resolutionSelector setSelectedSegmentIndex:resolution];
    [self.resolutionSelector addTarget:self action:@selector(newResolutionChosen) forControlEvents:UIControlEventValueChanged];
    [self.framerateSelector setSelectedSegmentIndex:framerate];
    [self.framerateSelector addTarget:self action:@selector(updateBitrate) forControlEvents:UIControlEventValueChanged];
    [self.onscreenControlSelector setSelectedSegmentIndex:onscreenControls];
    [self.onscreenControlSelector setEnabled:!currentSettings.absoluteTouchMode];
    [self.bitrateSlider setMinimumValue:0];
    [self.bitrateSlider setMaximumValue:(sizeof(bitrateTable) / sizeof(*bitrateTable)) - 1];
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:YES];
    [self.bitrateSlider addTarget:self action:@selector(bitrateSliderMoved) forControlEvents:UIControlEventValueChanged];
    [self updateBitrateText];
    [self updateResolutionDisplayViewText];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UIButton *desktopSettingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [desktopSettingsButton setTitle:@"Desktop" forState:UIControlStateNormal];
        [desktopSettingsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        desktopSettingsButton.titleLabel.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        desktopSettingsButton.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        desktopSettingsButton.layer.cornerRadius = 8.0;
        desktopSettingsButton.translatesAutoresizingMaskIntoConstraints = NO;
        [desktopSettingsButton addTarget:self action:@selector(showSecondMonitorSettings:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:desktopSettingsButton];
        [NSLayoutConstraint activateConstraints:@[
            [desktopSettingsButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16.0],
            [desktopSettingsButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8.0],
            [desktopSettingsButton.widthAnchor constraintEqualToConstant:150.0],
            [desktopSettingsButton.heightAnchor constraintEqualToConstant:44.0],
        ]];
    }
}

- (void)showSecondMonitorSettings:(id)sender {
    DataManager *dataMan = [[DataManager alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *hostUUID = [defaults stringForKey:@"Moonlight.SecondMonitor.HostUUID"];
    if (hostUUID.length == 0) {
        TemporaryHost *firstHost = [dataMan.getHosts firstObject];
        hostUUID = firstHost.uuid;
        if (hostUUID.length != 0) {
            [defaults setObject:hostUUID forKey:@"Moonlight.SecondMonitor.HostUUID"];
        }
    }

    LMStreamProfile *profile = hostUUID.length != 0 ? [dataMan getSecondMonitorProfileForHost:hostUUID] : nil;
    LMSecondMonitorSettingsViewController *panel = [[LMSecondMonitorSettingsViewController alloc] init];
    panel.hostUUID = hostUUID;
    panel.profile = profile ?: [LMStreamProfile defaultSecondMonitorProfile];
    panel.active = [defaults boolForKey:@"Moonlight.SecondMonitor.Active"];
    panel.modalPresentationStyle = UIModalPresentationFormSheet;
    __weak SettingsViewController *weakSelf = self;
    panel.completion = ^(LMStreamProfile *updatedProfile, BOOL active, BOOL diagnostics) {
        SettingsViewController *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        if (updatedProfile != nil && hostUUID.length != 0) {
            [dataMan saveSecondMonitorProfile:updatedProfile forHost:hostUUID];
        }
        [defaults setBool:active forKey:@"Moonlight.SecondMonitor.Active"];
        [defaults setBool:diagnostics forKey:@"Moonlight.SecondMonitor.Diagnostics"];
    };
    [self presentViewController:panel animated:YES completion:nil];
}

- (void) touchModeChanged {
    // Disable on-screen controls in absolute touch mode
    [self.onscreenControlSelector setEnabled:[self.touchModeSelector selectedSegmentIndex] == 0];
}

- (void) updateBitrate {
    NSInteger fps = [self getChosenFrameRate];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger defaultBitrate;
    
    // This logic is shamelessly stolen from Moonlight Qt:
    // https://github.com/moonlight-stream/moonlight-qt/blob/master/app/settings/streamingpreferences.cpp
    
    // Don't scale bitrate linearly beyond 60 FPS. It's definitely not a linear
    // bitrate increase for frame rate once we get to values that high.
    float frameRateFactor = (fps <= 60 ? fps : (sqrtf(fps / 60.f) * 60.f)) / 30.f;

    // TODO: Collect some empirical data to see if these defaults make sense.
    // We're just using the values that the Shield used, as we have for years.
    struct {
        NSInteger pixels;
        int factor;
    } resTable[] = {
        { 640 * 360, 1 },
        { 854 * 480, 2 },
        { 1280 * 720, 5 },
        { 1920 * 1080, 10 },
        { 2560 * 1440, 20 },
        { 3840 * 2160, 40 },
        { -1, -1 }
    };

    // Calculate the resolution factor by linear interpolation of the resolution table
    float resolutionFactor;
    NSInteger pixels = width * height;
    for (int i = 0;; i++) {
        if (pixels == resTable[i].pixels) {
            // We can bail immediately for exact matches
            resolutionFactor = resTable[i].factor;
            break;
        }
        else if (pixels < resTable[i].pixels) {
            if (i == 0) {
                // Never go below the lowest resolution entry
                resolutionFactor = resTable[i].factor;
            }
            else {
                // Interpolate between the entry greater than the chosen resolution (i) and the entry less than the chosen resolution (i-1)
                resolutionFactor = ((float)(pixels - resTable[i-1].pixels) / (resTable[i].pixels - resTable[i-1].pixels)) * (resTable[i].factor - resTable[i-1].factor) + resTable[i-1].factor;
            }
            break;
        }
        else if (resTable[i].pixels == -1) {
            // Never go above the highest resolution entry
            resolutionFactor = resTable[i-1].factor;
            break;
        }
    }

    defaultBitrate = round(resolutionFactor * frameRateFactor) * 1000;
    _bitrate = MIN(defaultBitrate, 100000);
    [self.bitrateSlider setValue:[self getSliderValueForBitrate:_bitrate] animated:YES];
    
    [self updateBitrateText];
}

- (void) newResolutionChosen {
    if (_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        _lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
        return;
    }

    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        [self promptCustomResolutionDialog];
    }
    else {
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        _lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
    }
}

- (void) promptCustomResolutionDialog {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Enter Custom Resolution" message:nil preferredStyle:UIAlertControllerStyleAlert];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Width";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width];
        }
    }];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Video Height";
        textField.clearButtonMode = UITextFieldViewModeAlways;
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
        if (resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height == 0) {
            textField.text = @"";
        }
        else {
            textField.text = [NSString stringWithFormat:@"%d", (int) resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height];
        }
    }];

    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSArray * textfields = alertController.textFields;
        UITextField *widthField = textfields[0];
        UITextField *heightField = textfields[1];
        
        long width = [widthField.text integerValue];
        long height = [heightField.text integerValue];
        if (width <= 0 || height <= 0) {
            // Restore the previous selection
            [self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];
            return;
        }
        
        // H.264 maximum
        int maxResolutionDimension = 4096;
        if (@available(iOS 11.0, tvOS 11.0, *)) {
            if (VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)) {
                // HEVC maximum
                maxResolutionDimension = 8192;
            }
        }
        
        // Cap to maximum valid dimensions
        width = MIN(width, maxResolutionDimension);
        height = MIN(height, maxResolutionDimension);
        
        // Cap to minimum valid dimensions
        width = MAX(width, 256);
        height = MAX(height, 256);

        resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX] = CGSizeMake(width, height);
        [self updateBitrate];
        [self updateResolutionDisplayViewText];
        self->_lastSelectedResolutionIndex = [self.resolutionSelector selectedSegmentIndex];
        
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Custom Resolution Selected" message: @"Custom resolutions are not officially supported by GeForce Experience, so it will not set your host display resolution. You will need to set it manually while in game.\n\nResolutions that are not supported by your client or host PC may cause streaming errors." preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alertController animated:YES completion:nil];
    }]];

    [alertController addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        // Restore the previous selection
        [self.resolutionSelector setSelectedSegmentIndex:self->_lastSelectedResolutionIndex];
    }]];

    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)resolutionDisplayViewTapped:(UITapGestureRecognizer *)sender {
    NSURL *url = [NSURL URLWithString:@"https://moonlight-stream.org/custom-resolution"];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }
}

- (void) updateResolutionDisplayViewText {
    NSInteger width = [self getChosenStreamWidth];
    NSInteger height = [self getChosenStreamHeight];
    CGFloat viewFrameWidth = self.resolutionDisplayView.frame.size.width;
    CGFloat viewFrameHeight = self.resolutionDisplayView.frame.size.height;
    CGFloat padding = 10;
    CGFloat fontSize = [UIFont smallSystemFontSize];
    
    for (UIView *subview in self.resolutionDisplayView.subviews) {
        [subview removeFromSuperview];
    }
    UILabel *label1 = [[UILabel alloc] init];
    label1.text = @"Set PC/Game resolution: ";
    label1.font = [UIFont systemFontOfSize:fontSize];
    [label1 sizeToFit];
    label1.frame = CGRectMake(padding, (viewFrameHeight - label1.frame.size.height) / 2, label1.frame.size.width, label1.frame.size.height);

    UILabel *label2 = [[UILabel alloc] init];
    label2.text = [NSString stringWithFormat:@"%ld x %ld", (long)width, (long)height];
    [label2 sizeToFit];
    label2.frame = CGRectMake(viewFrameWidth - label2.frame.size.width - padding, (viewFrameHeight - label2.frame.size.height) / 2, label2.frame.size.width, label2.frame.size.height);

    [self.resolutionDisplayView addSubview:label1];
    [self.resolutionDisplayView addSubview:label2];
}

- (void) bitrateSliderMoved {
    assert(self.bitrateSlider.value < (sizeof(bitrateTable) / sizeof(*bitrateTable)));
    _bitrate = bitrateTable[(int)self.bitrateSlider.value];
    [self updateBitrateText];
}

- (void) updateBitrateText {
    // Display bitrate in Mbps
    [self.bitrateLabel setText:[NSString stringWithFormat:bitrateFormat, _bitrate / 1000.]];
}

- (NSInteger) getChosenFrameRate {
    switch ([self.framerateSelector selectedSegmentIndex]) {
        case 0:
            return 30;
        case 1:
            return 60;
        case 2:
            return 120;
        default:
            return 30;
    }
}

- (uint32_t) getChosenCodecPreference {
    // Auto is always the last segment
    if (self.codecSelector.selectedSegmentIndex == self.codecSelector.numberOfSegments - 1) {
        return CODEC_PREF_AUTO;
    }
    else {
        switch (self.codecSelector.selectedSegmentIndex) {
            case 0:
                return CODEC_PREF_H264;
                
            case 1:
                return CODEC_PREF_HEVC;
                
            case 2:
                return CODEC_PREF_AV1;
                
            default:
                return CODEC_PREF_H264;
        }
    }
}

- (NSInteger) getChosenStreamHeight {
    if (_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
        return self.resolutionSelector.selectedSegmentIndex == 1 ? 1080 : 720;
    }

    // because the 4k resolution can be removed
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        return resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].height;
    }

    return resolutionTable[[self.resolutionSelector selectedSegmentIndex]].height;
}

- (NSInteger) getChosenStreamWidth {
    if (_secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
        return self.resolutionSelector.selectedSegmentIndex == 1 ? 1920 : 1280;
    }

    // because the 4k resolution can be removed
    BOOL lastSegmentSelected = [self.resolutionSelector selectedSegmentIndex] + 1 == [self.resolutionSelector numberOfSegments];
    if (lastSegmentSelected) {
        return resolutionTable[RESOLUTION_TABLE_CUSTOM_INDEX].width;
    }

    return resolutionTable[[self.resolutionSelector selectedSegmentIndex]].width;
}

- (void) saveSettings {
    DataManager* dataMan = [[DataManager alloc] init];
    NSInteger framerate = [self getChosenFrameRate];
    NSInteger height = [self getChosenStreamHeight];
    NSInteger width = [self getChosenStreamWidth];
    NSInteger onscreenControls = [self.onscreenControlSelector selectedSegmentIndex];
    BOOL optimizeGames = [self.optimizeSettingsSelector selectedSegmentIndex] == 1;
    BOOL multiController = [self.multiControllerSelector selectedSegmentIndex] == 1;
    BOOL swapABXYButtons = [self.swapABXYButtonsSelector selectedSegmentIndex] == 1;
    BOOL audioOnPC = [self.audioOnPCSelector selectedSegmentIndex] == 1;
    uint32_t preferredCodec = [self getChosenCodecPreference];
    BOOL btMouseSupport = [self.btMouseSelector selectedSegmentIndex] == 1;
    BOOL useFramePacing = [self.framePacingSelector selectedSegmentIndex] == 1;
    BOOL absoluteTouchMode = [self.touchModeSelector selectedSegmentIndex] == 1;
    BOOL statsOverlay = [self.statsOverlaySelector selectedSegmentIndex] == 1;
    BOOL enableHdr = [self.hdrSelector selectedSegmentIndex] == 1;

    if (_secondMonitorProfileMode) {
        LMStreamProfile *profile = [_editingSecondMonitorProfile copy] ?: [LMStreamProfile defaultSecondMonitorProfile];
        profile.resolution = CGSizeMake(width, height);
        profile.fps = framerate;
        profile.bitrate = _bitrate;
        profile.codec = _secondMonitorProfileMode && [LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir ? LMStreamCodecH264 :
            (preferredCodec == CODEC_PREF_H264 ? LMStreamCodecH264 :
            (preferredCodec == CODEC_PREF_HEVC ? LMStreamCodecHEVC : LMStreamCodecAV1));
        profile.hdrEnabled = enableHdr;
        if ([LMStreamProfile currentDeviceCapabilityProfile] == LMDeviceCapabilityProfileIPadAir) {
            profile.experimental1080pEnabled = self.resolutionSelector.selectedSegmentIndex == 1;
        }
        NSError *profileError = nil;
        if (![profile validateForCapabilityProfile:[LMStreamProfile currentDeviceCapabilityProfile] error:&profileError]) {
            Log(LOG_W, @"Rejected second-monitor profile settings: %@", profileError.localizedDescription);
            return;
        }
        NSString *hostUuid = [[NSUserDefaults standardUserDefaults] stringForKey:@"Moonlight.SecondMonitor.HostUUID"];
        if (hostUuid.length != 0) {
            [dataMan saveSecondMonitorProfile:profile forHost:hostUuid];
        }
        else {
            Log(LOG_W, @"Second-monitor profile was not saved because no host is selected.");
        }
        return;
    }

    [dataMan saveSettingsWithBitrate:_bitrate
                           framerate:framerate
                              height:height
                               width:width
                         audioConfig:2 // Stereo
                    onscreenControls:onscreenControls
                       optimizeGames:optimizeGames
                     multiController:multiController
                     swapABXYButtons:swapABXYButtons
                           audioOnPC:audioOnPC
                      preferredCodec:preferredCodec
                      useFramePacing:useFramePacing
                           enableHdr:enableHdr
                      btMouseSupport:btMouseSupport
                   absoluteTouchMode:absoluteTouchMode
                        statsOverlay:statsOverlay];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
}


@end
