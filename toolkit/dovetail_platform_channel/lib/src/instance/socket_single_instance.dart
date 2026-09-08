import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dovetail_platform_channel/src/instance/forwarded_launch.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance.dart';
import 'package:dovetail_platform_channel/src/instance/single_instance_verdict.dart';
import 'package:path/path.dart' as p;

const String _fieldSeparator = '\u0000\u0000';
const String _argumentSeparator = '\u0000';

final class SocketSingleInstance implements SingleInstance {
  SocketSingleInstance({required this.instanceKey, String? directory})
    : _directory = directory ?? Directory.systemTemp.path;

  final String instanceKey;
  final String _directory;

  final StreamController<ForwardedLaunch> _launches =
      StreamController<ForwardedLaunch>.broadcast();

  ServerSocket? _listener;

  String get socketPath => p.join(
    _directory,
    '${instanceKey.replaceAll(RegExp('[.-]'), '_')}_si.sock',
  );

  @override
  Stream<ForwardedLaunch> launches() => _launches.stream;

  @override
  Future<SingleInstanceVerdict> claim({
    List<String> arguments = const <String>[],
    String? workingDirectory,
  }) async {
    final InternetAddress address = InternetAddress(
      socketPath,
      type: InternetAddressType.unix,
    );

    try {
      final Socket peer = await Socket.connect(address, 0);
      peer.write(
        _encode(
          arguments: arguments,
          workingDirectory: workingDirectory ?? Directory.current.path,
        ),
      );
      await peer.flush();
      await peer.close();
      return SingleInstanceVerdict.secondary;
    } on SocketException {
      await _takeOver(address);
      return SingleInstanceVerdict.primary;
    }
  }

  @override
  Future<void> release() async {
    await _listener?.close();
    _listener = null;
    final File socket = File(socketPath);
    if (socket.existsSync()) {
      socket.deleteSync();
    }
  }

  @override
  Future<void> dispose() async {
    await release();
    await _launches.close();
  }

  Future<void> _takeOver(InternetAddress address) async {
    final File stale = File(socketPath);
    if (stale.existsSync()) {
      stale.deleteSync();
    }

    _listener = await ServerSocket.bind(address, 0);
    _listener!.listen(_onPeer);
  }

  void _onPeer(Socket peer) {
    utf8.decoder
        .bind(peer)
        .join()
        .then((String payload) {
          if (_launches.isClosed) {
            return;
          }
          _launches.add(decode(payload));
        })
        .catchError((Object _) {});
  }

  String _encode({
    required List<String> arguments,
    required String workingDirectory,
  }) =>
      '$workingDirectory$_fieldSeparator${arguments.join(_argumentSeparator)}';

  static ForwardedLaunch decode(String payload) {
    final int split = payload.indexOf(_fieldSeparator);
    if (split < 0) {
      return ForwardedLaunch(
        workingDirectory: payload,
        arguments: const <String>[],
      );
    }

    final String directory = payload.substring(0, split);
    final String rest = payload.substring(split + _fieldSeparator.length);

    return ForwardedLaunch(
      workingDirectory: directory,
      arguments: rest.isEmpty
          ? const <String>[]
          : rest.split(_argumentSeparator),
    );
  }
}
