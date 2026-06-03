import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../shared/models/media_item.dart';
import 'discord_rpc_models.dart';

export 'discord_rpc_models.dart';

class DiscordRpcService {
  DiscordRpcService._();

  static const Duration _connectCooldown = Duration(seconds: 8);

  static _DiscordIpcClient? _client;
  static DiscordRpcPresence? _lastPresence;
  static DateTime? _lastConnectFailureAt;
  static bool _appEnabled = true;
  static bool _playerEnabled = true;

  static bool get isSupported =>
      !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);

  static Future<void> configure({
    required bool appEnabled,
    required bool playerEnabled,
  }) async {
    _appEnabled = appEnabled;
    _playerEnabled = playerEnabled;

    if (!_effectiveEnabled) {
      await clearActivity();
      return;
    }

    final DiscordRpcPresence? lastPresence = _lastPresence;
    if (lastPresence != null) {
      await updatePresence(lastPresence);
    }
  }

  static Future<void> updatePresence(DiscordRpcPresence presence) async {
    _lastPresence = presence;
    if (!isSupported || !_effectiveEnabled) {
      return;
    }

    final bool connected = await _ensureConnected();
    if (!connected) {
      return;
    }

    try {
      await _client?.setActivity(_buildActivity(presence));
    } on Object {
      _lastConnectFailureAt = DateTime.now();
      await _closeClient();
    }
  }

  static Future<void> clearActivity() async {
    _lastPresence = null;
    final _DiscordIpcClient? client = _client;
    if (client != null) {
      try {
        await client.setActivity(null);
      } on Object {
        // Discord may already be closed; ignore.
      }
    }
    await _closeClient();
  }

  static Future<void> dispose() async {
    _lastPresence = null;
    _appEnabled = true;
    _playerEnabled = true;
    await _closeClient();
  }

  static bool get _effectiveEnabled => _appEnabled && _playerEnabled;

  static Future<bool> _ensureConnected() async {
    if (!isSupported) {
      return false;
    }

    final _DiscordIpcClient? existing = _client;
    if (existing != null && existing.isConnected) {
      return true;
    }

    final DateTime now = DateTime.now();
    final DateTime? lastFailure = _lastConnectFailureAt;
    if (lastFailure != null && now.difference(lastFailure) < _connectCooldown) {
      return false;
    }

    final _DiscordIpcClient client = _DiscordIpcClient(
      applicationId: AppConstants.discordRpcApplicationId,
      onClosed: () {
        _lastConnectFailureAt = DateTime.now();
        _client = null;
      },
    );

    try {
      await client.connect();
      _client = client;
      _lastConnectFailureAt = null;
      return true;
    } on Object {
      _lastConnectFailureAt = now;
      await client.close();
      return false;
    }
  }

  static Future<void> _closeClient() async {
    final _DiscordIpcClient? client = _client;
    _client = null;
    await client?.close();
  }

  static _DiscordActivity _buildActivity(DiscordRpcPresence presence) {
    final String details = _truncate(presence.title, 128);
    final String state = _truncate(_stateLabel(presence), 128);
    final String mediaUrl = _normalizedMediaUrl(presence.mediaUrl);
    final String posterUrl = _normalizedMediaUrl(presence.posterUrl);
    final String largeImage = posterUrl.isNotEmpty
        ? posterUrl
        : AppConstants.discordRpcLogoImageUrl;

    final _DiscordActivityTimestamps? timestamps = presence.isPlaying
        ? _buildTimestamps(presence.position, presence.duration)
        : null;

    return _DiscordActivity(
      name: AppConstants.appName,
      type: 3,
      details: details,
      detailsUrl: mediaUrl.isEmpty ? null : mediaUrl,
      state: state,
      stateUrl: mediaUrl.isEmpty ? null : mediaUrl,
      timestamps: timestamps,
      assets: _DiscordActivityAssets(
        largeImage: largeImage,
        largeText: details,
        largeUrl: AppConstants.appWebsiteUrl,
        smallImage: AppConstants.discordRpcLogoImageUrl,
        smallText: AppConstants.appName,
        smallUrl: AppConstants.appWebsiteUrl,
      ),
      buttons: <_DiscordActivityButton>[
        const _DiscordActivityButton(
          label: 'Visit Website',
          url: AppConstants.appWebsiteUrl,
        ),
        const _DiscordActivityButton(
          label: 'Download MiruShin',
          url: AppConstants.githubLatestReleaseUrl,
        ),
      ],
    );
  }

  static _DiscordActivityTimestamps? _buildTimestamps(
    Duration position,
    Duration duration,
  ) {
    final Duration safePosition = position < Duration.zero
        ? Duration.zero
        : position;
    final DateTime start = DateTime.now().subtract(safePosition);
    final DateTime? end = duration > Duration.zero ? start.add(duration) : null;
    return _DiscordActivityTimestamps(start: start, end: end);
  }

  static String _stateLabel(DiscordRpcPresence presence) {
    if (presence.mediaType == MediaType.movie) {
      return 'Movie';
    }

    final String episode = _episodeLabel(
      presence.episodeNumber,
      presence.episodeCount,
    );
    if (episode.isEmpty) {
      return presence.mediaType == MediaType.anime ? 'Anime' : 'TV Show';
    }

    return episode;
  }

  static String _episodeLabel(double episodeNumber, int? episodeCount) {
    if (episodeNumber <= 0) {
      return '';
    }
    final String number = _displayEpisodeNumber(episodeNumber);
    final String total = episodeCount != null && episodeCount > 0
        ? episodeCount.toString()
        : '?';
    return 'Episode $number of $total';
  }

  static String _displayEpisodeNumber(double episodeNumber) {
    if (episodeNumber == episodeNumber.roundToDouble()) {
      return episodeNumber.round().toString();
    }
    return episodeNumber.toString();
  }

  static String _normalizedMediaUrl(String? raw) {
    final String trimmed = raw?.trim() ?? '';
    if (trimmed.isEmpty) {
      return '';
    }
    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) {
      return '';
    }
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return '';
    }
    return uri.toString();
  }

  static String _truncate(String value, int maxLength) {
    final String trimmed = value.trim();
    if (trimmed.length <= maxLength) {
      return trimmed;
    }
    if (maxLength <= 3) {
      return trimmed.substring(0, maxLength);
    }
    return '${trimmed.substring(0, maxLength - 3)}...';
  }
}

