#import "Headers.h"

#define BUNDLE_PATH @"/Library/Application Support/VolumeBar/VolumeBar.bundle"
#define BULLETIN_IDENTIFIER @"volumebar.expetelek.com"

static const NSInteger DISMISS_INTERVAL_DELAY = 7.0;
static const NSInteger REPLACE_INTERVAL_DELAY = 5.0;
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
%end

%subclass AlwaysWhiteSlider : SBUIControlCenterSlider
- (AlwaysWhiteSlider *)init
{
	self = %orig;

	[[NSNotificationCenter defaultCenter] addObserver:self
	                                         selector:@selector(volumeChanged:)
	                                             name:@"AVSystemController_SystemVolumeDidChangeNotification"
	                                           object:nil];

	return self;
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
	self.value = newVolume;
}
%end

%hook SBBannerContainerViewController
- (void)_handleBannerTapGesture:(id)gesture withActionContext:(id)action
{
	// _bannerItem
	// if there's no action, there's no point in closing it
	if (action != nil)
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

	CGRect contentViewFrame = contentView.frame;

	// calculate label frame
	CGRect labelFrame = CGRectMake(0, 5, CGRectGetWidth(contentViewFrame), 15);

	// calculate slider frame
	CGFloat sliderWidth = fmin(SLIDER_MAX_WIDTH, CGRectGetWidth(contentViewFrame) - 20);
	CGFloat sliderX = CGRectGetMidX(contentViewFrame) - (sliderWidth / 2);
	CGFloat sliderY = CGRectGetMidY(contentViewFrame) - SLIDER_HEIGHT / 2;

	CGRect sliderFrame = CGRectMake(sliderX, sliderY, sliderWidth, SLIDER_HEIGHT);

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
	}
}
%end

%hook SBBulletinBannerController
- (SBDefaultBannerView *)newBannerViewForContext:(SBUIBannerContext *)bannerContext
{
	SBDefaultBannerView *view = %orig;

	// make sure this is a volume notification
	if (![bannerContext.item.seedBulletin.sectionID isEqualToString:BULLETIN_IDENTIFIER])
		return view;

	// hide time text
	SBDefaultBannerTextView *textView = MSHookIvar<SBDefaultBannerTextView *>(view, "_textView");
	textView.hidden = YES;

	// create label
	UILabel *label = [[UILabel alloc] init];
	label.font = [%c(SBDefaultBannerTextView) _primaryTextFont];
	label.textColor = [UIColor whiteColor];
	label.textAlignment = UITextAlignmentCenter;
	label.text = textView.primaryText;

	// create slider
	AlwaysWhiteSlider *slider = [[%c(AlwaysWhiteSlider) alloc] init];
	[slider addTarget:self action:@selector(sliderTouchBegan:) forControlEvents:UIControlEventTouchDown];
	[slider addTarget:self action:@selector(sliderTouchEnded:) forControlEvents:UIControlEventTouchUpInside];
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

	// add views
	[view addSubview:slider];
	[view addSubview:label];

	// make icons white
	slider.adjusting = YES;

	return view;
}

%new
- (void)sliderValueChanged:(UISlider *)sender
{
	// set volume (on a new thread)
	[[%c(AVSystemController) sharedAVSystemController] setVolumeTo:sender.value forCategory:currentCategory];
}

%new
- (void)sliderTouchBegan:(UISlider *)sender
{
	[[NSNotificationCenter defaultCenter] removeObserver:sender
													name:@"AVSystemController_SystemVolumeDidChangeNotification"
												  object:nil];
	
	// remove dismiss/replace timers
	[self removeTimers];
}

%new
- (void)sliderTouchEnded:(UISlider *)sender
{
	[[NSNotificationCenter defaultCenter] addObserver:sender
	                                         selector:@selector(volumeChanged:)
	                                             name:@"AVSystemController_SystemVolumeDidChangeNotification"
	                                           object:nil];

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

%hook VolumeControl
- (void)_presentVolumeHUDWithMode:(int)mode volume:(float)volume
{
	// get current banner
	SBBannerController *bannerController = (SBBannerController *)[%c(SBBannerController) sharedInstance];
	SBBulletinBannerItem *bannerItem = [bannerController _bannerItem];
	NSString *sectionID = bannerItem.seedBulletin.sectionID;

	// check if already showing
	if (![sectionID isEqualToString:BULLETIN_IDENTIFIER])
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
		request.title = [bundle localizedStringForKey:key value:@"" table:@"SpringBoard"];
		request.sectionID = BULLETIN_IDENTIFIER;
		request.defaultAction = [%c(BBAction) action];

		// add bulletin request
		SBBulletinBannerController *bulletinBannerController = (SBBulletinBannerController *)[%c(SBBulletinBannerController) sharedInstance];
		[bulletinBannerController observer:nil addBulletin:request forFeed:2];
	}
	else
		[bannerController rescheduleTimers];
}
%end
