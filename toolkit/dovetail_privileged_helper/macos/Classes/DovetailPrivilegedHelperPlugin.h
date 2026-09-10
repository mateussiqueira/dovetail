#import <FlutterMacOS/FlutterMacOS.h>

/*
 * The macOS half of dovetail_privileged_helper: SMAppService behind a method
 * channel.
 *
 * A channel and not a C ABI, unlike the other native code in this toolkit.
 * SMAppService answers with an NSError explaining why a registration was
 * refused, and Apple's sentence is better than anything this package would
 * invent to replace it. Flattening that into an integer would throw away the
 * one part of the answer a person can act on.
 */
@interface DovetailPrivilegedHelperPlugin : NSObject <FlutterPlugin>
@end
