//
//  SpecialKeysPanel.m
//  Moonlight
//

#import "SpecialKeysPanel.h"
#import "SpecialKeysState.h"

#include <math.h>

#if DEBUG
#define SpecialKeysPanelLog(...) NSLog(__VA_ARGS__)
#else
#define SpecialKeysPanelLog(...)
#endif

static NSString *const SpecialKeysCellReuseIdentifier = @"SpecialKeysCell";

@interface SpecialKeysPanel () <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>
@end

@implementation SpecialKeysPanel {
    UIView *_containerView;
    UIButton *_pinButton;
    UISegmentedControl *_tabControl;
    UICollectionView *_collectionView;
    NSLayoutConstraint *_panelHeightConstraint;
    NSArray<NSDictionary<NSString *, id> *> *_functionKeys;
    NSArray<NSDictionary<NSString *, id> *> *_specialKeys;
    SpecialKeysPanelState _panelState;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self buildKeyModels];
        [self buildInterface];
        [self resetForSession];
    }
    return self;
}

- (void)buildKeyModels {
    _functionKeys = @[
        @{ @"title": @"F1", @"code": @(SpecialKeyCodeF1) },
        @{ @"title": @"F2", @"code": @(SpecialKeyCodeF2) },
        @{ @"title": @"F3", @"code": @(SpecialKeyCodeF3) },
        @{ @"title": @"F4", @"code": @(SpecialKeyCodeF4) },
        @{ @"title": @"F5", @"code": @(SpecialKeyCodeF5) },
        @{ @"title": @"F6", @"code": @(SpecialKeyCodeF6) },
        @{ @"title": @"F7", @"code": @(SpecialKeyCodeF7) },
        @{ @"title": @"F8", @"code": @(SpecialKeyCodeF8) },
        @{ @"title": @"F9", @"code": @(SpecialKeyCodeF9) },
        @{ @"title": @"F10", @"code": @(SpecialKeyCodeF10) },
        @{ @"title": @"F11", @"code": @(SpecialKeyCodeF11) },
        @{ @"title": @"F12", @"code": @(SpecialKeyCodeF12) },
    ];
    size_t specialActionCount;
    const SpecialKeysActionDescriptor *specialActions = SpecialKeysGetSpecialActions(&specialActionCount);
    NSMutableArray<NSDictionary<NSString *, id> *> *specialKeys = [NSMutableArray arrayWithCapacity:specialActionCount];
    for (size_t i = 0; i < specialActionCount; i++) {
        [specialKeys addObject:@{
            @"title": [NSString stringWithUTF8String:specialActions[i].title],
            @"code": @(specialActions[i].keyCode),
            @"action": @(specialActions[i].action),
        }];
    }
    _specialKeys = [specialKeys copy];
}

