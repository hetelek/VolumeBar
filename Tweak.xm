#import "Headers.h"

#define BUNDLE_PATH @"/Library/Application Support/VolumeBar/VolumeBar.bundle"
#define BULLETIN_SLIDER_IDENTIFIER @"slider.volumebar.expetelek.com"
#define BULLETIN_RINGER_IDENTIFIER @"ringer.volumebar.expetelek.com"

static const NSInteger DISMISS_INTERVAL_DELAY = 3;
static const NSInteger REPLACE_INTERVAL_DELAY = 2;
static const CGFloat SLIDER_MAX_WIDTH = 413.0;
static const CGFloat SLIDER_HEIGHT = 34.0;

static NSBundle *volumeBarBundle = [NSBundle bundleWithPath:BUNDLE_PATH];
static NSString *currentCategory;

%hook SBBannerController
%new
- (void)rescheduleTimers
{
	// cancel timers
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_replaceIntervalElapsed) object:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_dismissIntervalElapsed) object:nil];

	// restart timers
	[self performSelector:@selector(_replaceIntervalElapsed) withObject:nil afterDelay:REPLACE_INTERVAL_DELAY];
	[self performSelector:@selector(_dismissIntervalElapsed) withObject:nil afterDelay:DISMISS_INTERVAL_DELAY];
}

- (void)_setBannerSticky:(BOOL)sticky
{
	%orig;

	SBBulletinBannerItem *bannerItem = [self _bannerItem];
	NSString *sectionID = bannerItem.seedBulletin.sectionID;

	// don't delay if this banner is a volume banner
	if ([sectionID isEqualToString:BULLETIN_SLIDER_IDENTIFIER] || [sectionID isEqualToString:BULLETIN_RINGER_IDENTIFIER])
		MSHookIvar<BOOL>(self, "_replaceDelayIsActive") = NO;
}
%end

%subclass AlwaysWhiteSlider : SBUIControlCenterSlider
%new
- (void)setTrackVolumeChanges:(BOOL)trackVolumeChanges
{
	if (trackVolumeChanges)
		[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(volumeChanged:)
	                                             name:@"AVSystemController_SystemVolumeDidChangeNotification"
	                                           object:nil];
	else
		[[NSNotificationCenter defaultCenter] removeObserver:self
													name:@"AVSystemController_SystemVolumeDidChangeNotification"
												  object:nil];
}

- (void)setAdjusting:(BOOL)arg1
{
	// say it's always adjusting (forces icons to be white)
	%orig(YES);
}

- (void)_updateEffects { }

- (void)setMaximumTrackImage:(UIImage *)maxImage forState:(long long)state
{
	UIImage *image = self.currentMinimumTrackImage;
	%orig([image _flatImageWithWhite:0.5 alpha:0.8], state);
}

%new
- (void)volumeChanged:(NSNotification *)notification
{
	NSDictionary *dict = notification.userInfo;
	float newVolume = [[dict objectForKey:@"AVSystemController_AudioVolumeNotificationParameter"] floatValue];
	if (self.value != newVolume)
	{
		SBBannerController *bannerController = (SBBannerController *)[%c(SBBannerController) sharedInstance];
		[bannerController rescheduleTimers];

		self.value = newVolume;
	}
}
%end

%hook SBBannerContainerViewController
- (void)_handleBannerTapGesture:(id)gesture withActionContext:(id)action
{
	// if this isn't the volume banner, do what it wants to do
	SBBulletinBannerItem *bannerItem = [self _bannerItem];
	NSString *sectionID = bannerItem.seedBulletin.sectionID;
	if (![sectionID isEqualToString:BULLETIN_SLIDER_IDENTIFIER])
		%orig;
}
%end

