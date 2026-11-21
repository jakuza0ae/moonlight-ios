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
#import "HttpManager.h"
#import "ServerInfoResponse.h"
#import "../Stream/StreamConfiguration.h"

#import <VideoToolbox/VideoToolbox.h>
#import <AVFoundation/AVFoundation.h>

@interface LMSecondMonitorSettingsViewController : UIViewController
@property (nonatomic, copy) NSString *selectedHostUUID;
@property (nonatomic, copy) NSArray *hosts;
@property (nonatomic, copy) LMStreamProfile *profile;
@property (nonatomic, copy) NSString *allAppsHostUUID;
@property (nonatomic, copy) LMSecondMonitorSettingsCompletion completion;
@end

@implementation LMSecondMonitorSettingsViewController {
    UIScrollView *_settingsScrollView;
    UIStackView *_settingsStack;
    UIStackView *_settingsGroup;
    UILabel *_streamSummary;
    UIButton *_hostButton;
    UIButton *_checkLinkButton;
    BOOL _checkingLink;
    UISegmentedControl *_modeSelector;
    UISegmentedControl *_resolutionSelector;
    UISwitch *_experimental1080Switch;
    UISegmentedControl *_fpsSelector;
    UISlider *_bitrateSlider;
    UILabel *_bitrateLabel;
    UISegmentedControl *_audioSelector;
    UISegmentedControl *_inputModeSelector;
    UISwitch *_reconnectSwitch;
    UISwitch *_framePacingSwitch;
    UISwitch *_diagnosticsSwitch;
    NSArray<NSValue *> *_supportedResolutions;
    NSArray<NSNumber *> *_supportedFrameRates;
    LMDeviceCapabilityProfile _capabilityProfile;
}

static UIColor *SDAccent(void) {
    return [UIColor colorWithRed:0.75 green:0.93 blue:0.79 alpha:1];
}

- (UILabel *)sectionTitle:(NSString *)title {
    UILabel *label = [[UILabel alloc] init];
    label.text = title;
    label.textColor = [UIColor colorWithWhite:0.95 alpha:1];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    label.accessibilityTraits = UIAccessibilityTraitHeader;
    return label;
}

- (UILabel *)detailLabel:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor colorWithWhite:0.73 alpha:1];
    label.numberOfLines = 0;
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (void)addSectionTitle:(NSString *)title {
    UIView *surface = [[UIView alloc] init];
    surface.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    surface.layer.cornerRadius = 12;
    surface.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
    surface.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    [_settingsStack addArrangedSubview:surface];

    _settingsGroup = [[UIStackView alloc] init];
    _settingsGroup.translatesAutoresizingMaskIntoConstraints = NO;
    _settingsGroup.axis = UILayoutConstraintAxisVertical;
    _settingsGroup.spacing = 12;
    [surface addSubview:_settingsGroup];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsGroup.leadingAnchor constraintEqualToAnchor:surface.leadingAnchor constant:16],
        [_settingsGroup.trailingAnchor constraintEqualToAnchor:surface.trailingAnchor constant:-16],
        [_settingsGroup.topAnchor constraintEqualToAnchor:surface.topAnchor constant:16],
        [_settingsGroup.bottomAnchor constraintEqualToAnchor:surface.bottomAnchor constant:-16],
    ]];
    [_settingsGroup addArrangedSubview:[self sectionTitle:title]];
}