class _DiscordIpcClient {
  _DiscordIpcClient({
    required this.applicationId,
    required this.onClosed,
  });

  final String applicationId;
  final void Function() onClosed;

  _DiscordTransport? _transport;
  StreamSubscription<_DiscordFrame>? _subscription;
  bool _closed = false;

  bool get isConnected => _transport != null && !_closed;

  Future<void> connect() async {
    final _DiscordTransport transport = _DiscordTransport.create();
    await transport.connect();
    _closed = false;
    _transport = transport;
    _subscription = transport.frames.listen(_handleFrame, onDone: _handleClose);
    await transport.send(
      const <String, Object?>{'v': 1},
      opcode: _DiscordOpcode.handshake,
      extra: <String, Object?>{'client_id': applicationId},
    );
  }

  Future<void> setActivity(_DiscordActivity? activity) async {
    final _DiscordTransport? transport = _transport;
    if (transport == null || _closed) {
      throw StateError('Discord IPC is not connected.');
    }
    await transport.sendCommand(
      'SET_ACTIVITY',
      <String, Object?>{
        'pid': pid,
        'activity': activity?.toJson(),
      },
    );
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    final _DiscordTransport? transport = _transport;
    _transport = null;
    await transport?.close();
  }

  void _handleFrame(_DiscordFrame frame) {
    if (frame.opcode == _DiscordOpcode.ping) {
      unawaited(_transport?.send(frame.payload, opcode: _DiscordOpcode.pong));
      return;
    }

    if (frame.opcode == _DiscordOpcode.close ||
        frame.payload['evt'] == 'ERROR') {
      unawaited(close());
      onClosed();
    }
  }

  void _handleClose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _transport = null;
    onClosed();
  }
}

enum _DiscordOpcode { handshake, frame, close, ping, pong }

class _DiscordFrame {
  const _DiscordFrame({
    required this.opcode,
    required this.payload,
  });

  final _DiscordOpcode opcode;
  final Map<String, dynamic> payload;
}

class _DiscordFrameParser {
  Uint8List _buffer = Uint8List(0);