- (void)buildInterface {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.25];
    self.accessibilityViewIsModal = YES;

    UIButton *dismissBackgroundButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissBackgroundButton.translatesAutoresizingMaskIntoConstraints = NO;
    dismissBackgroundButton.accessibilityLabel = @"Close Special Keys";
    [dismissBackgroundButton addTarget:self action:@selector(closeButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:dismissBackgroundButton];

    _containerView = [[UIView alloc] initWithFrame:CGRectZero];
    _containerView.translatesAutoresizingMaskIntoConstraints = NO;
    _containerView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    _containerView.layer.cornerRadius = 14.0;
    _containerView.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
    _containerView.layer.borderWidth = 1.0;
    _containerView.clipsToBounds = YES;
    [self addSubview:_containerView];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.text = @"Special Keys";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:17.0];
    [_containerView addSubview:titleLabel];

    _pinButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _pinButton.translatesAutoresizingMaskIntoConstraints = NO;
    _pinButton.accessibilityLabel = @"Keep Special Keys panel open";
    _pinButton.layer.cornerRadius = 7.0;
    _pinButton.layer.borderWidth = 1.0;
    [_pinButton setTitle:@"Pin" forState:UIControlStateNormal];
    [_pinButton addTarget:self action:@selector(pinButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:_pinButton];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.translatesAutoresizingMaskIntoConstraints = NO;
    closeButton.accessibilityLabel = @"Close Special Keys";
    closeButton.titleLabel.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightRegular];
    [closeButton setTitle:@"×" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [closeButton addTarget:self action:@selector(closeButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_containerView addSubview:closeButton];

    _tabControl = [[UISegmentedControl alloc] initWithItems:@[@"Function", @"Special"]];
    _tabControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_tabControl addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [_containerView addSubview:_tabControl];

    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 8.0;
    layout.minimumInteritemSpacing = 8.0;
    _collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    _collectionView.backgroundColor = [UIColor clearColor];
    _collectionView.dataSource = self;
    _collectionView.delegate = self;
    _collectionView.scrollEnabled = NO;
    _collectionView.contentInset = UIEdgeInsetsMake(0, 12, 12, 12);
    [_collectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:SpecialKeysCellReuseIdentifier];
    [_containerView addSubview:_collectionView];

    UILayoutGuide *safeArea = self.safeAreaLayoutGuide;
    _panelHeightConstraint = [_containerView.heightAnchor constraintEqualToConstant:204.0];
    NSLayoutConstraint *preferredWidth = [_containerView.widthAnchor constraintEqualToAnchor:safeArea.widthAnchor constant:-24.0];
    preferredWidth.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *tabWidth = [_tabControl.widthAnchor constraintEqualToAnchor:_containerView.widthAnchor multiplier:0.48];
    tabWidth.priority = UILayoutPriorityDefaultHigh;

    [NSLayoutConstraint activateConstraints:@[
        [dismissBackgroundButton.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [dismissBackgroundButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [dismissBackgroundButton.topAnchor constraintEqualToAnchor:self.topAnchor],
        [dismissBackgroundButton.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

        [_containerView.centerXAnchor constraintEqualToAnchor:safeArea.centerXAnchor],
        [_containerView.centerYAnchor constraintEqualToAnchor:safeArea.centerYAnchor],
        [_containerView.leadingAnchor constraintGreaterThanOrEqualToAnchor:safeArea.leadingAnchor constant:12.0],
        [_containerView.trailingAnchor constraintLessThanOrEqualToAnchor:safeArea.trailingAnchor constant:-12.0],
        [_containerView.topAnchor constraintGreaterThanOrEqualToAnchor:safeArea.topAnchor constant:12.0],
        [_containerView.bottomAnchor constraintLessThanOrEqualToAnchor:safeArea.bottomAnchor constant:-12.0],
        [_containerView.widthAnchor constraintLessThanOrEqualToConstant:720.0],
        preferredWidth,
        _panelHeightConstraint,

        [titleLabel.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor constant:14.0],
        [titleLabel.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],

        [closeButton.topAnchor constraintEqualToAnchor:_containerView.topAnchor constant:5.0],
        [closeButton.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor constant:-6.0],
        [closeButton.widthAnchor constraintEqualToConstant:38.0],
        [closeButton.heightAnchor constraintEqualToConstant:36.0],

        [_pinButton.trailingAnchor constraintEqualToAnchor:closeButton.leadingAnchor constant:-6.0],
        [_pinButton.centerYAnchor constraintEqualToAnchor:closeButton.centerYAnchor],
        [_pinButton.widthAnchor constraintEqualToConstant:58.0],
        [_pinButton.heightAnchor constraintEqualToConstant:30.0],

        [_tabControl.topAnchor constraintEqualToAnchor:closeButton.bottomAnchor constant:3.0],
        [_tabControl.centerXAnchor constraintEqualToAnchor:_containerView.centerXAnchor],
        [_tabControl.widthAnchor constraintLessThanOrEqualToConstant:300.0],
        tabWidth,
        [_tabControl.heightAnchor constraintEqualToConstant:30.0],

        [_collectionView.topAnchor constraintEqualToAnchor:_tabControl.bottomAnchor constant:8.0],
        [_collectionView.leadingAnchor constraintEqualToAnchor:_containerView.leadingAnchor],
        [_collectionView.trailingAnchor constraintEqualToAnchor:_containerView.trailingAnchor],
        [_collectionView.bottomAnchor constraintEqualToAnchor:_containerView.bottomAnchor],
    ]];

    [self updatePinAppearance];
}

- (BOOL)isVisible {
    return _panelState.visible;
}

- (BOOL)isFixed {
    return _panelState.fixed;
}

- (BOOL)shouldCloseAfterKey {
    return SpecialKeysPanelShouldCloseAfterKey(&_panelState);
}

- (void)showInView:(UIView *)hostView {
    if (self.superview != hostView) {
        [self removeFromSuperview];
        [hostView addSubview:self];
        [NSLayoutConstraint activateConstraints:@[
            [self.leadingAnchor constraintEqualToAnchor:hostView.leadingAnchor],
            [self.trailingAnchor constraintEqualToAnchor:hostView.trailingAnchor],
            [self.topAnchor constraintEqualToAnchor:hostView.topAnchor],
            [self.bottomAnchor constraintEqualToAnchor:hostView.bottomAnchor],
        ]];
    }

    SpecialKeysPanelShow(&_panelState);
    _panelHeightConstraint.constant = hostView.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact ? 204.0 : 260.0;
    _tabControl.selectedSegmentIndex = _panelState.selectedTab;
    [self updatePinAppearance];
    [_collectionView reloadData];
    self.alpha = 0.0;
    [UIView animateWithDuration:0.15 animations:^{ self.alpha = 1.0; }];
    UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, _containerView);
    SpecialKeysPanelLog(@"Special Keys opened");
}

- (void)hideAnimated:(BOOL)animated {
    if (!self.superview) {
        SpecialKeysPanelHide(&_panelState);
        return;
    }

    void (^completion)(BOOL) = ^(BOOL finished) {
        [self removeFromSuperview];
    };
    SpecialKeysPanelHide(&_panelState);
    [self updatePinAppearance];
    SpecialKeysPanelLog(@"Special Keys closed");

    if (animated) {
        [UIView animateWithDuration:0.12 animations:^{ self.alpha = 0.0; } completion:completion];
    }
    else {
        completion(YES);
    }
}

- (void)resetForSession {
    [self hideAnimated:NO];
    SpecialKeysPanelResetSession(&_panelState);
    _tabControl.selectedSegmentIndex = SpecialKeysTabFunction;
    [self updatePinAppearance];
    [_collectionView reloadData];
}

- (void)pinButtonPressed:(UIButton *)sender {
    SpecialKeysPanelSetFixed(&_panelState, !_panelState.fixed);
    [self updatePinAppearance];
    SpecialKeysPanelLog(@"Special Keys fixed mode %@", _panelState.fixed ? @"ON" : @"OFF");
}

- (void)closeButtonPressed:(UIButton *)sender {
    [self hideAnimated:YES];
}

- (void)tabChanged:(UISegmentedControl *)sender {
    SpecialKeysPanelSetSelectedTab(&_panelState, (SpecialKeysTab)sender.selectedSegmentIndex);
    [_collectionView reloadData];
    [_collectionView.collectionViewLayout invalidateLayout];
}

- (void)updatePinAppearance {
    UIColor *accentColor = [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0];
    _pinButton.backgroundColor = _panelState.fixed ? accentColor : [UIColor colorWithWhite:0.18 alpha:1.0];
    _pinButton.layer.borderColor = (_panelState.fixed ? accentColor : [UIColor colorWithWhite:1 alpha:0.25]).CGColor;
    [_pinButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _pinButton.accessibilityValue = _panelState.fixed ? @"On" : @"Off";
}

- (NSArray<NSDictionary<NSString *, id> *> *)currentKeys {
    return _panelState.selectedTab == SpecialKeysTabSpecial ? _specialKeys : _functionKeys;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.currentKeys.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                            cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:SpecialKeysCellReuseIdentifier
                                                                            forIndexPath:indexPath];
    UILabel *label = [cell.contentView viewWithTag:100];
    if (!label) {
        label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.tag = 100;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.textAlignment = NSTextAlignmentCenter;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont systemFontOfSize:16.0 weight:UIFontWeightSemibold];
        [cell.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor],
            [label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
            [label.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        ]];
    }

    NSDictionary<NSString *, id> *key = self.currentKeys[indexPath.item];
    label.text = key[@"title"];
    cell.contentView.backgroundColor = [UIColor colorWithWhite:0.19 alpha:1.0];
    cell.contentView.layer.cornerRadius = 8.0;
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@ key", key[@"title"]];
    cell.isAccessibilityElement = YES;
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary<NSString *, id> *key = self.currentKeys[indexPath.item];
    if ([key[@"action"] integerValue] == SpecialKeysActionCursorToggle) {
        [self.delegate specialKeysPanelDidSelectCursorToggle:self];
    }
    else {
        [self.delegate specialKeysPanel:self
                      didSelectKeyCode:[key[@"code"] shortValue]
                                 title:key[@"title"]];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                   layout:(UICollectionViewLayout *)collectionViewLayout
   sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger keyCount = self.currentKeys.count;
    NSUInteger columns;
    if (collectionView.bounds.size.width >= 520.0) {
        columns = _panelState.selectedTab == SpecialKeysTabFunction ? 6 : 5;
    }
    else {
        columns = _panelState.selectedTab == SpecialKeysTabFunction ? 4 : 3;
    }

    CGFloat horizontalInsets = collectionView.contentInset.left + collectionView.contentInset.right;
    CGFloat spacing = 8.0 * (columns - 1);
    CGFloat width = floor((collectionView.bounds.size.width - horizontalInsets - spacing) / columns);
    NSUInteger rows = (keyCount + columns - 1) / columns;
    CGFloat verticalSpacing = 8.0 * (rows - 1);
    CGFloat height = floor((collectionView.bounds.size.height - collectionView.contentInset.bottom - verticalSpacing) / rows);
    return CGSizeMake(width, MIN(48.0, MAX(36.0, height)));
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    _panelHeightConstraint.constant = self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClassCompact ? 204.0 : 260.0;
    [_collectionView.collectionViewLayout invalidateLayout];
}

@end
