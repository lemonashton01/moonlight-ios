#import "PlayniteStartupOverlay.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <VideoToolbox/VideoToolbox.h>

#import "Logger.h"

static const NSTimeInterval PlayniteReadinessTimeout = 60.0;
static const NSTimeInterval PlayniteFadeToBlackDuration = 0.4;
static const NSTimeInterval PlayniteBlackHoldDuration = 0.2;
static const NSTimeInterval PlayniteFadeToStreamDuration = 0.5;
static void *PlaynitePlayerItemStatusContext = &PlaynitePlayerItemStatusContext;
static void *PlayniteItemDiagnosticsContext = &PlayniteItemDiagnosticsContext;
static void *PlaynitePlayerDiagnosticsContext = &PlaynitePlayerDiagnosticsContext;

@implementation PlayniteStartupOverlay {
    AVPlayer *_player;
    AVPlayerLayer *_playerLayer;
    AVPlayerItemVideoOutput *_videoOutput;
    id _timeObserverToken;
    CVPixelBufferRef _latestVideoFrame;

    UIImageView *_finalFrameView;
    UIView *_blackView;
    UIView *_recoveryView;
    UILabel *_recoveryLabel;
    UIButton *_retryButton;
    UIButton *_manualRevealButton;
    UIButton *_cancelButton;
    dispatch_block_t _timeoutWorkItem;

    BOOL _playbackStarted;
    BOOL _videoFinished;
    BOOL _streamReady;
    BOOL _readinessConfirmed;
    BOOL _timedOut;
    BOOL _transitioning;
    BOOL _disposed;
    BOOL _wasPlayingWhenInactive;
    NSTimeInterval _overlayCreatedUptime;
    NSTimeInterval _lastTimeObserverUptime;
    NSTimeInterval _lastLayerLayoutLogUptime;
    NSUInteger _layerLayoutCount;
    CMTime _latestVideoFrameTime;
    NSTimer *_mainThreadWatchdogTimer;
    NSTimeInterval _lastMainThreadWatchdogUptime;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _overlayCreatedUptime = [NSProcessInfo processInfo].systemUptime;
        _latestVideoFrameTime = kCMTimeInvalid;
        self.backgroundColor = UIColor.blackColor;
        self.opaque = YES;
        self.userInteractionEnabled = YES;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

        _playerLayer = [AVPlayerLayer layer];
        _playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        [self.layer addSublayer:_playerLayer];

        _finalFrameView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _finalFrameView.contentMode = UIViewContentModeScaleAspectFit;
        _finalFrameView.backgroundColor = UIColor.blackColor;
        _finalFrameView.hidden = YES;
        [self addSubview:_finalFrameView];

        _blackView = [[UIView alloc] initWithFrame:CGRectZero];
        _blackView.backgroundColor = UIColor.blackColor;
        _blackView.alpha = 0;
        [self addSubview:_blackView];

        _recoveryView = [[UIView alloc] initWithFrame:CGRectZero];
        _recoveryView.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.88];
        _recoveryView.layer.cornerRadius = 12;
        _recoveryView.layer.masksToBounds = YES;
        _recoveryView.hidden = YES;
        [self addSubview:_recoveryView];

        _recoveryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _recoveryLabel.text = @"Playnite readiness was not confirmed.";
        _recoveryLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _recoveryLabel.textColor = UIColor.whiteColor;
        _recoveryLabel.textAlignment = NSTextAlignmentCenter;
        [_recoveryView addSubview:_recoveryLabel];

        UIStackView *buttonStack = [[UIStackView alloc] initWithFrame:CGRectZero];
        buttonStack.axis = UILayoutConstraintAxisHorizontal;
        buttonStack.alignment = UIStackViewAlignmentFill;
        buttonStack.distribution = UIStackViewDistributionFillEqually;
        buttonStack.spacing = 8;
        [_recoveryView addSubview:buttonStack];

        _retryButton = [self recoveryButtonWithTitle:@"Retry" action:@selector(retryTapped)];
        _manualRevealButton = [self recoveryButtonWithTitle:@"Show stream" action:@selector(manualRevealTapped)];
        _manualRevealButton.enabled = NO;
        _cancelButton = [self recoveryButtonWithTitle:@"Cancel" action:@selector(cancelTapped)];
        [buttonStack addArrangedSubview:_retryButton];
        [buttonStack addArrangedSubview:_manualRevealButton];
        [buttonStack addArrangedSubview:_cancelButton];
        buttonStack.tag = 7001;

