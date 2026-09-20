#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) return 2;
        [NSApplication sharedApplication];
        NSBundle *bundle = [NSBundle bundleWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSError *error = nil;
        if (![bundle loadAndReturnError:&error]) {
            NSLog(@"Plugin load failed: %@", error);
            return 1;
        }
        id<NSDockTilePlugIn> plugin = [[bundle principalClass] new];
        if (![plugin conformsToProtocol:@protocol(NSDockTilePlugIn)]) return 1;
        NSDockTile *tile = NSApplication.sharedApplication.dockTile;
        [plugin setDockTile:tile];
        if (![tile.contentView isKindOfClass:NSImageView.class]) return 1;
        NSImage *actual = ((NSImageView *)tile.contentView).image;
        CFPreferencesAppSynchronize(CFSTR("com.hidig.focus"));
        NSString *style = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("appIconPreference"), CFSTR("com.hidig.focus")));
        NSArray *styles = @[@"green", @"light", @"dark", @"rose", @"purple", @"aurora", @"blue", @"amber"];
        if (![styles containsObject:style ?: @""]) style = @"green";
        NSImage *expected = [[NSImage alloc] initWithContentsOfURL:[bundle URLForResource:style withExtension:@"png"]];
        if (!actual || ![actual.TIFFRepresentation isEqualToData:expected.TIFFRepresentation]) return 1;
        // The plugin must tolerate macOS removing and attaching a tile again.
        [plugin setDockTile:nil];
        [plugin setDockTile:tile];
        if (!((NSImageView *)tile.contentView).image) return 1;
        [plugin setDockTile:nil];
        printf("Dock plugin loaded independently and restored saved icon: %s\n", style.UTF8String);
    }
    return 0;
}
