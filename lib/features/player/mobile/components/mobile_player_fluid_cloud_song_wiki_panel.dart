import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
// 只取进度指示器：原版文件按逐行移植保留，避免 miuix 全量导入与原版符号撞名。
import 'package:flutter_miuix/miuix.dart'
    show MiuixCircularProgressIndicator, MiuixProgressIndicatorColors;
import '../compat/player_service.dart';
import '../compat/wiki_services.dart';
import '../compat/playlist_queue_service.dart';
import 'mobile_player_song_comments.dart';
import '../../../../domain/models/track.dart';
import '../../../../domain/models/media_url.dart';
import '../../../../domain/models/music_source.dart';

/// 移动端流体云歌曲信息面板
/// 展示曲风、BPM、语种、回忆坐标、相似歌曲、歌手信息等
class MobilePlayerFluidCloudSongWikiPanel extends StatefulWidget {
  const MobilePlayerFluidCloudSongWikiPanel({super.key});

  @override
  State<MobilePlayerFluidCloudSongWikiPanel> createState() => _MobilePlayerFluidCloudSongWikiPanelState();
}

class _MobilePlayerFluidCloudSongWikiPanelState extends State<MobilePlayerFluidCloudSongWikiPanel> {
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _wikiData;
  Map<String, dynamic>? _musicDetail;
  Map<String, dynamic>? _userMemory;
  
  // 歌手相关数据 (支持多位歌手)
  List<Map<String, dynamic>> _artistsDataList = [];
  
  bool _loading = true;
  dynamic _lastSongId;
  
  // 歌单详情相关 (内嵌子视图)
  int? _selectedPlaylistId;
  NeteasePlaylistDetail? _playlistDetail;
  bool _loadingPlaylist = false;

  @override
  void initState() {
    super.initState();
    PlayerService().addListener(_onPlayerChanged);
    _loadSongData();
  }

