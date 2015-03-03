#import <substrate.h>
#import <UIKit/UIKit.h>

@interface UIImage (UndocumentedMethods)
- (UIImage *)_flatImageWithWhite:(CGFloat)white alpha:(CGFloat)alpha;
@end

@interface SBUIControlCenterSlider : UISlider
@property (assign, nonatomic) BOOL adjusting;
+ (id)_minTrackImageForState:(long long)state;
@end

@interface AlwaysWhiteSlider : SBUIControlCenterSlider
@property (assign, nonatomic) BOOL trackVolumeChanges;
@end

@interface AVSystemController
+ (AVSystemController *)sharedAVSystemController;

- (BOOL)getVolume:(float *)volume forCategory:(NSString *)category;
- (BOOL)setVolumeTo:(float)newVolume forCategory:(NSString *)category;
@end

@interface SBDefaultBannerTextView : UIView
@property (nonatomic, readonly) NSString *primaryText;
+ (UIFont *)_primaryTextFont;
@end

@interface SBDefaultBannerView : UIView
{
	SBDefaultBannerTextView *_textView;
}

- (CGRect)_contentFrame;
@end

@interface BBAction
+ (BBAction *)action;
@end

@interface BBBulletinRequest : NSObject
@property NSString *title;
@property NSString *message;
@property NSString *sectionID;
@property BBAction *defaultAction;

- (BBBulletinRequest *)init;
@end

@interface SBBulletinBannerItem
@property BBBulletinRequest *seedBulletin;
@end

@interface SBBannerController : NSObject
- (SBBulletinBannerItem *)_bannerItem;

// new
- (void)rescheduleTimers;
@end

@interface SBBulletinBannerController
+ (SBBulletinBannerController *)sharedInstance;
- (void)observer:(id)observer addBulletin:(BBBulletinRequest *)request forFeed:(NSInteger)feed;

// new
- (void)sliderValueChanged:(UISlider *)sender;
- (void)sliderTouchBegan:(UISlider *)sender;
- (void)sliderTouchEnded:(UISlider *)sender;
- (void)removeTimers;
- (void)addTimers;
@end

@interface SBUIBannerContext
@property SBBulletinBannerItem *item;
@end

@interface SBBannerContainerViewController
- (SBBulletinBannerItem *)_bannerItem;
@end