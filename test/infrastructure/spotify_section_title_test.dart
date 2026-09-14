import 'package:flutter_test/flutter_test.dart';

import 'package:cyrene_music_reborn/infrastructure/services/discovery_service.dart';

void main() {
  group('localizeSpotifySectionTitle', () {
    test('「Made For xxx」绝不能把号池账号的用户名漏到界面上', () {
      // 线上实测返回的就是这个形态，xxx 是号池账号的显示名。
      expect(localizeSpotifySectionTitle('Made For Morax Morax'), '专属合辑');
      expect(localizeSpotifySectionTitle('Made For KR.Tirtho'), '专属合辑');
      // 换号之后用户名会变，规则不能依赖具体名字。
      expect(localizeSpotifySectionTitle('Made For 某个新账号'), '专属合辑');
    });

    test('带艺术家名的标题保留艺术家，只换说法', () {
      expect(localizeSpotifySectionTitle('More like 乌托邦P'), '相似推荐 · 乌托邦P');
      expect(
        localizeSpotifySectionTitle('Discover more from Kesha'),
        '探索更多 · Kesha',
      );
      expect(
        localizeSpotifySectionTitle('For fans of Twenty One Pilots'),
        'Twenty One Pilots 的乐迷也在听',
      );
      expect(localizeSpotifySectionTitle('Best of artists'), 'artists 精选');
    });

    test('第二人称说法换成不声称归属的中文', () {
      // 内容来自号池账号，说成「你的」是误导。
      expect(localizeSpotifySectionTitle('Your top mixes'), '热门合辑');
      expect(localizeSpotifySectionTitle('Based on your recent listening'), '近期口味推荐');
      expect(localizeSpotifySectionTitle('New releases for you'), '新歌新碟');
      expect(localizeSpotifySectionTitle('Recently played'), '近期热播');
    });

    test('固定标题查表', () {
      expect(localizeSpotifySectionTitle("Today's biggest hits"), '今日热榜');
      expect(localizeSpotifySectionTitle('Popular artists'), '热门艺人');
      expect(localizeSpotifySectionTitle('Winding down...'), '夜深了');
    });

    test('随时间变化的标题走模式匹配', () {
      expect(
        localizeSpotifySectionTitle('Soundtrack your Sunday night'),
        '此刻的配乐',
      );
      expect(
        localizeSpotifySectionTitle('Soundtrack your Monday morning'),
        '此刻的配乐',
      );
    });

    test('未收录的标题原样返回，不吞成空串', () {
      // Spotify 随时可能改词或加新分区，漏掉时宁可显示英文也不能显示空白。
      expect(
        localizeSpotifySectionTitle('Some Brand New Shelf'),
        'Some Brand New Shelf',
      );
      expect(localizeSpotifySectionTitle(''), '');
      expect(localizeSpotifySectionTitle('   '), '');
    });

    test('首尾空白被去掉后再匹配', () {
      expect(localizeSpotifySectionTitle('  Chill  '), '放松一下');
    });
  });

  group('localizeSpotifySectionDescription', () {
    test('已知副标题换成中文', () {
      expect(
        localizeSpotifySectionDescription('Inspired by your recent activity'),
        '根据近期收听生成',
      );
      expect(
        localizeSpotifySectionDescription('Unwind with these calming playlists.'),
        '舒缓下来，慢慢听',
      );
    });

    test('未收录的原样返回', () {
      expect(localizeSpotifySectionDescription('Whatever else'), 'Whatever else');
      expect(localizeSpotifySectionDescription(''), '');
    });
  });
}
