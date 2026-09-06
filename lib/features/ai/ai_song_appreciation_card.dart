import 'package:flutter/material.dart';

import '../../application/ai/song_appreciation_controller.dart';
import '../../application/stores/ai_settings_store.dart';
import '../../domain/models/track.dart';

/// 歌曲信息面板里的「AI 赏析」卡片。
///
/// 样式跟着宿主面板走（封面之上的深色背景 + 白字），所以这里不用 Miuix 主题色。
/// 没配置 AI 时整块不渲染——设置页才是配置的地方，不在播放器里推销。
class AiSongAppreciationCard extends StatefulWidget {
  const AiSongAppreciationCard({
    super.key,
    required this.track,
    this.styles = const [],
    this.language = '',
    this.bpm = '',
    this.artistBio = '',
  });

  final Track? track;

  /// 宿主面板已经加载好的曲目资料，直接透传给模型当材料，避免重复请求。
  final List<String> styles;
  final String language;
  final String bpm;
  final String artistBio;

  @override
  State<AiSongAppreciationCard> createState() => _AiSongAppreciationCardState();
}

class _AiSongAppreciationCardState extends State<AiSongAppreciationCard> {
  final _settings = AiSettingsStore.instance;
  final _controller = SongAppreciationController.instance;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    if (track == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([_settings, _controller]),
      builder: (context, _) {
        if (!_settings.isConfigured) return const SizedBox.shrink();
        final state = _controller.of(track);
        return Padding(
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'AI 赏析',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (state.streaming)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        color: Colors.white70,
                      ),
                    )
                  else if (state.text.isNotEmpty || state.error != null)
                    _TextAction(
                      label: '重新生成',
                      onTap: () => _generate(track, force: true),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: _body(track, state),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _generate(Track track, {bool force = false}) =>
      _controller.generate(
        track,
        force: force,
        styles: widget.styles,
        language: widget.language,
        bpm: widget.bpm,
        artistBio: widget.artistBio,
      );

  Widget _body(Track track, SongAppreciation state) {
    if (state.error != null && state.text.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.error!,
            style: const TextStyle(
              color: Color(0xFFFFB4A9),
              fontSize: 13,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          _TextAction(label: '重试', onTap: () => _generate(track, force: true)),
        ],
      );
    }
    if (state.text.isNotEmpty) {
      return Text(
        state.text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.86),
          fontSize: 14,
          height: 1.7,
        ),
      );
    }
    if (state.streaming) {
      return Text(
        '正在生成…',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.5),
          fontSize: 13,
        ),
      );
    }
    // 初始态：不自动生成，点了才花钱。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '让 AI 聊聊这首歌的编曲、演唱和歌词。',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 12),
        _TextAction(label: '生成赏析', onTap: () => _generate(track)),
      ],
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}
