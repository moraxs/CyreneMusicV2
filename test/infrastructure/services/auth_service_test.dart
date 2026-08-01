import 'dart:convert';

import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('登录响应从 data 同层读取用户和 token', () async {
    final service = AuthService(
      apiClient: ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/auth/login');
          expect(jsonDecode(request.body), {
            'account': 'cyrene',
            'password': 'secret',
          });
          return _jsonResponse(
            '{"message":"ok","data":{"id":7,"email":"cyrene@example.com","username":"Cyrene","isVerified":true,"isSponsor":false,"token":"token-123"}}',
            200,
          );
        }),
      ),
    );

    final result = await service.login('cyrene', 'secret');

    expect(result.success, isTrue);
    expect(result.user?.id, 7);
    expect(result.user?.username, 'Cyrene');
    expect(result.token, 'token-123');
  });

  test('登录失败保留服务端错误消息', () async {
    final service = AuthService(
      apiClient: ApiClient(
        client: MockClient(
          (_) async => _jsonResponse('{"message":"账号或密码错误"}', 401),
        ),
      ),
    );

    final result = await service.login('cyrene', 'wrong');

    expect(result.success, isFalse);
    expect(result.message, '账号或密码错误');
  });
}

http.Response _jsonResponse(String body, int statusCode) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
