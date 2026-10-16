import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _storage.remove(key);
    } else {
      _storage[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.clear();
  }

  @override
  Future<bool> containsKey({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _storage.containsKey(key);
  }

  @override
  Future<Map<String, String>> readAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return Map<String, String>.from(_storage);
  }
}

class FakeWebSocketChannel extends StreamChannelMixin<dynamic> implements WebSocketChannel {
  final StreamController<dynamic> incoming = StreamController<dynamic>.broadcast();
  final StreamController<dynamic> outgoing = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _FakeWebSocketSink(outgoing);

  @override
  String? get closeReason => null;

  @override
  int? get closeCode => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamController<dynamic> controller;
  _FakeWebSocketSink(this.controller);

  @override
  void add(dynamic data) => controller.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      controller.addError(error, stackTrace);

  @override
  Future addStream(Stream<dynamic> stream) => controller.addStream(stream);

  @override
  Future close([int? closeCode, String? closeReason]) => controller.close();

  @override
  Future get done => controller.done;
}