%hook SBBannerContextView
- (void)_layoutContentView
{
	%orig;

	// get view, make sure it's a SBDefaultBannerView
	SBDefaultBannerView *contentView = MSHookIvar<SBDefaultBannerView *>(self, "_contentView");
	if (![contentView isKindOfClass:[%c(SBDefaultBannerView) class]])
		return;

	// make sure this is a ringer/slider banner
	NSString *sectionID = self.bannerContext.item.seedBulletin.sectionID;
	BOOL isRingerNotification = [sectionID isEqualToString:BULLETIN_RINGER_IDENTIFIER];
	BOOL isSliderNotification = [sectionID isEqualToString:BULLETIN_SLIDER_IDENTIFIER];
	if (!isSliderNotification && !isRingerNotification)
		return;

	CGRect contentViewFrame = contentView.frame;

	// calculate label frame
	CGRect labelFrame = CGRectMake(0, 5, CGRectGetWidth(contentViewFrame), 15);

	// calculate slider frame
	CGFloat sliderWidth = fmin(SLIDER_MAX_WIDTH, CGRectGetWidth(contentViewFrame) - 20);
	CGFloat sliderX = CGRectGetMidX(contentViewFrame) - (sliderWidth / 2);
	CGFloat sliderY = CGRectGetMidY(contentViewFrame) - (SLIDER_HEIGHT / 2);
	CGRect sliderFrame = CGRectMake(sliderX, sliderY, sliderWidth, SLIDER_HEIGHT);

	// calculate image view frame
	CGFloat ringerImageViewY = CGRectGetMaxY(labelFrame) + 2;
	CGFloat ringerImageViewSize = CGRectGetHeight(contentViewFrame) - ringerImageViewY - 10;
	CGFloat ringerImageViewX = CGRectGetMidX(contentViewFrame) - (ringerImageViewSize / 2);
	CGRect ringerImageViewFrame = CGRectMake(ringerImageViewX, ringerImageViewY, ringerImageViewSize, ringerImageViewSize);

	BOOL hideLabel = CGRectGetHeight(contentViewFrame) < 50.0;

	// update frames
	for (UIView *view in contentView.subviews)
	{
		if ([view isKindOfClass:[%c(AlwaysWhiteSlider) class]])
			view.frame = sliderFrame;
		else if ([view isKindOfClass:[UILabel class]])
		{
			if (hideLabel)
				view.hidden = YES;
			else
				view.hidden = NO;
			view.frame = labelFrame;
		}
		else if ([view isKindOfClass:[UIImageView class]])
		{
			UIImageView *imageView = (UIImageView *)view;
			imageView.frame = ringerImageViewFrame;
		}
	}
}
%end

%hook SBBannerContainerViewController
- (void)removeChildPullDownViewController:(id)viewController
{
	// get view, remove observer
	SBDefaultBannerView *contentView = MSHookIvar<SBDefaultBannerView *>(self.bannerContextView, "_contentView");
	if (contentView)
		[[NSNotificationCenter defaultCenter] removeObserver:contentView];

	%orig;
}
%end

%hook SBDefaultBannerView
%new
- (void)ringerChanged:(NSNotification *)notification
{
	// get ringer state
	SBMediaController *mediaController = (SBMediaController *)[%c(SBMediaController) sharedInstance];
	BOOL ringerMuted = [mediaController isRingerMuted];
	NSString *imageName;
	if (ringerMuted)
		imageName = @"ringer-silence";
	else
		imageName = @"ringer";

	// get image
	UIImage *image = [[UIImage imageNamed:imageName] _flatImageWithWhite:1 alpha:1];

	// update ringer image view
	for (UIView *view in self.subviews)
	{
		if ([view isKindOfClass:[UIImageView class]])
		{
			UIImageView *imageView = (UIImageView *)view;
			imageView.image = image;
			break;
		}
	}
}
%end