  List<_DiscordFrame> addChunk(Uint8List chunk) {
    final Uint8List merged = Uint8List(_buffer.length + chunk.length)
      ..setRange(0, _buffer.length, _buffer)
      ..setRange(_buffer.length, _buffer.length + chunk.length, chunk);

    final List<_DiscordFrame> frames = <_DiscordFrame>[];
    int offset = 0;

    while (merged.length - offset >= 8) {
      final ByteData header = ByteData.sublistView(merged, offset, offset + 8);
      final int opcodeValue = header.getInt32(0, Endian.little);
      final int payloadLength = header.getInt32(4, Endian.little);
      if (payloadLength < 0 || merged.length - offset - 8 < payloadLength) {
        break;
      }

      final _DiscordOpcode? opcode = _opcodeFromValue(opcodeValue);
      final int payloadStart = offset + 8;
      final int payloadEnd = payloadStart + payloadLength;
      if (opcode != null) {
        try {
          final Object? decoded = jsonDecode(
            utf8.decode(merged.sublist(payloadStart, payloadEnd)),
          );
          if (decoded is Map<String, dynamic>) {
            frames.add(_DiscordFrame(opcode: opcode, payload: decoded));
          }
        } on Object {
          // Ignore malformed frames so the next valid update can recover.
        }
      }

      offset = payloadEnd;
    }

    _buffer = offset >= merged.length
        ? Uint8List(0)
        : Uint8List.fromList(merged.sublist(offset));
    return frames;
  }

  _DiscordOpcode? _opcodeFromValue(int value) {
    return switch (value) {
      0 => _DiscordOpcode.handshake,
      1 => _DiscordOpcode.frame,
      2 => _DiscordOpcode.close,
      3 => _DiscordOpcode.ping,
      4 => _DiscordOpcode.pong,
      _ => null,
    };
  }
}

abstract class _DiscordTransport {
  _DiscordTransport();

  final StreamController<_DiscordFrame> _frames =
      StreamController<_DiscordFrame>.broadcast();
  final _DiscordFrameParser _parser = _DiscordFrameParser();
  bool _finished = false;

  Stream<_DiscordFrame> get frames => _frames.stream;

  static _DiscordTransport create() {
    if (Platform.isWindows) {
      return _DiscordWindowsTransport();
    }
    return _DiscordUnixTransport();
  }

  Future<void> connect();

  Future<void> send(
    Map<String, Object?> payload, {
    required _DiscordOpcode opcode,
    Map<String, Object?> extra = const <String, Object?>{},
  });

  Future<void> sendCommand(
    String command,
    Map<String, Object?> args,
  ) {
    return send(
      <String, Object?>{
        'cmd': command,
        'args': args,
        'nonce': DateTime.now().microsecondsSinceEpoch.toString(),
      },
      opcode: _DiscordOpcode.frame,
    );
  }

  Future<void> close();

  @protected
  void pushChunk(Uint8List chunk) {
    if (_finished || _frames.isClosed) {
      return;
    }
    for (final _DiscordFrame frame in _parser.addChunk(chunk)) {
      if (_finished || _frames.isClosed) {
        return;
      }
      _frames.add(frame);
    }
  }

  @protected
  void finish() {
    if (_finished) {
      return;
    }
    _finished = true;
    if (!_frames.isClosed) {
      _frames.close();
    }
  }

  Uint8List encode(_DiscordOpcode opcode, Map<String, Object?> payload) {
    final List<int> jsonBytes = utf8.encode(jsonEncode(payload));
    final Uint8List buffer = Uint8List(8 + jsonBytes.length);
    final ByteData header = ByteData.sublistView(buffer);
    header.setInt32(0, opcode.index, Endian.little);
    header.setInt32(4, jsonBytes.length, Endian.little);
    buffer.setRange(8, 8 + jsonBytes.length, jsonBytes);
    return buffer;
  }
}

class _DiscordUnixTransport extends _DiscordTransport {
  Socket? _socket;

  @override
  Future<void> connect() async {
    _socket = await _openSocket();
    final Socket? socket = _socket;
    if (socket == null) {
      throw StateError("Couldn't connect to Discord IPC.");
    }

    socket.listen(
      pushChunk,
      onDone: finish,
      onError: (_) => finish(),
      cancelOnError: true,
    );
  }

  @override
  Future<void> send(
    Map<String, Object?> payload, {
    required _DiscordOpcode opcode,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final Socket? socket = _socket;
    if (socket == null) {
      throw StateError('Discord IPC socket is closed.');
    }
    socket.add(encode(opcode, <String, Object?>{...payload, ...extra}));
    await socket.flush();
  }

  @override
  Future<void> close() async {
    final Socket? socket = _socket;
    _socket = null;
    try {
      socket?.add(encode(_DiscordOpcode.close, const <String, Object?>{}));
      await socket?.flush();
    } on Object {
      // Ignore close errors.
    }
    await socket?.close();
    finish();
  }

  Future<Socket?> _openSocket() async {
    for (int index = 0; index < 10; index += 1) {
      try {
        final InternetAddress address = InternetAddress(
          _socketPath(index),
          type: InternetAddressType.unix,
        );
        return await Socket.connect(
          address,
          0,
          timeout: const Duration(seconds: 2),
        );
      } on Object {
        continue;
      }
    }
    return null;
  }

  String _socketPath(int index) {
    final Map<String, String> env = Platform.environment;
    final String prefix = switch (env) {
      {'XDG_RUNTIME_DIR': final String value} => value,
      {'TMPDIR': final String value} => value,
      {'TMP': final String value} => value,
      {'TEMP': final String value} => value,
      _ => '/tmp',
    };
    return '$prefix/discord-ipc-$index';
  }
}

class _DiscordWindowsTransport extends _DiscordTransport {
  RandomAccessFile? _file;

