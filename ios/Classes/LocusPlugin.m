#import "LocusPlugin.h"
#if __has_include(<locus/locus-Swift.h>)
#import <locus/locus-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "locus-Swift.h"
#endif

@implementation LocusPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftLocusPlugin registerWithRegistrar:registrar];
}
@end