- (void)styleSegments:(UISegmentedControl *)segments {
    segments.tintColor = SDAccent();
    NSDictionary *normal = @{NSForegroundColorAttributeName: UIColor.whiteColor};
    NSDictionary *selected = @{NSForegroundColorAttributeName: UIColor.blackColor};
    [segments setTitleTextAttributes:normal forState:UIControlStateNormal];
    [segments setTitleTextAttributes:selected forState:UIControlStateSelected];
    if (@available(iOS 13.0, *)) {
        segments.selectedSegmentTintColor = SDAccent();
    }
    [segments.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
}

- (void)addControl:(UIView *)control {
    control.translatesAutoresizingMaskIntoConstraints = NO;
    if ([control isKindOfClass:[UISegmentedControl class]]) {
        [self styleSegments:(UISegmentedControl *)control];
    }
    [_settingsGroup addArrangedSubview:control];
}

- (void)addSwitch:(UISwitch *)control title:(NSString *)title {
    UILabel *label = [self detailLabel:title];
    label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    control.accessibilityLabel = title;
    control.onTintColor = [UIColor colorWithRed:0.30 green:0.58 blue:0.40 alpha:1];
    label.isAccessibilityElement = NO;
    [control setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[label, control]];
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [self addControl:row];
}

- (TemporaryHost *)hostWithUUID:(NSString *)hostUUID {
    for (TemporaryHost *host in self.hosts) {
        if ([host.uuid isEqualToString:hostUUID]) {
            return host;
        }
    }
    return nil;
}

- (void)updateHostButtonTitle {
    TemporaryHost *host = [self hostWithUUID:self.selectedHostUUID];
    NSString *title = host.name ?: @"Choose computer";
    [_hostButton setTitle:title forState:UIControlStateNormal];
    _checkLinkButton.enabled = host != nil && !_checkingLink;
}

- (void)loadProfileForSelectedHost {
    if (self.selectedHostUUID.length == 0) {
        self.profile = [LMStreamProfile defaultSecondMonitorProfile];
    }
    else {
        self.profile = [LMStreamProfileStore loadProfileForHost:self.selectedHostUUID profileName:@"second-monitor"] ?: [LMStreamProfile defaultSecondMonitorProfile];
    }

    _modeSelector.selectedSegmentIndex = [self.allAppsHostUUID isEqualToString:self.selectedHostUUID] ? 1 : 0;
    _fpsSelector.selectedSegmentIndex = [self selectedIndexForFrameRate:self.profile.fps];
    _audioSelector.selectedSegmentIndex = MIN(self.profile.audioPolicy, 2);
    _inputModeSelector.selectedSegmentIndex = self.profile.inputMode;
    _reconnectSwitch.on = self.profile.reconnectEnabled;
    _framePacingSwitch.on = self.profile.framePacing;
    _bitrateSlider.value = MAX(_bitrateSlider.minimumValue, MIN(_bitrateSlider.maximumValue, self.profile.bitrate));
    [self updateBitrateLabel];
    if (_experimental1080Switch != nil) {
        _experimental1080Switch.on = self.profile.experimental1080pEnabled;
    }
    [self rebuildResolutionSelector];
}

- (void)rebuildResolutionSelector {
    BOOL experimental1080pEnabled = _experimental1080Switch == nil || _experimental1080Switch.isOn;
    _supportedResolutions = [LMStreamProfile supportedResolutionsForCapabilityProfile:_capabilityProfile
                                                               experimental1080pEnabled:experimental1080pEnabled];

    NSMutableArray<NSString *> *resolutionTitles = [NSMutableArray array];
    for (NSValue *value in _supportedResolutions) {
        CGSize resolution = value.CGSizeValue;
        [resolutionTitles addObject:[NSString stringWithFormat:@"%ld×%ld", (long)resolution.width, (long)resolution.height]];
    }

    UISegmentedControl *oldSelector = _resolutionSelector;
    UIStackView *group = oldSelector == nil ? _settingsGroup : (UIStackView *)oldSelector.superview;
    NSUInteger oldIndex = oldSelector == nil ? NSNotFound : [group.arrangedSubviews indexOfObject:oldSelector];
    _resolutionSelector = [[UISegmentedControl alloc] initWithItems:resolutionTitles];
    NSInteger selectedIndex = [self selectedIndexForResolution:self.profile.resolution];
    _resolutionSelector.selectedSegmentIndex = selectedIndex;
    _resolutionSelector.accessibilityLabel = @"Resolution";
    [_resolutionSelector addTarget:self action:@selector(resolutionChanged:) forControlEvents:UIControlEventValueChanged];
    if (oldSelector != nil && oldIndex != NSNotFound) {
        [group removeArrangedSubview:oldSelector];
        [oldSelector removeFromSuperview];
        _resolutionSelector.translatesAutoresizingMaskIntoConstraints = NO;
        [self styleSegments:_resolutionSelector];
        [group insertArrangedSubview:_resolutionSelector atIndex:oldIndex];
    }
    else {
        [self addControl:_resolutionSelector];
    }
    [self updateFrameRateAvailability];
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

- (void)updateStreamSummary {
    NSInteger mode = _resolutionSelector.selectedSegmentIndex;
    NSInteger rate = _fpsSelector.selectedSegmentIndex;
    if (mode < 0 || mode >= (NSInteger)_supportedResolutions.count ||
        rate < 0 || rate >= (NSInteger)_supportedFrameRates.count) {
        return;
    }
    CGSize size = _supportedResolutions[mode].CGSizeValue;
    _streamSummary.text = [NSString stringWithFormat:@"%ld × %ld  ·  %@ FPS  ·  H.264",
                           (long)size.width, (long)size.height, _supportedFrameRates[rate]];
}

- (void)updateFrameRateAvailability {
    NSInteger resolutionIndex = _resolutionSelector.selectedSegmentIndex;
    if (_fpsSelector == nil || resolutionIndex < 0 || resolutionIndex >= (NSInteger)_supportedResolutions.count) {
        return;
    }
    CGSize resolution = _supportedResolutions[resolutionIndex].CGSizeValue;
    BOOL allow60FPS = _capabilityProfile != LMDeviceCapabilityProfileIPadAir ||
                      !CGSizeEqualToSize(resolution, CGSizeMake(1920, 1080));
    [_fpsSelector setEnabled:allow60FPS forSegmentAtIndex:1];
    if (!allow60FPS && _fpsSelector.selectedSegmentIndex == 1) {
        _fpsSelector.selectedSegmentIndex = 0;
    }
    [self updateStreamSummary];
}

- (void)updateBitrateLabel {
    float bitrate = roundf(_bitrateSlider.value / 500.0) / 2.0;
    NSString *value = [NSString stringWithFormat:@"%.1f Mb/s", bitrate];
    _bitrateLabel.text = [NSString stringWithFormat:@"Video bitrate  ·  %@", value];
    _bitrateSlider.accessibilityValue = value;
}

- (void)bitrateChanged:(UISlider *)sender {
    [self updateBitrateLabel];
}

- (void)resolutionChanged:(UISegmentedControl *)sender {
    NSInteger index = sender.selectedSegmentIndex;
    if (index < 0 || index >= (NSInteger)_supportedResolutions.count) {
        return;
    }
    CGSize resolution = _supportedResolutions[index].CGSizeValue;
    if (CGSizeEqualToSize(resolution, CGSizeMake(1024, 768))) {
        _bitrateSlider.value = 4000;
    } else if (CGSizeEqualToSize(resolution, CGSizeMake(1280, 960))) {
        _bitrateSlider.value = 6000;
    } else if (CGSizeEqualToSize(resolution, CGSizeMake(1440, 1080))) {
        _bitrateSlider.value = 8000;
    }
    [self updateBitrateLabel];
    [self updateFrameRateAvailability];
}

- (void)frameRateChanged:(UISegmentedControl *)sender {
    [self updateStreamSummary];
}

- (void)experimental1080Changed:(UISwitch *)sender {
    self.profile.resolution = _supportedResolutions[_resolutionSelector.selectedSegmentIndex].CGSizeValue;
    [self rebuildResolutionSelector];
}

- (void)presentHostPicker:(UIButton *)sender {
    if (self.hosts.count == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No Hosts Available"
                                                                           message:@"Pair a host before enabling second-monitor mode."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    UIAlertController *picker = [UIAlertController alertControllerWithTitle:@"Choose Host"
                                                                       message:@"Select the host that owns this second-monitor profile."
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
    for (TemporaryHost *host in self.hosts) {
        NSString *hostUUID = host.uuid;
        NSString *hostName = host.name ?: hostUUID;
        [picker addAction:[UIAlertAction actionWithTitle:hostName
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction *action) {
            self.selectedHostUUID = hostUUID;
            [self loadProfileForSelectedHost];
            [self updateHostButtonTitle];
        }]];
    }
    [picker addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    if (picker.popoverPresentationController != nil) {
        picker.popoverPresentationController.sourceView = sender;
        picker.popoverPresentationController.sourceRect = sender.bounds;
    }
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)checkLink:(UIButton *)sender {
    if (_checkingLink) {
        return;
    }
    TemporaryHost *host = [self hostWithUUID:self.selectedHostUUID];
    NSString *address = host.activeAddress ?: host.localAddress ?: host.address ?: host.externalAddress ?: host.ipv6Address;
    if (address.length == 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"No computer address"
            message:@"Open the computer in StreamDesk to discover its current address."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    _checkingLink = YES;
    sender.enabled = NO;
    NSString *uuid = host.uuid;
    [sender setTitle:@"Checking…" forState:UIControlStateNormal];
    __weak LMSecondMonitorSettingsViewController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        HttpManager *manager = [[HttpManager alloc] initWithAddress:address httpsPort:host.httpsPort serverCert:nil];
        NSUInteger replies = 0;
        double totalMs = 0;
        for (NSUInteger attempt = 0; attempt < 3; ++attempt) {
            ServerInfoResponse *response = [[ServerInfoResponse alloc] init];
            NSURLRequest *request = [manager newHttpServerInfoRequest:true];
            CFTimeInterval start = CACurrentMediaTime();
            [manager executeRequestSynchronously:[HttpRequest requestForResponse:response withUrlRequest:request]];
            if (response.isStatusOk) {
                totalMs += (CACurrentMediaTime() - start) * 1000;
                ++replies;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            LMSecondMonitorSettingsViewController *panel = weakSelf;
            if (panel == nil) {
                return;
            }
            panel->_checkingLink = NO;
            [sender setTitle:@"Check connection" forState:UIControlStateNormal];
            [panel updateHostButtonTitle];
            if (panel.viewIfLoaded.window == nil || ![panel.selectedHostUUID isEqualToString:uuid] || panel.presentedViewController != nil) {
                return;
            }
            NSString *message = replies == 0 ? @"The computer did not respond. Check that Sunshine is running at the saved address." :
                [NSString stringWithFormat:@"%lu of 3 replies · %.0f ms average HTTP response", (unsigned long)replies, totalMs / replies];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Connection check"
                message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
            [panel presentViewController:alert animated:YES completion:nil];
        });
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Second display";
    self.view.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
    self.view.tintColor = SDAccent();

    if (self.profile == nil) {
        self.profile = [LMStreamProfile defaultSecondMonitorProfile];
    }
    if ([self hostWithUUID:self.selectedHostUUID] == nil) {
        self.selectedHostUUID = nil;
    }
    _capabilityProfile = [LMStreamProfile currentDeviceCapabilityProfile];
    _supportedFrameRates = @[@30, @60];

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
    _settingsStack.spacing = 16.0;
    [_settingsScrollView addSubview:_settingsStack];
    [NSLayoutConstraint activateConstraints:@[
        [_settingsStack.leadingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.leadingAnchor constant:20.0],
        [_settingsStack.trailingAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.trailingAnchor constant:-20.0],
        [_settingsStack.topAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.topAnchor constant:20.0],
        [_settingsStack.bottomAnchor constraintEqualToAnchor:_settingsScrollView.contentLayoutGuide.bottomAnchor constant:-20.0],
        [_settingsStack.widthAnchor constraintEqualToAnchor:_settingsScrollView.frameLayoutGuide.widthAnchor constant:-40.0],
    ]];

    [self addSectionTitle:@"Computer"];
    _streamSummary = [self detailLabel:@""];
    _streamSummary.textColor = SDAccent();
    _streamSummary.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    [self addControl:_streamSummary];
    _hostButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_hostButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _hostButton.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1.0];
    _hostButton.layer.cornerRadius = 8;
    _hostButton.backgroundColor = [UIColor colorWithWhite:0.19 alpha:1];
    _hostButton.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    [_hostButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [_hostButton addTarget:self action:@selector(presentHostPicker:) forControlEvents:UIControlEventTouchUpInside];
    [self addControl:_hostButton];
    [self updateHostButtonTitle];
    _modeSelector = [[UISegmentedControl alloc] initWithItems:@[@"Display app only", @"All apps on this computer"]];
    _modeSelector.selectedSegmentIndex = [self.allAppsHostUUID isEqualToString:self.selectedHostUUID] ? 1 : 0;
    [self addControl:_modeSelector];
    [self addControl:[self detailLabel:@"StreamDesk Display uses this profile. Other apps use Other streams unless you select All apps on this computer."]];

    [self addSectionTitle:@"Picture"];
    [self addControl:[self detailLabel:@"1024×768 uses less bandwidth. 1440×1080 gives text more detail."]];
    if (_capabilityProfile == LMDeviceCapabilityProfileIPadAir) {
        _experimental1080Switch = [[UISwitch alloc] init];
        _experimental1080Switch.on = self.profile.experimental1080pEnabled;
        [_experimental1080Switch addTarget:self action:@selector(experimental1080Changed:) forControlEvents:UIControlEventValueChanged];
        [self addSwitch:_experimental1080Switch title:@"Show experimental 1920×1080 at 30 FPS"];
    }
    [self rebuildResolutionSelector];

    NSMutableArray<NSString *> *frameRateTitles = [NSMutableArray array];
    for (NSNumber *frameRate in _supportedFrameRates) {
        [frameRateTitles addObject:[NSString stringWithFormat:@"%@ FPS", frameRate]];
    }
    _fpsSelector = [[UISegmentedControl alloc] initWithItems:frameRateTitles];
    _fpsSelector.selectedSegmentIndex = [self selectedIndexForFrameRate:self.profile.fps];
    _fpsSelector.accessibilityLabel = @"Frame rate";
    [_fpsSelector addTarget:self action:@selector(frameRateChanged:) forControlEvents:UIControlEventValueChanged];
    [self addControl:_fpsSelector];
    [self addControl:[self detailLabel:@"60 FPS shows motion more often and can use more battery and bandwidth."]];

    _bitrateLabel = [self detailLabel:@""];
    _bitrateLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightMedium];
    [self addControl:_bitrateLabel];
    _bitrateSlider = [[UISlider alloc] init];
    _bitrateSlider.minimumValue = 500.0;
    _bitrateSlider.minimumTrackTintColor = SDAccent();
    _bitrateSlider.accessibilityLabel = @"Video bitrate";
    [_bitrateSlider.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    _bitrateSlider.maximumValue = 30000.0;
    _bitrateSlider.value = MAX(_bitrateSlider.minimumValue, MIN(_bitrateSlider.maximumValue, self.profile.bitrate));
    [_bitrateSlider addTarget:self action:@selector(bitrateChanged:) forControlEvents:UIControlEventValueChanged];
    [self addControl:_bitrateSlider];
    [self updateBitrateLabel];
    [self updateFrameRateAvailability];

    [self addSectionTitle:@"Sound and input"];
    _audioSelector = [[UISegmentedControl alloc] initWithItems:@[@"Off", @"Host", @"Stream"]];
    _audioSelector.selectedSegmentIndex = MIN(self.profile.audioPolicy, 2);
    _audioSelector.accessibilityLabel = @"Audio output";
    [self addControl:_audioSelector];
    _inputModeSelector = [[UISegmentedControl alloc] initWithItems:@[@"Touch", @"Mouse", @"Hybrid"]];
    _inputModeSelector.selectedSegmentIndex = self.profile.inputMode;
    [self addControl:_inputModeSelector];

    _inputModeSelector.accessibilityLabel = @"Input mode";
    [self addControl:[self detailLabel:@"Use mouse mode if the host treats touches as clicks."]];
    [self addSectionTitle:@"Connection"];
    _framePacingSwitch = [[UISwitch alloc] init];
    _framePacingSwitch.on = self.profile.framePacing;
    [self addSwitch:_framePacingSwitch title:@"Smooth uneven frame delivery"];
    [self addControl:[self detailLabel:@"Can add one frame of latency. Leave off for the quickest response."]];
    _reconnectSwitch = [[UISwitch alloc] init];
    _reconnectSwitch.on = self.profile.reconnectEnabled;
    [self addSwitch:_reconnectSwitch title:@"Reconnect after a drop"];
    _diagnosticsSwitch = [[UISwitch alloc] init];
    _diagnosticsSwitch.on = [[NSUserDefaults standardUserDefaults] boolForKey:@"Moonlight.SecondMonitor.Diagnostics"];
    [self addSwitch:_diagnosticsSwitch title:@"Show stream statistics"];
    _checkLinkButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_checkLinkButton setTitle:@"Check connection" forState:UIControlStateNormal];
    [_checkLinkButton addTarget:self action:@selector(checkLink:) forControlEvents:UIControlEventTouchUpInside];
    [_checkLinkButton.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [self addControl:_checkLinkButton];
    [self updateHostButtonTitle];
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
    profile.framePacing = _framePacingSwitch.isOn;
    profile.codec = LMStreamCodecH264;
    profile.hdrEnabled = NO;
    if (_experimental1080Switch != nil) {
        profile.experimental1080pEnabled = LMSecondMonitorProfileSupportsExplicit1080p30(_experimental1080Switch.isOn,
                                                                                          profile.resolution,
                                                                                          profile.fps);
    }
    return profile;
}

- (void)saveSettings:(id)sender {
    LMStreamProfile *profile = [self profileFromControls];
    BOOL active = _modeSelector.selectedSegmentIndex == 1;
    NSError *error = nil;
    if (![profile validateForCapabilityProfile:_capabilityProfile error:&error]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Invalid Profile"
                                                                           message:error.localizedDescription
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (!LMSecondMonitorProfileSelectionIsValid(active, self.selectedHostUUID, profile)) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Choose a Host"
                                                                           message:@"Select a valid host and profile before enabling second-monitor mode."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }

    if (self.completion != nil) {
        self.completion(self.selectedHostUUID, profile, active, _diagnosticsSwitch.isOn);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

UINavigationController *LMCreateSecondMonitorSettingsNavigationController(NSArray *hosts,
                                                                          NSString *selectedHostUUID,
                                                                          LMStreamProfile *profile,
                                                                          BOOL active,
                                                                          LMSecondMonitorSettingsCompletion completion) {
    LMSecondMonitorSettingsViewController *panel = [[LMSecondMonitorSettingsViewController alloc] init];
    panel.hosts = hosts ?: @[];
    panel.selectedHostUUID = selectedHostUUID;
    panel.profile = profile ?: [LMStreamProfile defaultSecondMonitorProfile];
    panel.allAppsHostUUID = active ? selectedHostUUID : nil;
    panel.completion = completion;

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:panel];
    navigationController.navigationBar.barStyle = UIBarStyleBlack;
    navigationController.navigationBar.translucent = NO;
    navigationController.navigationBar.barTintColor = [UIColor colorWithWhite:0.07 alpha:1];
    navigationController.navigationBar.tintColor = SDAccent();
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor colorWithWhite:0.07 alpha:1];
        appearance.titleTextAttributes = @{NSForegroundColorAttributeName: UIColor.whiteColor};
        navigationController.navigationBar.standardAppearance = appearance;
        navigationController.navigationBar.scrollEdgeAppearance = appearance;
    }
    return navigationController;
}

NSString * const LMSecondDisplayShortcutHostKey = @"Moonlight.SecondMonitor.ShortcutHostUUID";

void LMPresentSecondDisplaySettings(UIViewController *presenter, NSString *preferredHostUUID) {
    DataManager *dataMan = [[DataManager alloc] init];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL active = [defaults boolForKey:@"Moonlight.SecondMonitor.Active"];
    NSString *savedHostUUID = [defaults stringForKey:@"Moonlight.SecondMonitor.HostUUID"];
    NSString *hostUUID = preferredHostUUID ?: [defaults stringForKey:LMSecondDisplayShortcutHostKey] ?: savedHostUUID;
    NSArray *hosts = [dataMan getHosts];
    if (hostUUID == nil && hosts.count == 1) {
        hostUUID = [hosts.firstObject valueForKey:@"uuid"];
    }
    LMStreamProfile *profile = hostUUID.length ? [dataMan getSecondMonitorProfileForHost:hostUUID] : nil;
    UINavigationController *navigation = LMCreateSecondMonitorSettingsNavigationController(
        hosts, hostUUID, profile ?: [LMStreamProfile defaultSecondMonitorProfile], active && [savedHostUUID isEqualToString:hostUUID],
        ^(NSString *selectedHostUUID, LMStreamProfile *updatedProfile, BOOL selectedActive, BOOL diagnostics) {
            if (selectedHostUUID.length != 0) {
                [dataMan saveSecondMonitorProfile:updatedProfile forHost:selectedHostUUID];
                [defaults setObject:selectedHostUUID forKey:LMSecondDisplayShortcutHostKey];
            }
            if (selectedActive) {
                [defaults setObject:selectedHostUUID forKey:@"Moonlight.SecondMonitor.HostUUID"];
                [defaults setBool:YES forKey:@"Moonlight.SecondMonitor.Active"];
            } else if ([savedHostUUID isEqualToString:selectedHostUUID]) {
                [defaults setBool:NO forKey:@"Moonlight.SecondMonitor.Active"];
            }
            [defaults setBool:diagnostics forKey:@"Moonlight.SecondMonitor.Diagnostics"];
        });
    LMSecondMonitorSettingsViewController *panel = (LMSecondMonitorSettingsViewController *)navigation.topViewController;
    panel.allAppsHostUUID = active ? savedHostUUID : nil;
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    [presenter presentViewController:navigation animated:YES completion:nil];
}

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

- (void)hideHDRSetting {
    self.hdrSelector.hidden = YES;
    for (UIView *view in self.scrollView.subviews) {
        if ([view isKindOfClass:[UILabel class]] && [((UILabel *)view).text containsString:@"HDR"]) {
            view.hidden = YES;
        }
    }
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
        [self hideHDRSetting];
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
        [self hideHDRSetting];
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
