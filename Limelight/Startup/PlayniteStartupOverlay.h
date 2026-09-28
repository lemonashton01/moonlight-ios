#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Full-screen, opaque video cover. The Moonlight StreamView remains running underneath.
@interface PlayniteStartupOverlay : UIView

@property(nonatomic, copy, nullable) dispatch_block_t retryHandler;
@property(nonatomic, copy, nullable) dispatch_block_t manualRevealHandler;
@property(nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@property(nonatomic, copy, nullable) dispatch_block_t transitionFinishedHandler;

- (void)startPlayback;
- (void)markStreamReady;
- (void)markReadinessConfirmed;
- (void)streamConnectionStarted;
- (void)pausePlaybackForAppDeactivation;
- (void)resumePlaybackAfterAppActivation;
- (void)dispose;

@end

NS_ASSUME_NONNULL_END