#if DEBUG
        NSLog(@"[PlayniteDiag] startup overlay created uptime=%.3f mainThread=%@",
              _overlayCreatedUptime,
              [NSThread isMainThread] ? @"yes" : @"no");
#endif
    }
    return self;
}

- (UIButton *)recoveryButtonWithTitle:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithWhite:0.7 alpha:1] forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    button.backgroundColor = [UIColor colorWithWhite:0.24 alpha:1];
    button.layer.cornerRadius = 8;
    button.contentEdgeInsets = UIEdgeInsetsMake(8, 10, 8, 10);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)layoutSubviews {
    [super layoutSubviews];
#if DEBUG
    _layerLayoutCount++;
    NSTimeInterval layoutUptime = [NSProcessInfo processInfo].systemUptime;
    if (_lastLayerLayoutLogUptime == 0 || layoutUptime - _lastLayerLayoutLogUptime >= 1.0) {
        NSLog(@"[PlayniteDiag] overlay layout window: calls=%lu frame=%.0fx%.0f uptime=%.3f",
              (unsigned long)_layerLayoutCount,
              self.bounds.size.width,
              self.bounds.size.height,
              layoutUptime);
        _layerLayoutCount = 0;
        _lastLayerLayoutLogUptime = layoutUptime;
    }
#endif
    _playerLayer.frame = self.bounds;
    _finalFrameView.frame = self.bounds;
    _blackView.frame = self.bounds;

    CGFloat width = MIN(MAX(300, self.bounds.size.width - 32), 480);
    CGFloat safeBottom = 0;
    if (@available(iOS 11.0, *)) {
        safeBottom = self.safeAreaInsets.bottom;
    }
    _recoveryView.frame = CGRectMake((self.bounds.size.width - width) / 2,
                                     self.bounds.size.height - safeBottom - 102 - 16,
                                     width,
                                     102);
    _recoveryLabel.frame = CGRectMake(12, 8, width - 24, 26);
    UIStackView *buttonStack = (UIStackView *)[_recoveryView viewWithTag:7001];
    buttonStack.frame = CGRectMake(10, 42, width - 20, 50);
}

- (void)startPlayback {
    if (_playbackStarted || _disposed) {
        return;
    }
    _playbackStarted = YES;
    [self resetReadinessTimeout];
#if DEBUG
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSLog(@"[PlayniteDiag] AVPlayer setup begin uptime=%.3f mainThread=%@ audioCategory=%@ audioOptions=0x%lx otherAudioPlaying=%@",
          [NSProcessInfo processInfo].systemUptime,
          [NSThread isMainThread] ? @"yes" : @"no",
          audioSession.category,
          (unsigned long)audioSession.categoryOptions,
          audioSession.isOtherAudioPlaying ? @"yes" : @"no");
#endif

    NSURL *videoURL = [[NSBundle mainBundle] URLForResource:@"moonlight_startup" withExtension:@"mp4"];
    if (videoURL == nil) {
        Log(LOG_E, @"Playnite startup video is missing from the app bundle");
        [self finishVideoPlayback];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:videoURL];
#if DEBUG
    NSLog(@"[PlayniteDiag] AVPlayerItem created at +%.3fs uptime=%.3f",
          [NSProcessInfo processInfo].systemUptime - _overlayCreatedUptime,
          [NSProcessInfo processInfo].systemUptime);
#endif
    NSDictionary *attributes = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (id)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
    };
    _videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:attributes];
    [item addOutput:_videoOutput];

    _player = [AVPlayer playerWithPlayerItem:item];
    _playerLayer.player = _player;

    [item addObserver:self
           forKeyPath:@"playbackLikelyToKeepUp"
              options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
              context:PlayniteItemDiagnosticsContext];
    [item addObserver:self
           forKeyPath:@"playbackBufferEmpty"
              options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
              context:PlayniteItemDiagnosticsContext];
    [item addObserver:self
           forKeyPath:@"playbackBufferFull"
              options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
              context:PlayniteItemDiagnosticsContext];
    [_player addObserver:self
              forKeyPath:@"timeControlStatus"
                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:PlaynitePlayerDiagnosticsContext];
    [_player addObserver:self
              forKeyPath:@"rate"
                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:PlaynitePlayerDiagnosticsContext];
    [_player addObserver:self
              forKeyPath:@"reasonForWaitingToPlay"
                 options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                 context:PlaynitePlayerDiagnosticsContext];

    [item addObserver:self
           forKeyPath:@"status"
              options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
              context:PlaynitePlayerItemStatusContext];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(videoItemFinished:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(videoItemFailed:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(videoPlaybackStalled:)
                                                 name:AVPlayerItemPlaybackStalledNotification
                                               object:item];
#if DEBUG
    if (@available(iOS 16.0, *)) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(playerRateDidChange:)
                                                     name:AVPlayerRateDidChangeNotification
                                                   object:_player];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioRouteChanged:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:[AVAudioSession sharedInstance]];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioServicesReset:)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:[AVAudioSession sharedInstance]];
