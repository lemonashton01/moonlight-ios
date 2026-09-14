//
//  SpecialKeysPanel.h
//  Moonlight
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SpecialKeysPanel;

@protocol SpecialKeysPanelDelegate <NSObject>

- (void)specialKeysPanel:(SpecialKeysPanel *)panel
        didSelectKeyCode:(short)keyCode
                   title:(NSString *)title;

@end

@interface SpecialKeysPanel : UIView

@property(nonatomic, weak, nullable) id<SpecialKeysPanelDelegate> delegate;
@property(nonatomic, readonly, getter=isVisible) BOOL visible;
@property(nonatomic, readonly, getter=isFixed) BOOL fixed;

- (void)showInView:(UIView *)hostView;
- (void)hideAnimated:(BOOL)animated;
- (void)resetForSession;
- (BOOL)shouldCloseAfterKey;

@end

NS_ASSUME_NONNULL_END