%hook SBBulletinBannerController
- (SBDefaultBannerView *)newBannerViewForContext:(SBUIBannerContext *)bannerContext
{
	SBDefaultBannerView *view = %orig;
	NSString *sectionID = bannerContext.item.seedBulletin.sectionID;

	BOOL isRingerNotification = [sectionID isEqualToString:BULLETIN_RINGER_IDENTIFIER];
	BOOL isSliderNotification = [sectionID isEqualToString:BULLETIN_SLIDER_IDENTIFIER];

	// check for the notification type
	if (isSliderNotification || isRingerNotification)
	{
		// hide time text
		SBDefaultBannerTextView *textView = MSHookIvar<SBDefaultBannerTextView *>(view, "_textView");
		textView.hidden = YES;

		// create label
		UILabel *label = [[UILabel alloc] init];
		label.font = [%c(SBDefaultBannerTextView) _primaryTextFont];
		label.textColor = [UIColor whiteColor];
		label.textAlignment = UITextAlignmentCenter;
		label.text = textView.primaryText;

		// add label view
		[view addSubview:label];

		if (isRingerNotification)
		{
			/*
				imageNamed:, strings

				ringer-silence, SILENT_VOLUME
				ringer
			*/

			SBMediaController *mediaController = (SBMediaController *)[%c(SBMediaController) sharedInstance];
			BOOL ringerMuted = [mediaController isRingerMuted];
			NSString *imageName;
			if (ringerMuted)
				imageName = @"ringer-silence";
			else
				imageName = @"ringer";

			UIImage *image = [[UIImage imageNamed:imageName] _flatImageWithWhite:1 alpha:1];
			UIImageView *ringerImageView = [[UIImageView alloc] initWithImage:image];
			ringerImageView.contentMode = UIViewContentModeScaleAspectFit;

			[[NSNotificationCenter defaultCenter] addObserver:view
	                                         selector:@selector(ringerChanged:)
	                                             name:@"SBRingerChangedNotification"
	                                           object:nil];

			// add image to view
			[view addSubview:ringerImageView];
		}
		else if (isSliderNotification)
		{
			// create slider
			AlwaysWhiteSlider *slider = [[%c(AlwaysWhiteSlider) alloc] init];
			slider.trackVolumeChanges = YES;

			[slider addTarget:self action:@selector(sliderTouchBegan:) forControlEvents:UIControlEventTouchDown];
			[slider addTarget:self action:@selector(sliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside];
			[slider addTarget:self action:@selector(sliderTouchEnded:) forControlEvents:UIControlEventTouchUpOutside];
			[slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];

			// get current volume
		    float volume = 0;
		    [[%c(AVSystemController) sharedAVSystemController] getVolume:&volume forCategory:currentCategory];

			slider.value = volume;

			// set slider images
			slider.minimumValueImage = [UIImage imageNamed:@"min" inBundle:volumeBarBundle compatibleWithTraitCollection:nil];
			slider.maximumValueImage = [UIImage imageNamed:@"max" inBundle:volumeBarBundle compatibleWithTraitCollection:nil];

			// set volume bounds [0, 1]
			slider.minimumValue = 0.0;
			slider.maximumValue = 1.0;

			// add view
			[view addSubview:slider];

			// make icons white
			slider.adjusting = YES;
		}
	}

	return view;
}

%new
- (void)sliderValueChanged:(AlwaysWhiteSlider *)sender
{
	// update volume
	[[%c(AVSystemController) sharedAVSystemController] setVolumeTo:sender.value forCategory:currentCategory];
}

%new
- (void)sliderTouchBegan:(AlwaysWhiteSlider *)sender
{
	sender.trackVolumeChanges = NO;

	// remove dismiss/replace timers
	[self removeTimers];
}

%new
- (void)sliderTouchEnded:(AlwaysWhiteSlider *)sender
{
	sender.trackVolumeChanges = YES;

	// add dismiss/replace timers
	[self addTimers];
}

%new
- (void)removeTimers
{
	SBBannerController *bannerController = (SBBannerController *)[%c(SBBannerController) sharedInstance];
	
	// cancel timers
	[NSObject cancelPreviousPerformRequestsWithTarget:bannerController selector:@selector(_replaceIntervalElapsed) object:nil];
	[NSObject cancelPreviousPerformRequestsWithTarget:bannerController selector:@selector(_dismissIntervalElapsed) object:nil];
}

%new
- (void)addTimers
{
	SBBannerController *bannerController = (SBBannerController *)[%c(SBBannerController) sharedInstance];

	// start timers
	[bannerController performSelector:@selector(_replaceIntervalElapsed) withObject:nil afterDelay:REPLACE_INTERVAL_DELAY];
	[bannerController performSelector:@selector(_dismissIntervalElapsed) withObject:nil afterDelay:DISMISS_INTERVAL_DELAY];
}
%end

%hook SBHUDController
- (void)presentHUDView:(id)view autoDismissWithDelay:(double)delay
{
	BOOL isRingerView = [view isKindOfClass:[%c(SBRingerHUDView) class]];

	// if it's locked or not what we're looking for, let it do what it wants to do
	if ([%c(SBLockScreenManager) sharedInstance].isUILocked || !isRingerView)
	{
		%orig;
		return;
	}

	// get current banner
	SBBannerController *bannerController = (SBBannerController *)[%c(SBBannerController) sharedInstance];
	SBBulletinBannerItem *bannerItem = [bannerController _bannerItem];
	NSString *sectionID = bannerItem.seedBulletin.sectionID;

	// check if already showing
	if (![sectionID isEqualToString:BULLETIN_RINGER_IDENTIFIER])
	{
		// get category and localized string key
		NSBundle *bundle = [NSBundle mainBundle];
		NSString *key;
		if ([%c(VolumeControl) sharedVolumeControl].headphonesPresent)
			key = @"HEADPHONES_VOLUME";
		else
			key = @"RINGER_VOLUME";

		// create request
		BBBulletinRequest *request = [[%c(BBBulletinRequest) alloc] init];
		request.bulletinID = BULLETIN_RINGER_IDENTIFIER;
		request.sectionID = BULLETIN_RINGER_IDENTIFIER;
		request.title = [bundle localizedStringForKey:key value:@"" table:@"SpringBoard"];
		request.defaultAction = [%c(BBAction) action];

		// add bulletin request
		SBBulletinBannerController *bulletinBannerController = (SBBulletinBannerController *)[%c(SBBulletinBannerController) sharedInstance];
		[bulletinBannerController observer:nil addBulletin:request forFeed:2];
	}
	else
		[bannerController rescheduleTimers];
}
%end

%hook VolumeControl
- (void)_presentVolumeHUDWithMode:(int)mode volume:(float)volume
{
	// get current banner
	SBBannerController *bannerController = (SBBannerController *)[%c(SBBannerController) sharedInstance];
	SBBulletinBannerItem *bannerItem = [bannerController _bannerItem];
	NSString *sectionID = bannerItem.seedBulletin.sectionID;

	// check if already showing
	if (![sectionID isEqualToString:BULLETIN_SLIDER_IDENTIFIER])
	{
		// get category and localized string key
		NSBundle *bundle = [NSBundle mainBundle];
		NSString *key;
		if (mode == 1)
		{
			key = @"RINGER_VOLUME";
			currentCategory = @"Ringtone";
		}
		else
		{
			key = @"VOLUME_VOLUME";
			currentCategory = @"Audio/Video";
		}

		// create request
		BBBulletinRequest *request = [[%c(BBBulletinRequest) alloc] init];
		request.bulletinID = BULLETIN_SLIDER_IDENTIFIER;
		request.sectionID = BULLETIN_SLIDER_IDENTIFIER;
		request.title = [bundle localizedStringForKey:key value:@"" table:@"SpringBoard"];
		request.defaultAction = [%c(BBAction) action];

		// add bulletin request
		SBBulletinBannerController *bulletinBannerController = (SBBulletinBannerController *)[%c(SBBulletinBannerController) sharedInstance];
		[bulletinBannerController observer:nil addBulletin:request forFeed:2];
	}
	else
		[bannerController rescheduleTimers];
}
%end