#endif

    __weak typeof(self) weakSelf = self;
    _timeObserverToken = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 10)
                                                               queue:dispatch_get_main_queue()
                                                          usingBlock:^(CMTime time) {
        PlayniteStartupOverlay *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_disposed) {
            return;
        }
        NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
        if (strongSelf->_lastTimeObserverUptime > 0) {
            NSTimeInterval observerGap = now - strongSelf->_lastTimeObserverUptime;
            if (observerGap >= 0.25) {
#if DEBUG
                NSLog(@"[PlayniteDiag] AVPlayer main-queue time observer gap=%.3fs currentTime=%.3f uptime=%.3f",
                      observerGap,
                      CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time) : -1.0,
                      now);
#endif
            }
        }
        strongSelf->_lastTimeObserverUptime = now;
        [strongSelf captureVideoFrameAtTime:time];
    }];
#if DEBUG
    _lastMainThreadWatchdogUptime = [NSProcessInfo processInfo].systemUptime;
    _mainThreadWatchdogTimer = [NSTimer timerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(mainThreadWatchdogFired:)
                                                     userInfo:nil
                                                      repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:_mainThreadWatchdogTimer forMode:NSRunLoopCommonModes];
    NSLog(@"[PlayniteDiag] AVPlayer play request uptime=%.3f mainThread=%@ playerCount=1",
          [NSProcessInfo processInfo].systemUptime,
          [NSThread isMainThread] ? @"yes" : @"no");
#endif
    Log(LOG_I, @"Starting bundled Playnite Horizon Scan video");
    [_player play];
}

- (void)mainThreadWatchdogFired:(NSTimer *)timer {
    (void)timer;
#if DEBUG
    NSTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    NSTimeInterval heartbeatGap = _lastMainThreadWatchdogUptime > 0 ?
        now - _lastMainThreadWatchdogUptime : 0;
    _lastMainThreadWatchdogUptime = now;
    NSLog(@"[PlayniteDiag] main-thread heartbeat gap=%.3fs uptime=%.3f",
          heartbeatGap,
          now);
    [self logPlaybackDiagnostics:@"main-thread heartbeat"];
#endif
}