  @override
  void dispose() {
    PlayerService().removeListener(_onPlayerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    _loadSongData();
  }

  Future<void> _loadSongData() async {
    final track = PlayerService().currentTrack;
    
    if (track == null || track.source != MusicSource.netease) {
      if (mounted && _wikiData != null) {
        setState(() {
          _wikiData = null;
          _musicDetail = null;
          _userMemory = null;
          _lastSongId = null;
        });
      }
      return;
    }

    if (track.id == _lastSongId && _wikiData != null) return;

    if (mounted) setState(() => _loading = true);

    try {
      // 1. 获取所有歌手名
      final allArtistsName = track.artists;
      final artistNames = _splitArtists(allArtistsName);
      
      // 2. 基础请求：网易云百科 + 用户回忆坐标
      final baseFutures = <Future<dynamic>>[
        NeteaseSongWikiService().fetchSongWiki(track.id),
        NeteaseSongWikiService().fetchSongMusicDetail(track.id),
        SongMemoryService().fetchSongMemory(track.id.toString(), track.source.name),
      ];

      final baseResults = await Future.wait(baseFutures);
      
      // 3. 并行获取每位歌手的详情
      List<Map<String, dynamic>> newArtistsDataList = [];
      
      final artistFutures = artistNames.map((name) async {
         try {
           final artistId = await NeteaseArtistDetailService().resolveArtistIdByName(name);
           if (artistId == null) return null;
           
           final results = await Future.wait([
             NeteaseArtistDetailService().fetchArtistDesc(artistId),
             NeteaseArtistDetailService().fetchArtistDetail(artistId),
           ]);
           
           final descData = results[0];
           final detailData = results[1];
           
           String briefDesc = '';
           if (descData != null && descData['briefDesc'] != null) {
              briefDesc = descData['briefDesc'].toString();
           } else if (detailData != null && detailData['artist'] != null) {
              final val = detailData['artist']['briefDesc'] ?? detailData['artist']['description'];
              briefDesc = val?.toString() ?? '';
           }
           
           String avatarUrl = '';
           if (detailData != null && detailData['artist'] != null) {
              final artistObj = detailData['artist'];
              if (artistObj is Map) {
                avatarUrl = artistObj['img1v1Url']?.toString() ?? 
                            artistObj['picUrl']?.toString() ?? '';
              }
           }
           
           List<Track> hotSongs = [];
           if (detailData != null && detailData['songs'] != null) {
             final songsData = detailData['songs'] as List<dynamic>;
             hotSongs = songsData.map((s) {
               final m = s as Map<String, dynamic>;
               return Track(
                 id: m['id'],
                 name: m['name']?.toString() ?? '',
                 artists: m['artists']?.toString() ?? '',
                 album: m['album']?.toString() ?? '',
                 picUrl: m['picUrl']?.toString() ?? '',
                 source: MusicSource.netease,
               );
             }).toList();
           }
           
           return {
             'name': name,
             'desc': briefDesc,
             'avatarUrl': avatarUrl,
             'hotSongs': hotSongs,
           };
         } catch (e) {
           debugPrint('Error fetching artist data for $name: $e');
           return null;
         }
      }).toList();

      final artistsResults = await Future.wait(artistFutures);
      
      for (final item in artistsResults) {
        if (item != null) {
          newArtistsDataList.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _wikiData = baseResults[0] as Map<String, dynamic>?;
          _musicDetail = baseResults[1] as Map<String, dynamic>?;
          _userMemory = baseResults[2] as Map<String, dynamic>?;
          
          _artistsDataList = newArtistsDataList;

          _loading = false;
          _lastSongId = track.id;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 分割歌手字符串
  List<String> _splitArtists(String artists) {
    if (artists.isEmpty) return [];
    final separators = RegExp(r'[/\\、&,，]');
    return artists.split(separators).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 从 blocks 中查找指定 code 的区块
  Map<String, dynamic>? _findBlock(String code) {
    final blocks = _wikiData?['blocks'] as List? ?? [];
    for (final block in blocks) {
      if (block is Map && block['code'] == code) {
        return block as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// 解析音乐百科数据（曲风、语种、BPM）
  Map<String, dynamic> _parseBasicInfo() {
    final basicBlock = _findBlock('SONG_PLAY_ABOUT_SONG_BASIC');
    final creatives = basicBlock?['creatives'] as List? ?? [];
    
    List<String> styles = [];
    String language = '';
    String bpm = '';
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final creativeType = creative['creativeType']?.toString() ?? '';
      final uiElement = creative['uiElement'] as Map?;
      
      if (creativeType == 'songTag') {
        final resources = creative['resources'] as List? ?? [];
        for (final res in resources) {
          if (res is Map) {
            final title = res['uiElement']?['mainTitle']?['title']?.toString();
            if (title != null && title.isNotEmpty) {
              styles.add(title);
            }
          }
        }
      } else if (creativeType == 'language') {
        final textLinks = uiElement?['textLinks'] as List? ?? [];
        if (textLinks.isNotEmpty && textLinks[0] is Map) {
          language = textLinks[0]['text']?.toString() ?? '';
        }
      } else if (creativeType == 'bpm') {
        final textLinks = uiElement?['textLinks'] as List? ?? [];
        if (textLinks.isNotEmpty && textLinks[0] is Map) {
          bpm = textLinks[0]['text']?.toString() ?? '';
        }
      }
    }
    
    return {'styles': styles, 'language': language, 'bpm': bpm};
  }

  /// 解析回忆坐标数据（第一次听、累计播放）
  Map<String, dynamic> _parseMemoryInfo() {
    final memoryBlock = _findBlock('SONG_PLAY_ABOUT_MUSIC_MEMORY');
    final creatives = memoryBlock?['creatives'] as List? ?? [];
    
    String firstListenDate = '';
    String firstListenSeason = '';
    String firstListenPeriod = '';
    int playCount = 0;
    String playDescription = '';
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final resources = creative['resources'] as List? ?? [];
      
      for (final res in resources) {
        if (res is! Map) continue;
        final resourceType = res['resourceType']?.toString() ?? '';
        final resourceExt = res['resourceExt'] as Map?;
        
        if (resourceType == 'FIRST_LISTEN') {
          final dto = resourceExt?['musicFirstListenDto'] as Map?;
          if (dto != null) {
            firstListenDate = dto['date']?.toString() ?? '';
            firstListenSeason = dto['season']?.toString() ?? '';
            firstListenPeriod = dto['period']?.toString() ?? '';
          }
        } else if (resourceType == 'TOTAL_PLAY') {
          final dto = resourceExt?['musicTotalPlayDto'] as Map?;
          if (dto != null) {
            playCount = dto['playCount'] ?? 0;
            playDescription = dto['text']?.toString() ?? '';
          }
        }
      }
    }
    
    return {
      'firstListenDate': firstListenDate,
      'firstListenSeason': firstListenSeason,
      'firstListenPeriod': firstListenPeriod,
      'playCount': playCount,
      'playDescription': playDescription,
    };
  }

  /// 解析相似歌曲数据
  List<Map<String, dynamic>> _parseSimilarSongs() {
    final similarBlock = _findBlock('SONG_PLAY_ABOUT_SIMILAR_SONG');
    final creatives = similarBlock?['creatives'] as List? ?? [];
    
    List<Map<String, dynamic>> songs = [];
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final resources = creative['resources'] as List? ?? [];
      
      for (final res in resources) {
        if (res is! Map) continue;
        if (res['resourceType'] != 'SONG') continue;
        
        final uiElement = res['uiElement'] as Map?;
        if (uiElement == null) continue;
        
        final title = uiElement['mainTitle']?['title']?.toString() ?? '';
        
        final subTitles = uiElement['subTitles'] as List? ?? [];
        String artist = '';
        if (subTitles.isNotEmpty && subTitles[0] is Map) {
          artist = (subTitles[0] as Map)['title']?.toString() ?? '';
        }
        
        final images = uiElement['images'] as List? ?? [];
        String imageUrl = '';
        if (images.isNotEmpty && images[0] is Map) {
          // URL 原样使用：明文 HTTP 由 network_security_config 放行（见封面加载约定）
          imageUrl = (images[0] as Map)['imageUrl']?.toString() ?? '';
        }
        
        final songId = res['resourceId']?.toString() ?? '';
        
        if (title.isNotEmpty) {
          songs.add({
            'id': songId,
            'name': title,
            'artist': artist,
            'imageUrl': imageUrl,
          });
        }
      }
    }
    
    return songs.take(6).toList();
  }

  /// 解析相关歌单数据
  List<Map<String, dynamic>> _parseRelatedPlaylists() {
    final relatedBlock = _findBlock('SONG_PLAY_ABOUT_RELATED_PLAYLIST');
    final creatives = relatedBlock?['creatives'] as List? ?? [];
    
    List<Map<String, dynamic>> playlists = [];
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final resources = creative['resources'] as List? ?? [];
      
      for (final res in resources) {
        if (res is! Map) continue;
        if (res['resourceType'] != 'PLAYLIST') continue;
        
        final uiElement = res['uiElement'] as Map?;
        if (uiElement == null) continue;
        
        final title = uiElement['mainTitle']?['title']?.toString() ?? '';
        
        // 解析封面
        final images = uiElement['images'] as List? ?? [];
        String imageUrl = '';
        if (images.isNotEmpty && images[0] is Map) {
          // URL 原样使用：明文 HTTP 由 network_security_config 放行（见封面加载约定）
          imageUrl = (images[0] as Map)['imageUrl']?.toString() ?? '';
        }
        
        // 解析播放量
        final resourceExt = res['resourceExt'] as Map?;
        final playCount = resourceExt?['playCount'] ?? 0;
        
        final playlistId = res['resourceId']?.toString() ?? '';
        
        if (title.isNotEmpty) {
          playlists.add({
            'id': playlistId,
            'name': title,
            'imageUrl': imageUrl,
            'playCount': playCount,
          });
        }
      }
    }
    
    return playlists.take(6).toList(); // 移动端最多显示6个歌单
  }

  /// 根据日期获取季节和时段描述
  String _getSeasonAndPeriod(DateTime date) {
    String season;
    final month = date.month;
    if (month >= 3 && month <= 5) {
      season = '春天';
    } else if (month >= 6 && month <= 8) {
      season = '夏天';
    } else if (month >= 9 && month <= 11) {
      season = '秋天';
    } else {
      season = '冬天';
    }
    
    String period;
    final hour = date.hour;
    if (hour >= 6 && hour < 12) {
      period = '早晨';
    } else if (hour >= 12 && hour < 14) {
      period = '中午';
    } else if (hour >= 14 && hour < 18) {
      period = '下午';
    } else if (hour >= 18 && hour < 22) {
      period = '傍晚';
    } else {
      period = '深夜';
    }
    
    return '$season · $period';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: MiuixCircularProgressIndicator(
          size: 28,
          strokeWidth: 3,
          colors: MiuixProgressIndicatorColors(
            foregroundColor: Colors.white70,
            disabledForegroundColor: Colors.white70,
            backgroundColor: Colors.transparent,
          ),
        ),
      );
    }

    if (_wikiData == null && _musicDetail == null) {
      return Center(
        child: Text(
          '暂无歌曲信息',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
        ),
      );
    }

    // 使用 AnimatedSwitcher 在主内容和歌单详情之间切换
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        return FadeTransition(opacity: animation, child: child);
      },
      child: _selectedPlaylistId != null
          ? _buildPlaylistDetailView()
          : _buildMainContentView(),
    );
  }

  Widget _buildMainContentView() {
    final track = PlayerService().currentTrack;
    final basicInfo = _parseBasicInfo();
    final memoryInfo = _parseMemoryInfo();
    final similarSongs = _parseSimilarSongs();
    final relatedPlaylists = _parseRelatedPlaylists();
    
    final styles = basicInfo['styles'] as List<String>;
    final language = basicInfo['language'] as String;
    final bpm = basicInfo['bpm'] as String;
    
    // 优先使用用户自己的回忆坐标
    String firstListenDate = '';
    String firstListenDesc = '';
    int playCount = 0;
    String playDescription = '';
    
    if (_userMemory != null) {
      final firstPlayedAt = _userMemory!['firstPlayedAt'] as String?;
      if (firstPlayedAt != null && firstPlayedAt.isNotEmpty) {
        final dateUtc = DateTime.tryParse(firstPlayedAt);
        if (dateUtc != null) {
          final date = dateUtc.add(const Duration(hours: 8));
          firstListenDate = '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          firstListenDesc = _getSeasonAndPeriod(date);
        }
      }
      playCount = (_userMemory!['playCount'] as int?) ?? 0;
    } else {
      firstListenDate = memoryInfo['firstListenDate'] as String;
      final season = memoryInfo['firstListenSeason'] as String;
      final period = memoryInfo['firstListenPeriod'] as String;
      firstListenDesc = '$season$period';
      playCount = memoryInfo['playCount'] as int;
      playDescription = memoryInfo['playDescription'] as String;
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      children: [
        // 歌曲大标题
        Text(
          track?.name ?? '歌曲信息',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          track?.artists ?? '',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 32),

        // 音乐百科元数据
        if (styles.isNotEmpty || language.isNotEmpty || bpm.isNotEmpty) ...[
          _buildSectionTitle('音乐百科'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 16,
            children: [
              if (styles.isNotEmpty) _buildMetaItem('曲风', styles.join(' / ')),
              if (language.isNotEmpty) _buildMetaItem('语种', language),
              if (bpm.isNotEmpty) _buildMetaItem('BPM', bpm),
            ],
          ),
          const SizedBox(height: 32),
        ],

        // 回忆坐标
        if (firstListenDate.isNotEmpty || playCount > 0) ...[
          _buildSectionTitle('回忆坐标'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (firstListenDate.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, color: Colors.white.withValues(alpha: 0.6), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '第一次听',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$firstListenDate · $firstListenDesc',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                if (firstListenDate.isNotEmpty && playCount > 0)
                  const SizedBox(height: 16),
                if (playCount > 0) ...[
                  Row(
                    children: [
                      Icon(Icons.replay_rounded, color: Colors.white.withValues(alpha: 0.6), size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '累计播放 $playCount 次',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (playDescription.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                playDescription,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],

        // 相似歌曲
        if (similarSongs.isNotEmpty) ...[
          _buildSectionTitle('相似歌曲'),
          const SizedBox(height: 12),
          ...similarSongs.map((song) => _buildSimilarSongTile(song)),
          const SizedBox(height: 32),
        ],

        // 包含这首歌的歌单
        if (relatedPlaylists.isNotEmpty) ...[
          _buildSectionTitle('包含这首歌的歌单'),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemCount: relatedPlaylists.length,
            itemBuilder: (context, index) => _buildRelatedPlaylistTile(relatedPlaylists[index]),
          ),
          const SizedBox(height: 32),
        ],

        // 歌手介绍
        if (_artistsDataList.isNotEmpty) ...[
          _buildSectionTitle('关于歌手'),
          
          ..._artistsDataList.map((artistData) {
             final name = artistData['name'] as String;
             final desc = artistData['desc'] as String;
             final avatarUrl = artistData['avatarUrl'] as String;
             final hotSongs = artistData['hotSongs'] as List<Track>;
             
             return Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                 const SizedBox(height: 20),
                 // 歌手名小标题
                 Row(
                   children: [
                      if (avatarUrl.isNotEmpty)
                        ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: avatarUrl,
                            httpHeaders: imageHeaders(avatarUrl),
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            memCacheWidth: coverDecodeWidth(
                              36,
                              MediaQuery.devicePixelRatioOf(context),
                            ),
                            placeholder: (context, url) => Container(
                              color: Colors.white10,
                              child: Icon(CupertinoIcons.person_fill, size: 18, color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.white10,
                              child: Icon(CupertinoIcons.person_fill, size: 18, color: Colors.white.withValues(alpha: 0.5)),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.1),
                          ),
                          child: Icon(CupertinoIcons.person_fill, size: 18, color: Colors.white.withValues(alpha: 0.6)),
                        ),
                        
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                         name,
                         style: TextStyle(
                           color: Colors.white.withValues(alpha: 0.9),
                           fontSize: 16,
                           fontWeight: FontWeight.bold,
                         ),
                       ),
                      ),
                   ],
                 ),
                 const SizedBox(height: 12),
                 
                 // 简介
                 if (desc.isNotEmpty) ...[
                   Text(
                     desc,
                     style: TextStyle(
                       color: Colors.white.withValues(alpha: 0.7),
                       fontSize: 13,
                       height: 1.5,
                     ),
                     maxLines: 3,
                     overflow: TextOverflow.ellipsis,
                   ),
                   const SizedBox(height: 16),
                 ],
                 
                 // 热门作品
                 if (hotSongs.isNotEmpty) ...[
                    Text(
                      '$name 的热门作品',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...hotSongs.take(4).map((track) => _buildArtistSongItem(track)),
                 ],
                 
                 // 分隔线
                 if (artistData != _artistsDataList.last)
                   Padding(
                     padding: const EdgeInsets.symmetric(vertical: 16),
                     child: Divider(color: Colors.white.withValues(alpha: 0.1), height: 1),
                   ),
               ],
             );
          }),
        ],

        // 歌曲评论（仅网易云，对齐后端 /comment/music）
        if (track != null && track.source == MusicSource.netease) ...[
          const SizedBox(height: 32),
          MobilePlayerSongComments(track: track),
        ],

        const SizedBox(height: 60), // 底部留白
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.9),
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimilarSongTile(Map<String, dynamic> song) {
    final imageUrl = song['imageUrl'] as String? ?? '';
    final name = song['name'] as String? ?? '';
    final artist = song['artist'] as String? ?? '';
    
    return GestureDetector(
      onTap: () => _playSimilarSong(song),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // 封面
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: imageUrl,
                      httpHeaders: imageHeaders(imageUrl),
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      memCacheWidth: coverDecodeWidth(
                        44,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      placeholder: (context, url) => Container(
                        width: 44,
                        height: 44,
                        color: Colors.white10,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 44,
                        height: 44,
                        color: Colors.white10,
                        child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.3), size: 20),
                      ),
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      color: Colors.white10,
                      child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.3), size: 20),
                    ),
            ),
            const SizedBox(width: 12),
            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _playSimilarSong(Map<String, dynamic> song) {
    final songId = song['id']?.toString();
    if (songId == null || songId.isEmpty) return;
    
    final track = Track(
      id: songId,
      name: song['name']?.toString() ?? '',
      artists: song['artist']?.toString() ?? '',
      album: '',
      picUrl: song['imageUrl']?.toString() ?? '',
      source: MusicSource.netease,
    );
    
    // 使用 PlayerService 直接播放，与桌面端行为一致
    PlayerService().playTrack(track);
  }

  Widget _buildArtistSongItem(Track track) {
    return GestureDetector(
      onTap: () => PlayerService().playTrack(track),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // 封面
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: track.picUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: track.picUrl,
                      httpHeaders: imageHeaders(track.picUrl),
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      memCacheWidth: coverDecodeWidth(
                        36,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      placeholder: (context, url) => Container(
                        width: 36,
                        height: 36,
                        color: Colors.white10,
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 36,
                        height: 36,
                        color: Colors.white10,
                        child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.3), size: 16),
                      ),
                    )
                  : Container(
                      width: 36,
                      height: 36,
                      color: Colors.white10,
                      child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.3), size: 16),
                    ),
            ),
            const SizedBox(width: 10),
            // 信息
            Expanded(
              child: Text(
                track.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRelatedPlaylistTile(Map<String, dynamic> playlist) {
    final playCount = playlist['playCount'] as int? ?? 0;
    String playCountText;
    if (playCount >= 100000000) {
      playCountText = '${(playCount / 100000000).toStringAsFixed(1)}亿';
    } else if (playCount >= 10000) {
      playCountText = '${(playCount / 10000).toStringAsFixed(1)}万';
    } else {
      playCountText = playCount.toString();
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPlaylist(playlist),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: playlist['imageUrl'] ?? '',
                    httpHeaders: imageHeaders(playlist['imageUrl'] ?? ''),
                    fit: BoxFit.cover,
                    // 网格卡片约 120dp 宽，按此降采样解码
                    memCacheWidth: coverDecodeWidth(
                      120,
                      MediaQuery.devicePixelRatioOf(context),
                    ),
                    placeholder: (_, _) => Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: Icon(Icons.queue_music, color: Colors.white.withValues(alpha: 0.3), size: 28),
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: Colors.white.withValues(alpha: 0.1),
                      child: Icon(Icons.queue_music, color: Colors.white.withValues(alpha: 0.3), size: 28),
                    ),
                  ),
                  // 播放量标签
                  if (playCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow, color: Colors.white.withValues(alpha: 0.9), size: 10),
                            const SizedBox(width: 2),
                            Text(
                              playCountText,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          // 歌单名
          SizedBox(
            height: 32, // 固定高度，容纳2行文字
            child: Text(
              playlist['name'] ?? '',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _openPlaylist(Map<String, dynamic> playlist) async {
    final playlistId = playlist['id'];
    if (playlistId == null || playlistId.isEmpty) return;
    
    final id = int.tryParse(playlistId);
    if (id == null) return;
    
    // 立即切换到歌单详情视图，显示加载状态
    setState(() {
      _selectedPlaylistId = id;
      _loadingPlaylist = true;
      _playlistDetail = null;
    });
    
    // 异步加载歌单详情
    try {
      final detail = await NeteaseDiscoverService().fetchPlaylistDetail(id);
      if (mounted && _selectedPlaylistId == id) {
        setState(() {
          _playlistDetail = detail;
          _loadingPlaylist = false;
        });
      }
    } catch (e) {
      debugPrint('加载歌单详情失败: $e');
      if (mounted && _selectedPlaylistId == id) {
        setState(() => _loadingPlaylist = false);
      }
    }
  }

  /// 内嵌歌单详情视图
  Widget _buildPlaylistDetailView() {
    // 显示加载状态
    if (_loadingPlaylist) {
      return const Center(
        key: ValueKey('playlist_loading'),
        child: MiuixCircularProgressIndicator(
          size: 28,
          strokeWidth: 3,
          colors: MiuixProgressIndicatorColors(
            foregroundColor: Colors.white70,
            disabledForegroundColor: Colors.white70,
            backgroundColor: Colors.transparent,
          ),
        ),
      );
    }

    // 加载失败
    if (_playlistDetail == null) {
      return Center(
        key: const ValueKey('playlist_error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white.withValues(alpha: 0.5), size: 40),
            const SizedBox(height: 12),
            Text('加载失败', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => setState(() {
                _selectedPlaylistId = null;
                _playlistDetail = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('返回', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
              ),
            ),
          ],
        ),
      );
    }

    final detail = _playlistDetail!;
    final playCountText = detail.playCount >= 10000
        ? '${(detail.playCount / 10000).toStringAsFixed(1)}万'
        : detail.playCount.toString();

    return ListView(
      key: ValueKey('playlist_${detail.id}'),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      children: [
        // 返回按钮
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            onTap: () => setState(() {
              _selectedPlaylistId = null;
              _playlistDetail = null;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back_ios, color: Colors.white.withValues(alpha: 0.7), size: 14),
                  const SizedBox(width: 4),
                  Text('歌曲信息', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        
        // 歌单封面和信息
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              // URL 原样使用（不做 http→https 改写）+ 网易 UA，否则图片 CDN 403。
              child: CachedNetworkImage(
                imageUrl: detail.coverImgUrl,
                httpHeaders: imageHeaders(detail.coverImgUrl),
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                memCacheWidth: coverDecodeWidth(
                  100,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                placeholder: (_, _) => Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: Icon(Icons.queue_music, color: Colors.white.withValues(alpha: 0.3), size: 36),
                ),
                errorWidget: (_, _, _) => Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: Icon(Icons.queue_music, color: Colors.white.withValues(alpha: 0.3), size: 36),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail.creator,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.play_circle_outline, color: Colors.white.withValues(alpha: 0.5), size: 13),
                      const SizedBox(width: 3),
                      Text(playCountText, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                      const SizedBox(width: 10),
                      Icon(Icons.music_note_outlined, color: Colors.white.withValues(alpha: 0.5), size: 13),
                      const SizedBox(width: 3),
                      Text('${detail.trackCount}首', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 20),
        
        // 播放全部按钮
        GestureDetector(
          onTap: () {
            if (detail.tracks.isNotEmpty) {
              PlaylistQueueService().setQueue(detail.tracks, 0, QueueSource.playlist);
              PlayerService().playTrack(detail.tracks[0], fromPlaylist: true);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_arrow_rounded, color: Colors.white.withValues(alpha: 0.85), size: 20),
                const SizedBox(width: 6),
                Text(
                  '播放全部',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // 歌曲列表
        ...detail.tracks.take(50).map((track) => _buildPlaylistTrackTile(track, detail.tracks)),
        
        const SizedBox(height: 60),
      ],
    );
  }

  /// 歌单内歌曲卡片
  Widget _buildPlaylistTrackTile(Track track, List<Track> allTracks) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final index = allTracks.indexOf(track);
        final startIndex = index >= 0 ? index : 0;
        PlaylistQueueService().setQueue(allTracks, startIndex, QueueSource.playlist);
        PlayerService().playTrack(allTracks[startIndex], fromPlaylist: true);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: CachedNetworkImage(
                imageUrl: track.picUrl,
                httpHeaders: imageHeaders(track.picUrl),
                width: 42,
                height: 42,
                fit: BoxFit.cover,
                memCacheWidth: coverDecodeWidth(
                  42,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                placeholder: (_, _) => Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.3), size: 16),
                ),
                errorWidget: (_, _, _) => Container(
                  color: Colors.white.withValues(alpha: 0.1),
                  child: Icon(Icons.music_note, color: Colors.white.withValues(alpha: 0.3), size: 16),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.name,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artists,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