  @override
  Future<void> connect() async {
    _file = await _openPipe();
    if (_file == null) {
      throw StateError("Couldn't connect to Discord IPC.");
    }
    // The pipe is opened write-only (FileMode.write). Starting a concurrent
    // read loop on the same handle causes "async operation is currently
    // pending" exceptions. Discord accepts presence updates without us
    // reading the ACK frames, so we skip the read loop entirely.
  }

  @override
  Future<void> send(
    Map<String, Object?> payload, {
    required _DiscordOpcode opcode,
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final RandomAccessFile? file = _file;
    if (file == null) {
      throw StateError('Discord IPC pipe is closed.');
    }
    await file.writeFrom(encode(opcode, <String, Object?>{...payload, ...extra}));
  }

  @override
  Future<void> close() async {
    final RandomAccessFile? file = _file;
    _file = null;
    try {
      if (file != null) {
        await file.writeFrom(
          encode(_DiscordOpcode.close, const <String, Object?>{}),
        );
      }
    } on Object {
      // Ignore close errors.
    }
    await file?.close();
    finish();
  }

  Future<RandomAccessFile?> _openPipe() async {
    for (int index = 0; index < 10; index += 1) {
      try {
        return await File(_pipePath(index)).open(mode: FileMode.write);
      } on Object {
        continue;
      }
    }
    return null;
  }

  String _pipePath(int index) => '\\\\?\\pipe\\discord-ipc-$index';
}

class _DiscordActivity {
  const _DiscordActivity({
    required this.name,
    required this.type,
    this.details,
    this.detailsUrl,
    this.state,
    this.stateUrl,
    this.timestamps,
    this.assets,
    this.buttons = const <_DiscordActivityButton>[],
  });

  final String name;
  final int type;
  final String? details;
  final String? detailsUrl;
  final String? state;
  final String? stateUrl;
  final _DiscordActivityTimestamps? timestamps;
  final _DiscordActivityAssets? assets;
  final List<_DiscordActivityButton> buttons;

  Map<String, Object?> toJson() {
    final Map<String, Object?> json = <String, Object?>{
      'name': name,
      'type': type,
      'details': details,
      'details_url': detailsUrl,
      'state': state,
      'state_url': stateUrl,
      'timestamps': timestamps?.toJson(),
      'assets': assets?.toJson(),
      'buttons': buttons.isEmpty
          ? null
          : buttons.map((button) => button.toJson()).toList(growable: false),
    };
    json.removeWhere((_, Object? value) => value == null);
    return json;
  }
}

class _DiscordActivityAssets {
  const _DiscordActivityAssets({
    this.largeImage,
    this.largeText,
    this.largeUrl,
    this.smallImage,
    this.smallText,
    this.smallUrl,
  });

  final String? largeImage;
  final String? largeText;
  final String? largeUrl;
  final String? smallImage;
  final String? smallText;
  final String? smallUrl;

  Map<String, Object?> toJson() {
    final Map<String, Object?> json = <String, Object?>{
      'large_image': largeImage,
      'large_text': largeText,
      'large_url': largeUrl,
      'small_image': smallImage,
      'small_text': smallText,
      'small_url': smallUrl,
    };
    json.removeWhere((_, Object? value) => value == null);
    return json;
  }
}

class _DiscordActivityButton {
  const _DiscordActivityButton({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  Map<String, String> toJson() => <String, String>{
    'label': label,
    'url': url,
  };
}

class _DiscordActivityTimestamps {
  const _DiscordActivityTimestamps({
    this.start,
    this.end,
  });

  final DateTime? start;
  final DateTime? end;

  Map<String, Object?> toJson() {
    final Map<String, Object?> json = <String, Object?>{
      'start': start == null ? null : start!.millisecondsSinceEpoch ~/ 1000,
      'end': end == null ? null : end!.millisecondsSinceEpoch ~/ 1000,
    };
    json.removeWhere((_, Object? value) => value == null);
    return json;
  }
}