- (void)logPlaybackDiagnostics:(NSString *)event {
#if DEBUG
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self logPlaybackDiagnostics:event]; });
        return;
    }
    AVPlayerItem *item = _player.currentItem;
    double currentTime = _player != nil && CMTIME_IS_NUMERIC(_player.currentTime) ?
        CMTimeGetSeconds(_player.currentTime) : -1.0;
    double videoOutputTime = CMTIME_IS_NUMERIC(_latestVideoFrameTime) ?
        CMTimeGetSeconds(_latestVideoFrameTime) : -1.0;
    NSString *timeControlStatus = @"unavailable";
    if (_player != nil) {
        switch (_player.timeControlStatus) {
            case AVPlayerTimeControlStatusPaused:
                timeControlStatus = @"paused";
                break;
            case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
                timeControlStatus = @"waiting";
                break;
            case AVPlayerTimeControlStatusPlaying:
                timeControlStatus = @"playing";
                break;
            default:
                timeControlStatus = @"unknown";
                break;
        }
    }
    NSString *waitingReason = _player.reasonForWaitingToPlay ?: @"none";
    CMTimeRange loadedRange = kCMTimeRangeInvalid;
    if (item.loadedTimeRanges.count > 0) {
        loadedRange = [item.loadedTimeRanges.lastObject CMTimeRangeValue];
    }
    double loadedEnd = CMTIMERANGE_IS_VALID(loadedRange) ?
        CMTimeGetSeconds(CMTimeRangeGetEnd(loadedRange)) : -1.0;
    NSLog(@"[PlayniteDiag] t=+%.3fs event=%@ playerStatus=%ld itemStatus=%ld timeControlStatus=%@ rate=%.3f currentTime=%.3f reasonForWaitingToPlay=%@ playbackLikelyToKeepUp=%@ playbackBufferEmpty=%@ playbackBufferFull=%@ loadedEnd=%.3f videoOutputTime=%.3f layerReadyForDisplay=%@ uptime=%.3f",
          [NSProcessInfo processInfo].systemUptime - _overlayCreatedUptime,
          event,
          (long)_player.status,
          (long)item.status,
          timeControlStatus,
          _player.rate,
          currentTime,
          waitingReason,
          item.playbackLikelyToKeepUp ? @"yes" : @"no",
          item.playbackBufferEmpty ? @"yes" : @"no",
          item.playbackBufferFull ? @"yes" : @"no",
          loadedEnd,
          videoOutputTime,
          _playerLayer.readyForDisplay ? @"yes" : @"no",
          [NSProcessInfo processInfo].systemUptime);
#else
    (void)event;
#endif
}

#if DEBUG
- (void)playerRateDidChange:(NSNotification *)notification {
    NSInteger reasonCode = 0;
    if (@available(iOS 16.0, *)) {
        AVPlayerRateDidChangeReason reason = notification.userInfo[AVPlayerRateDidChangeReasonKey];
        if ([reason isEqualToString:AVPlayerRateDidChangeReasonAudioSessionInterrupted]) {
            reasonCode = 1;
        }
        else if ([reason isEqualToString:AVPlayerRateDidChangeReasonAppBackgrounded]) {
            reasonCode = 2;
        }
        else if ([reason isEqualToString:AVPlayerRateDidChangeReasonSetRateCalled]) {
            reasonCode = 3;
        }
        else if ([reason isEqualToString:AVPlayerRateDidChangeReasonSetRateFailed]) {
            reasonCode = 4;
        }
    }
    // 1=audio interruption, 2=background, 3=explicit rate change, 4=failed rate change.
    NSLog(@"[PlayniteDiag] AVPlayer rate change reasonCode=%ld rate=%.3f uptime=%.3f",
          (long)reasonCode, _player.rate, [NSProcessInfo processInfo].systemUptime);
    [self logPlaybackDiagnostics:@"rateDidChangeNotification"];
}

- (void)audioSessionInterrupted:(NSNotification *)notification {
    NSLog(@"[PlayniteDiag] AVAudioSession interruption type=%ld reason=%ld option=%ld uptime=%.3f",
          (long)[notification.userInfo[AVAudioSessionInterruptionTypeKey] integerValue],
          (long)[notification.userInfo[AVAudioSessionInterruptionReasonKey] integerValue],
          (long)[notification.userInfo[AVAudioSessionInterruptionOptionKey] integerValue],
          [NSProcessInfo processInfo].systemUptime);
    [self logPlaybackDiagnostics:@"audioSessionInterruption"];
}

- (void)audioRouteChanged:(NSNotification *)notification {
    NSLog(@"[PlayniteDiag] AVAudioSession route change reason=%ld uptime=%.3f",
          (long)[notification.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue],
          [NSProcessInfo processInfo].systemUptime);
    [self logPlaybackDiagnostics:@"audioRouteChange"];
}

- (void)audioServicesReset:(NSNotification *)notification {
    (void)notification;
    NSLog(@"[PlayniteDiag] AVAudioSession media services reset uptime=%.3f",
          [NSProcessInfo processInfo].systemUptime);
    [self logPlaybackDiagnostics:@"audioServicesReset"];
}
#endif

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context == PlaynitePlayerItemStatusContext && [keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
#if DEBUG
        [self logPlaybackDiagnostics:[NSString stringWithFormat:@"item.status changed to %ld", (long)item.status]];
#endif
        if (item.status == AVPlayerItemStatusFailed) {
            Log(LOG_E, @"Playnite startup video item failed to load: %@", item.error);
            dispatch_async(dispatch_get_main_queue(), ^{ [self finishVideoPlayback]; });
        }
        return;
    }
    if (context == PlayniteItemDiagnosticsContext || context == PlaynitePlayerDiagnosticsContext) {
#if DEBUG
        [self logPlaybackDiagnostics:[NSString stringWithFormat:@"KVO %@", keyPath]];
#endif
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}

