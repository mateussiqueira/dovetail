import 'package:dovetail_shortcut_channel/src/global_shortcut_surface.dart';
import 'package:dovetail_shortcut_channel/src/session_probe.dart';
import 'package:dovetail_shortcut_channel/src/shortcut_refusal.dart';

final class DisabledShortcutSurface implements GlobalShortcutSurface {
  const DisabledShortcutSurface(this.support, this.reason);

  @override
  final ShortcutSupport support;

  final ShortcutRefusal reason;

  @override
  Stream<ShortcutPress> presses() => const Stream<ShortcutPress>.empty();

  @override
  Future<List<ShortcutOutcome>> bind(List<ShortcutRequest> requests) async =>
      requests
          .map(
            (ShortcutRequest request) => ShortcutRefused(
              request.name,
              reason,
              support.unavailableBecause ??
                  'this session has no system-wide shortcut surface',
            ),
          )
          .toList(growable: false);

  @override
  Future<void> release(String name) async {}

  @override
  Future<void> releaseAll() async {}

  @override
  Future<void> dispose() async {}
}
