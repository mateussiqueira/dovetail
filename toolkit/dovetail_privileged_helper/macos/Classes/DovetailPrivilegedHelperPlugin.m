#import "DovetailPrivilegedHelperPlugin.h"

#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>

/* Spelled identically in DarwinDaemonHelper.channelName. */
static NSString *const kDovetailHelperChannel = @"dovetail_privileged_helper";

/*
 * The wire contract, which the Dart side reads in DarwinServiceStatus.
 *
 * At most one of these three keys carries the answer: `raw` is a status this
 * code actually read from SMAppService, `unsupported` is a macOS with no such
 * class, `error` is Apple's own sentence about a call that failed. `raw` and
 * `error` arrive together when a registration fails and the status is still
 * readable — losing either half there would lose either what went wrong or
 * where the daemon now stands.
 */
static NSString *const kRaw = @"raw";
static NSString *const kUnsupported = @"unsupported";
static NSString *const kError = @"error";
static NSString *const kOpened = @"opened";

@implementation DovetailPrivilegedHelperPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMethodChannel *channel =
      [FlutterMethodChannel methodChannelWithName:kDovetailHelperChannel
                                  binaryMessenger:registrar.messenger];
  DovetailPrivilegedHelperPlugin *instance =
      [[DovetailPrivilegedHelperPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall *)call
                  result:(FlutterResult)result {
  if ([call.method isEqualToString:@"openApprovalSettings"]) {
    result([self openApprovalSettings:[self stringArgument:call named:@"uri"]]);
    return;
  }

  NSString *plistName = [self stringArgument:call named:@"plist"];
  if (plistName.length == 0) {
    result(@{
      kError : @"the Dart side sent no property list name, so no daemon was "
               @"named to ask about"
    });
    return;
  }

  /*
   * The version check lives here rather than in Dart on purpose. The only
   * reading of the OS version worth trusting is the one the compiler and the
   * loader agree on; the Dart alternative is parsing
   * Platform.operatingSystemVersion, a human-readable string whose shape
   * Apple has changed before.
   *
   * Before 13 the route was SMJobBless, which is a different flow with no
   * approval state, a helper signed into a separate bundle, and a deprecation
   * warning. Reporting "unsupported" is not this package giving up: it is the
   * honest answer, because the state machine the Dart side describes does not
   * exist on those systems.
   */
  if (@available(macOS 13.0, *)) {
    SMAppService *service = [SMAppService daemonServiceWithPlistName:plistName];

    if ([call.method isEqualToString:@"status"]) {
      result(@{kRaw : @(service.status)});
      return;
    }
    if ([call.method isEqualToString:@"register"]) {
      result([self perform:^BOOL(NSError **error) {
        return [service registerAndReturnError:error];
      }
                 onService:service]);
      return;
    }
    if ([call.method isEqualToString:@"unregister"]) {
      result([self perform:^BOOL(NSError **error) {
        return [service unregisterAndReturnError:error];
      }
                 onService:service]);
      return;
    }
    result(FlutterMethodNotImplemented);
    return;
  }

  result(@{
    kUnsupported :
        @"this macOS is older than 13, where SMAppService arrived. The route "
        @"here would be SMJobBless, which has no approval state and a "
        @"different install shape, and this package does not pretend to it."
  });
}

/*
 * Runs one SMAppService call and reports the status it left behind.
 *
 * The status is read AFTER the call, never assumed from its return value.
 * A successful register does not mean enabled: on macOS 13 it means the
 * daemon is now registered and waiting for a human in Login Items, and a
 * plugin that answered "enabled" because the call returned YES would be the
 * source of exactly the lie this package exists to remove.
 */
- (NSDictionary *)perform:(BOOL (^)(NSError **error))action
                onService:(SMAppService *)service API_AVAILABLE(macos(13.0)) {
  NSError *error = nil;
  BOOL succeeded = action(&error);
  NSMutableDictionary *reply = [NSMutableDictionary dictionary];
  reply[kRaw] = @(service.status);
  if (!succeeded) {
    reply[kError] = error.localizedDescription
                        ?: @"the call failed and macOS gave no reason";
  }
  return reply;
}

/*
 * Brings up the pane where the daemon is switched on.
 *
 * The URL comes from Dart, and the fallback exists because it is
 * undocumented: Apple has never published the System Settings pane
 * identifiers, and they have moved between releases. When the URL stops
 * resolving, openSystemSettingsLoginItems is the supported call that lands in
 * the same place. It is the fallback and not the primary because it can only
 * ever open Login Items, and a second backend approves somewhere else — a
 * Network Extension asks in Network, not here.
 */
- (NSDictionary *)openApprovalSettings:(NSString *)uri {
  BOOL opened = NO;
  if (uri.length > 0) {
    NSURL *url = [NSURL URLWithString:uri];
    if (url != nil) {
      opened = [[NSWorkspace sharedWorkspace] openURL:url];
    }
  }
  if (!opened) {
    if (@available(macOS 13.0, *)) {
      [SMAppService openSystemSettingsLoginItems];
      opened = YES;
    }
  }
  return @{kOpened : @(opened)};
}

- (NSString *)stringArgument:(FlutterMethodCall *)call named:(NSString *)key {
  if (![call.arguments isKindOfClass:[NSDictionary class]]) {
    return nil;
  }
  id value = ((NSDictionary *)call.arguments)[key];
  return [value isKindOfClass:[NSString class]] ? value : nil;
}

@end