- (void)captureVideoFrameAtTime:(CMTime)time {
    if (_videoOutput == nil || _videoFinished || _disposed || !CMTIME_IS_NUMERIC(time)) {
        return;
    }

    CFTimeInterval copyStart = CACurrentMediaTime();
    CMTime presentationTime = kCMTimeInvalid;
    CVPixelBufferRef frame = [_videoOutput copyPixelBufferForItemTime:time itemTimeForDisplay:&presentationTime];
    CFTimeInterval copyDuration = CACurrentMediaTime() - copyStart;
    if (frame != NULL) {
        if (_latestVideoFrame != NULL) {
            CVPixelBufferRelease(_latestVideoFrame);
        }
        _latestVideoFrame = frame;
        _latestVideoFrameTime = CMTIME_IS_NUMERIC(presentationTime) ? presentationTime : time;
    }
#if DEBUG
    if (copyDuration >= 0.025) {
        NSLog(@"[PlayniteDiag] AVPlayerItemVideoOutput copy duration=%.3fs returnedFrame=%@ itemTime=%.3f outputTime=%.3f uptime=%.3f",
              copyDuration,
              frame != NULL ? @"yes" : @"no",
              CMTIME_IS_NUMERIC(time) ? CMTimeGetSeconds(time) : -1.0,
              CMTIME_IS_NUMERIC(presentationTime) ? CMTimeGetSeconds(presentationTime) : -1.0,
              [NSProcessInfo processInfo].systemUptime);
    }
#endif
}

- (UIImage *)imageForPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (pixelBuffer == NULL) {
        return nil;
    }
    CGImageRef cgImage = NULL;
    OSStatus status = VTCreateCGImageFromCVPixelBuffer(pixelBuffer, NULL, &cgImage);
    if (status != noErr || cgImage == NULL) {
        Log(LOG_W, @"Could not retain the final startup-video frame: %d", (int)status);
        return nil;
    }
    UIImage *result = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return result;
}

- (void)videoItemFinished:(NSNotification *)notification {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self videoItemFinished:notification]; });
        return;
    }
#if DEBUG
    [self logPlaybackDiagnostics:@"AVPlayerItemDidPlayToEndTime"];
#endif
    AVPlayerItem *item = notification.object;
    if (_videoOutput != nil && CMTIME_IS_NUMERIC(item.duration) && CMTimeCompare(item.duration, CMTimeMake(1, 60)) > 0) {
        CMTime finalFrameTime = CMTimeSubtract(item.duration, CMTimeMake(1, 60));
        [self captureVideoFrameAtTime:finalFrameTime];
    }
    [self finishVideoPlayback];
}

- (void)videoItemFailed:(NSNotification *)notification {
    Log(LOG_E, @"Playnite startup video playback failed: %@", notification.userInfo);
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
#if DEBUG
            [self logPlaybackDiagnostics:@"AVPlayerItemFailedToPlayToEndTime"];
#endif
            [self finishVideoPlayback];
        });
    }
    else {
#if DEBUG
        [self logPlaybackDiagnostics:@"AVPlayerItemFailedToPlayToEndTime"];
#endif
        [self finishVideoPlayback];
    }
}

- (void)videoPlaybackStalled:(NSNotification *)notification {
    (void)notification;
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self videoPlaybackStalled:nil]; });
        return;
    }
#if DEBUG
    [self logPlaybackDiagnostics:@"AVPlayerItemPlaybackStalled"];
#endif
}

- (void)finishVideoPlayback {
    if (_videoFinished || _disposed) {
        return;
    }

#if DEBUG
    [self logPlaybackDiagnostics:@"finishVideoPlayback"];
#endif
    _videoFinished = YES;
    if (_latestVideoFrame != NULL) {
        _finalFrameView.image = [self imageForPixelBuffer:_latestVideoFrame];
        CVPixelBufferRelease(_latestVideoFrame);
        _latestVideoFrame = NULL;
    }
    _finalFrameView.hidden = (_finalFrameView.image == nil);
    [self releaseVideoPlaybackResources];
    [self updateRecoveryVisibility];
    [self maybeStartTransition];
}

