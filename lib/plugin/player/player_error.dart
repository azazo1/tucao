/// 播放器错误判定.
///
/// 只做纯逻辑判断, 不接触原生播放器, 方便单独验证.
///
/// 判据说明: media_kit 的 error 流是把 mpv 日志里 level 为 error 的条目
/// 按 prefix 和文本前缀筛出来再转发, 没有错误码和严重程度.
/// 而 mpv 真正的终局信号 MPV_EVENT_END_FILE 在 media_kit 里被注释掉了,
/// 所以应用层拿不到 "这次真的播不下去了" 的权威标志.
///
/// 能用的直接证据是 demuxer-cache-time (即 [Player.stream.buffer]),
/// 它是缓存末尾的绝对时间, 只在 demuxer 真的读到新数据时才前进.
/// 播放位置推进只能说明解码器在消费缓存, 不能说明网络活着, 不能用来判断恢复.
abstract final class PlayerError {
  /// 出错后先等这么久, 期间缓存末尾前进了就当抖动, 不打扰画面.
  static const grace = Duration(seconds: 2);

  /// 缓存末尾相对出错时前进这么多, 认为已经真正恢复.
  static const cacheLead = Duration(seconds: 1);

  /// 判断错误是否只是解码器回退, 语义确定, 可以直接忽略.
  ///
  /// mpv 明说了要换软解继续播, 这类信息不该当成播放失败.
  static bool codecFallback(String message) =>
      message.toLowerCase().contains('could not open codec');

  /// 出错后缓存末尾是否已经往前走了, 说明 demuxer 又能读到数据.
  static bool cacheAdvanced(Duration errorBuffered, Duration buffered) =>
      buffered - errorBuffered >= cacheLead;

  /// 缓存是否快被吃完了, 播放马上就要卡住.
  ///
  /// 缓存时间不可用 (为 0) 时返回 true, 由调用方退回到只按观察窗判断.
  static bool cacheDrained(Duration position, Duration buffered) {
    if (buffered <= Duration.zero) {
      return true;
    }
    return buffered - position <= cacheLead;
  }
}
