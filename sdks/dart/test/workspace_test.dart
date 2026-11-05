import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:openhuman_sdk_dart/openhuman.dart';
import 'package:test/test.dart';

/// A tiny stand-in server that records what it was asked.
class _Server {
  late HttpServer http;
  final seen = <(String, String, String?, List<int>)>[];
  final routes = <String, (int, Object)>{};

  Future<String> start() async {
    http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    http.listen((req) async {
      final body = await req.fold<List<int>>([], (a, b) => a..addAll(b));
      seen.add((
        req.method,
        req.uri.path,
        req.headers.value(HttpHeaders.authorizationHeader),
        body,
      ));
      final hit = routes['${req.method} ${req.uri.path}'];
      if (hit == null) {
        req.response.statusCode = 404;
      } else {
        req.response.statusCode = hit.$1;
        final v = hit.$2;
        if (v is List<int>) {
          req.response.add(v);
        } else {
          req.response.headers.contentType = ContentType.json;
          req.response.write(jsonEncode(v));
        }
      }
      await req.response.close();
    });
    return 'ws://127.0.0.1:${http.port}/ws';
  }
}

void main() {
  late _Server s;
  late OpenHumanClient c;

  setUp(() async {
    s = _Server();
    c = OpenHumanClient()..useHttp(await s.start(), 'ohk_test');
  });
  tearDown(() async {
    await s.http.close(force: true);
    c.dispose();
  });

  test('answer posts text, files and end_turn to /v1/seat/reply', () async {
    s.routes['POST /v1/seat/reply'] = (
      200,
      {'ok': true, 'live': true, 'turn_ended': true},
    );
    final r = await c.answer(
      'cnv_1',
      text: '这是你要的图',
      attachments: [
        ReplyAttachment(
          name: 'out.png',
          mime: 'image/png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      ],
    );
    expect(r.ok, isTrue);
    expect(r.live, isTrue);
    final (m, path, auth, body) = s.seen.single;
    expect((m, path, auth), ('POST', '/v1/seat/reply', 'Bearer ohk_test'));
    final j = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    expect(j['conversation_id'], 'cnv_1');
    expect(j['end_turn'], isTrue);
    expect(j['attachments'][0]['data'], base64Encode([1, 2, 3]));
    expect(j['attachments'][0]['mime'], 'image/png');
  });

  test('a refused answer carries the server reason', () async {
    s.routes['POST /v1/seat/reply'] = (
      400,
      {
        'error': {'code': 'bad_answer', 'message': 'expected 2 entr(ies)'},
      },
    );
    final r = await c.answer('cnv_1', text: '[[]]');
    expect(r.ok, isFalse);
    expect(r.errorCode, 'bad_answer');
    expect(r.errorMessage, contains('expected 2'));
  });

  test('an answer nobody waits for reads as abandoned', () async {
    s.routes['POST /v1/seat/reply'] = (
      200,
      {'ok': true, 'live': false, 'abandoned': true},
    );
    final r = await c.answer('cnv_1', text: 'x');
    expect(r.abandoned, isTrue);
  });

  test('files: list, info, content, delete', () async {
    s.routes['GET /v1/files'] = (
      200,
      {
        'data': [
          {
            'id': 'file-1',
            'filename': 'out.png',
            'bytes': 3,
            'mime_type': 'image/png',
            'purpose': 'output',
            'created_at': 1700000000,
          },
        ],
      },
    );
    s.routes['GET /v1/files/file-1'] = (
      200,
      {'id': 'file-1', 'filename': 'out.png', 'bytes': 3},
    );
    s.routes['GET /v1/files/file-1/content'] = (200, <int>[9, 8, 7]);
    s.routes['DELETE /v1/files/file-1'] = (200, {'deleted': true});
    final list = await c.listFiles();
    expect(list.single.mime, 'image/png');
    expect(list.single.createdAt!.year, 2023);
    expect((await c.fileInfo('file-1')).filename, 'out.png');
    expect(await c.fileContent('file-1'), [9, 8, 7]);
    expect(await c.deleteFile('file-1'), isTrue);
  });

  test('upload sends multipart with the file and purpose', () async {
    s.routes['POST /v1/files'] = (
      200,
      {'id': 'file-2', 'filename': 'a.wav', 'bytes': 2},
    );
    final f = await c.uploadFile(
      'a.wav',
      Uint8List.fromList([5, 6]),
      mime: 'audio/wav',
    );
    expect(f.id, 'file-2');
    final body = latin1.decode(s.seen.single.$4);
    expect(body, contains('name="purpose"'));
    expect(body, contains('filename="a.wav"'));
    expect(body, contains('Content-Type: audio/wav'));
  });

  test('invites, leaving and removing members', () async {
    s.routes['POST /v1/invites/AB12/accept'] = (201, {'id': 'room_1'});
    s.routes['POST /v1/rooms/room_1/leave'] = (200, {'ok': true});
    s.routes['DELETE /v1/rooms/room_1/members/hum_2'] = (200, {'ok': true});
    expect((await c.acceptInvite(' AB12 '))['id'], 'room_1');
    expect(await c.leaveRoom('room_1'), isTrue);
    expect(await c.removeRoomMember('room_1', 'hum_2'), isTrue);
  });

  test('model name: seat view, fallback to the model list, rename', () async {
    s.routes['GET /v1/seat/model-name'] = (
      200,
      {'model': 'linxiao', 'locked': true},
    );
    final m = await c.modelName();
    expect((m.name, m.locked), ('linxiao', true));

    s.routes.remove('GET /v1/seat/model-name');
    s.routes['GET /v1/models'] = (
      200,
      {
        'data': [
          {'id': 'openhuman-human'},
        ],
      },
    );
    expect((await c.modelName()).name, 'openhuman-human');

    s.routes['POST /v1/seat/model-name'] = (200, {'ok': true, 'model': 'mia'});
    expect(await c.setModelName('mia'), 'mia');
  });

  test('history messages keep the request shape', () {
    final m = HistoryMessage.fromJson({
      'id': 'msg_1',
      'conversation_id': 'cnv_1',
      'sender_id': 'agt_1',
      'sender_type': 'agent',
      'text': 'a fox',
      'request': {'kind': 'api', 'api': 'images.generations'},
    });
    expect(m.request!['api'], 'images.generations');
  });
}