- (void)releaseVideoPlaybackResources {
    if (_player != nil) {
        if (_timeObserverToken != nil) {
            [_player removeTimeObserver:_timeObserverToken];
            _timeObserverToken = nil;
        }
        AVPlayerItem *item = _player.currentItem;
        if (item != nil) {
            @try {
                [item removeObserver:self forKeyPath:@"status" context:PlaynitePlayerItemStatusContext];
            }
            @catch (NSException *exception) {
                // The item may already have invalidated its observation during a failed load.
                (void)exception;
            }
            NSArray<NSString *> *itemDiagnosticKeyPaths = @[
                @"playbackLikelyToKeepUp",
                @"playbackBufferEmpty",
                @"playbackBufferFull",
            ];
            for (NSString *keyPath in itemDiagnosticKeyPaths) {
                @try {
                    [item removeObserver:self forKeyPath:keyPath context:PlayniteItemDiagnosticsContext];
                }
                @catch (NSException *exception) {
                    (void)exception;
                }
            }
        }
        NSArray<NSString *> *playerDiagnosticKeyPaths = @[
            @"timeControlStatus",
            @"rate",
            @"reasonForWaitingToPlay",
        ];
        for (NSString *keyPath in playerDiagnosticKeyPaths) {
            @try {
                [_player removeObserver:self forKeyPath:keyPath context:PlaynitePlayerDiagnosticsContext];
            }
            @catch (NSException *exception) {
                (void)exception;
            }
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:item];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemFailedToPlayToEndTimeNotification
                                                      object:item];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemPlaybackStalledNotification
                                                      object:item];
#if DEBUG
        if (@available(iOS 16.0, *)) {
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:AVPlayerRateDidChangeNotification
                                                          object:_player];
        }
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVAudioSessionInterruptionNotification
                                                      object:[AVAudioSession sharedInstance]];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVAudioSessionRouteChangeNotification
                                                      object:[AVAudioSession sharedInstance]];
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVAudioSessionMediaServicesWereResetNotification
                                                      object:[AVAudioSession sharedInstance]];
#endif
        [_player pause];
        _playerLayer.player = nil;
        _player = nil;
    }
    _videoOutput = nil;
}

- (void)markStreamReady {
    _streamReady = YES;
    _manualRevealButton.enabled = _videoFinished;
    [self maybeStartTransition];
}

- (void)markReadinessConfirmed {
    _readinessConfirmed = YES;
    [self maybeStartTransition];
}

- (void)resetReadinessTimeout {
    if (_timeoutWorkItem != nil) {
        dispatch_block_cancel(_timeoutWorkItem);
    }
    __weak typeof(self) weakSelf = self;
    _timeoutWorkItem = dispatch_block_create(0, ^{
        PlayniteStartupOverlay *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_disposed || strongSelf->_transitioning) {
            return;
        }
        strongSelf->_timedOut = YES;
        Log(LOG_W, @"Playnite readiness timed out; explicit recovery controls enabled");
        [strongSelf updateRecoveryVisibility];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PlayniteReadinessTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), _timeoutWorkItem);
}

- (void)updateRecoveryVisibility {
    _recoveryView.hidden = !_timedOut || !_videoFinished || _transitioning || _disposed;
    _manualRevealButton.enabled = _streamReady && _videoFinished;
}

- (void)retryTapped {
    if (_disposed || !_timedOut) {
        return;
    }
    _timedOut = NO;
    _readinessConfirmed = NO;
    _recoveryView.hidden = YES;
    [self resetReadinessTimeout];
    Log(LOG_I, @"Playnite readiness retry requested");
    if (self.retryHandler != nil) {
        self.retryHandler();
    }
}

- (void)manualRevealTapped {
    if (_disposed || !_timedOut || !_streamReady || !_videoFinished) {
        return;
    }
    Log(LOG_I, @"Playnite stream manually revealed after readiness timeout");
    if (self.manualRevealHandler != nil) {
        self.manualRevealHandler();
    }
}

- (void)cancelTapped {
    if (_disposed || !_timedOut) {
        return;
    }
    Log(LOG_I, @"Playnite startup cover cancelled after readiness timeout");
    if (self.cancelHandler != nil) {
        self.cancelHandler();
    }
}

