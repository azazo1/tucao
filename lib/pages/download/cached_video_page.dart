import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tucao/models/download_task.dart';
import 'package:tucao/plugin/player/tucao_player.dart';
import 'package:tucao/utils/logger.dart';

/// 缓存播放只打开已下载的本地文件, 不请求详情, 弹幕或线上播放地址.
class CachedVideoPage extends StatefulWidget {
  const CachedVideoPage({super.key, required this.task, required this.file});

  final DownloadTask task;
  final File file;

  @override
  State<CachedVideoPage> createState() => _CachedVideoPageState();
}

class _CachedVideoPageState extends State<CachedVideoPage>
    with WidgetsBindingObserver {
  final _player = TucaoPlayer();
  bool _loading = true;
  String? _error;
  bool _closing = false;
  Future<void>? _opening;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _opening = _open();
  }

  Future<void> _open() async {
    try {
      if (!await widget.file.exists() || await widget.file.length() <= 0) {
        throw const FileSystemException('本地文件不存在或为空');
      }
      if (_closing) {
        return;
      }
      await _player.setUrl(widget.file.uri.toString(), autoPlay: false);
      if (_closing) {
        return;
      }
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? false)) {
        // 在后台或被另一页覆盖期间加载完成时不自动开始播放.
        final lifecycle = WidgetsBinding.instance.lifecycleState;
        if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
          await _player.play();
        }
      }
    } catch (error, stackTrace) {
      Log.e('打开本地缓存失败', error: error, stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = '本地缓存无法播放, 请删除后重新下载');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _player.pause().catchError((Object error) {
        Log.w('暂停本地播放失败: $error');
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closing = true;
    // 等待 open 收尾, 防止 native player 在异步加载中被销毁后再次使用.
    (_opening ?? Future<void>.value()).whenComplete(_player.dispose);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.task.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ColoredBox(
              color: Colors.black,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListenableBuilder(
                      listenable: _player,
                      builder: (context, child) {
                        final error = _error ?? _player.error;
                        if (error != null || !_player.initialized) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '本地缓存无法播放, 请删除后重新下载',
                                style: TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }
                        return Video(controller: _player.videoController);
                      },
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '本地缓存 - P${widget.task.part + 1} ${widget.task.partTitle}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
