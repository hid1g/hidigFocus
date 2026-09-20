#import <Cocoa/Cocoa.h>

// Loaded by macOS independently of the application process.
@interface HFIconDockTilePlugin : NSObject <NSDockTilePlugIn>
@property(nonatomic, strong) NSDockTile *tile;
@end

@implementation HFIconDockTilePlugin
- (void)setDockTile:(NSDockTile *)dockTile {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
    self.tile = dockTile;
    if (!dockTile) return;
    [[NSDistributedNotificationCenter defaultCenter]
        addObserver:self selector:@selector(iconChanged:)
        name:@"com.hidig.focus.iconChanged" object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
    [self updateIcon];
}

- (void)iconChanged:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateIcon]; });
}

- (void)updateIcon {
    if (!self.tile) return;
    CFPreferencesAppSynchronize(CFSTR("com.hidig.focus"));
    NSString *style = CFBridgingRelease(CFPreferencesCopyAppValue(
        CFSTR("appIconPreference"), CFSTR("com.hidig.focus")));
    NSArray *styles = @[@"green", @"light", @"dark", @"rose", @"purple", @"aurora", @"blue", @"amber"];
    if (![style isKindOfClass:NSString.class] || ![styles containsObject:style]) style = @"green";
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSURL *url = [bundle URLForResource:style withExtension:@"png"];
    NSImage *image = [[NSImage alloc] initWithContentsOfURL:url];
    if (!image) return;
    NSImageView *view = [[NSImageView alloc] initWithFrame:NSMakeRect(0, 0, 128, 128)];
    view.image = image;
    view.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.tile.contentView = view;
    [self.tile display];
}

- (void)dealloc {
    [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
}
@end