- (void)maybeStartTransition {
    if (!_videoFinished || !_streamReady || !_readinessConfirmed || _transitioning || _disposed) {
        return;
    }

    _transitioning = YES;
    _recoveryView.hidden = YES;
    if (_timeoutWorkItem != nil) {
        dispatch_block_cancel(_timeoutWorkItem);
        _timeoutWorkItem = nil;
    }

    __weak typeof(self) weakSelf = self;
    [UIView animateWithDuration:PlayniteFadeToBlackDuration
                          delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                     animations:^{
        PlayniteStartupOverlay *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_blackView.alpha = 1.0;
        }
    } completion:^(BOOL finished) {
        PlayniteStartupOverlay *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_disposed) {
            return;
        }
        // Expose the stream only after the independent black layer is fully opaque.
        strongSelf->_finalFrameView.hidden = YES;
        strongSelf.backgroundColor = UIColor.clearColor;
        strongSelf.opaque = NO;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                     (int64_t)(PlayniteBlackHoldDuration * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (strongSelf->_disposed) {
                return;
            }
            [UIView animateWithDuration:PlayniteFadeToStreamDuration
                                  delay:0
                                options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut
                             animations:^{
                strongSelf->_blackView.alpha = 0;
            } completion:^(BOOL fadeFinished) {
                if (!strongSelf->_disposed && strongSelf.transitionFinishedHandler != nil) {
                    Log(LOG_I, @"Playnite startup cover faded to the matched stream");
                    strongSelf.transitionFinishedHandler();
                }
            }];
        });
    }];
}

- (void)pausePlaybackForAppDeactivation {
    _wasPlayingWhenInactive = _player.rate > 0;
#if DEBUG
    [self logPlaybackDiagnostics:@"app will resign active"];
#endif
    if (_wasPlayingWhenInactive) {
        [_player pause];
    }
}

- (void)resumePlaybackAfterStreamConnectionStarted {
    // SDL opens and activates its audio device during connection startup.
    // On iOS this can leave the already-playing startup AVPlayer paused, even
    // though its item is fully buffered and the app remains active. Retry only
    // once, after Moonlight has completed its normal audio setup.
    if (_disposed || _videoFinished || !_playbackStarted || _player == nil ||
        [UIApplication sharedApplication].applicationState != UIApplicationStateActive ||
        _player.currentItem.status != AVPlayerItemStatusReadyToPlay ||
        _player.timeControlStatus != AVPlayerTimeControlStatusPaused || _player.rate != 0) {
        return;
    }
#if DEBUG
    [self logPlaybackDiagnostics:@"resuming after Moonlight connection started"];
    NSLog(@"[PlayniteDiag] AVPlayer play retry after Moonlight audio initialization uptime=%.3f",
          [NSProcessInfo processInfo].systemUptime);
#endif
    [_player play];
}

- (void)resumePlaybackAfterAppActivation {
#if DEBUG
    [self logPlaybackDiagnostics:@"app did become active"];
#endif
    if (_wasPlayingWhenInactive && !_videoFinished && !_disposed) {
        [_player play];
    }
    _wasPlayingWhenInactive = NO;
}

- (void)dispose {
    if (_disposed) {
        return;
    }
#if DEBUG
    [self logPlaybackDiagnostics:@"dispose"];
#endif
    _disposed = YES;
#if DEBUG
    [_mainThreadWatchdogTimer invalidate];
    _mainThreadWatchdogTimer = nil;
#endif
    if (_timeoutWorkItem != nil) {
        dispatch_block_cancel(_timeoutWorkItem);
        _timeoutWorkItem = nil;
    }
    [self.layer removeAllAnimations];
    [_blackView.layer removeAllAnimations];
    [self releaseVideoPlaybackResources];
    if (_latestVideoFrame != NULL) {
        CVPixelBufferRelease(_latestVideoFrame);
        _latestVideoFrame = NULL;
    }
    _finalFrameView.image = nil;
    self.retryHandler = nil;
    self.manualRevealHandler = nil;
    self.cancelHandler = nil;
    self.transitionFinishedHandler = nil;
    [self removeFromSuperview];
}

- (void)dealloc {
    [self dispose];
}

@end
