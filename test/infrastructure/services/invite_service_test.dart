import 'dart:convert';

import 'package:cyrene_music_reborn/infrastructure/core/api_client.dart';
import 'package:cyrene_music_reborn/infrastructure/services/invite_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // InviteService 是私有构造的单例、内部固定用 ApiClient.instance，
  // 只能从这里换掉底层 http.Client。测试文件各跑在自己的 isolate，不会串台。
  void mock(Future<http.Response> Function(http.Request request) handler) {
    ApiClient.instance.useClient(MockClient(handler));
  }

  test('summary 解析出邀请码、积分与邀请人', () async {
    mock((request) async {
      expect(request.url.path, '/invite/summary');
      expect(request.headers['Authorization'], 'Bearer t');
      return _json('''
{"code":200,"data":{
  "code":"ABCD2345","points":3,"totalPoints":5,"rewardPerInvite":1,"minWithdrawal":1,
  "invitedBy":{"id":2,"username":"小明"},
  "invitedCount":2,"rewardedCount":1,
  "invitees":[{"id":9,"username":"小红","maskedEmail":"12***@qq.com","hasPremium":true,"rewarded":true}]
}}''');
    });

    final summary = await InviteService.instance.getSummary('t');

    expect(summary, isNotNull);
    expect(summary!.code, 'ABCD2345');
    expect(summary.points, 3);
    expect(summary.totalPoints, 5);
    expect(summary.inviterName, '小明');
    expect(summary.hasBoundInviter, isTrue);
    expect(summary.invitees.single.username, '小红');
    expect(summary.invitees.single.rewarded, isTrue);
  });

  test('未绑定邀请人时 hasBoundInviter 为 false', () async {
    mock(
      (_) async => _json(
        '{"code":200,"data":{"code":null,"points":0,"invitedBy":null,"invitees":[]}}',
      ),
    );

    final summary = await InviteService.instance.getSummary('t');

    expect(summary!.code, isNull);
    expect(summary.hasBoundInviter, isFalse);
    // 后端没下发时回落到本地默认，UI 不会拿到 0 而把提现按钮永久点亮。
    expect(summary.rewardPerInvite, 1);
    expect(summary.minWithdrawal, 1);
  });

  test('绑定失败时把后端文案原样透出', () async {
    mock((request) async {
      expect(request.url.path, '/invite/bind');
      expect(jsonDecode(request.body), {'code': 'ABCD2345'});
      return _json('{"code":400,"message":"不能填写自己的邀请码"}', 400);
    });

    final result = await InviteService.instance.bindCode('t', 'ABCD2345');

    expect(result.ok, isFalse);
    expect(result.message, '不能填写自己的邀请码');
  });

  test('提现记录状态解析，未知状态回落到待审核', () async {
    mock(
      (_) async => _json('''
{"code":200,"data":{"points":4,"minWithdrawal":1,"withdrawals":[
  {"id":1,"amount":2,"alipayAccount":"a@b.com","status":"paid"},
  {"id":2,"amount":1,"alipayAccount":"a@b.com","status":"rejected","note":"账号有误"},
  {"id":3,"amount":1,"alipayAccount":"a@b.com","status":"某个以后才有的状态"}
]}}'''),
    );

    final result = await InviteService.instance.getWithdrawals('t');

    expect(result!.points, 4);
    expect(result.records[0].status, WithdrawalStatus.paid);
    expect(result.records[1].status, WithdrawalStatus.rejected);
    expect(result.records[1].note, '账号有误');
    expect(result.records[2].status, WithdrawalStatus.pending);
    expect(result.records[2].status.label, '待审核');
  });

  test('提现姓名为空时不下发该字段', () async {
    late Map<String, Object?> sent;
    mock((request) async {
      sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      return _json('{"code":200,"message":"提现申请已提交，等待审核"}');
    });

    final result = await InviteService.instance.submitWithdrawal(
      token: 't',
      amount: 2,
      alipayAccount: 'a@b.com',
      alipayName: '   ',
    );

    expect(result.ok, isTrue);
    expect(result.message, '提现申请已提交，等待审核');
    expect(sent, {'amount': 2, 'alipayAccount': 'a@b.com'});
  });

  test('提现姓名非空时带上并去掉两侧空白', () async {
    late Map<String, Object?> sent;
    mock((request) async {
      sent = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      return _json('{"code":200,"message":"ok"}');
    });

    await InviteService.instance.submitWithdrawal(
      token: 't',
      amount: 2,
      alipayAccount: 'a@b.com',
      alipayName: ' 小红 ',
    );

    expect(sent['alipayName'], '小红');
  });

  test('网络异常不抛给调用方，降级成可展示的失败结果', () async {
    mock((_) async => throw http.ClientException('boom'));

    final bind = await InviteService.instance.bindCode('t', 'ABCD2345');
    final summary = await InviteService.instance.getSummary('t');

    expect(bind.ok, isFalse);
    expect(bind.message, '网络错误，请稍后重试');
    expect(summary, isNull);
  });
}

http.Response _json(String body, [int statusCode = 200]) => http.Response.bytes(
  utf8.encode(body),
  statusCode,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);
