import 'dart:math' as math;

/// Download/cache progress helpers consumed by the setup screen,
/// transfer screens, and any screen showing stale-data timestamps.
class DownloadHelper {
  DownloadHelper._();

  /// Converts [bytes] to a human-readable string: "2.4 MB", "840 KB".
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    final i = (math.log(bytes) / math.log(1024)).floor().clamp(0, units.length - 1);
    final val = bytes / math.pow(1024, i);
    return i == 0 ? '$bytes B' : '${val.toStringAsFixed(1)} ${units[i]}';
  }

  /// Returns "just now", "2 min ago", "1 h ago", "3 days ago"
  /// relative to [then]. Used on stale-data banners.
  static String timeAgo(DateTime? then) {
    if (then == null) return 'never';
    final diff = DateTime.now().difference(then);

    if (diff.inSeconds  <  60) return 'just now';
    if (diff.inMinutes  <  60) return '${diff.inMinutes} min ago';
    if (diff.inHours    <  24) return '${diff.inHours} h ago';
    if (diff.inDays     <   7) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return '${(diff.inDays / 7).floor()} week${(diff.inDays / 7).floor() == 1 ? '' : 's'} ago';
  }

  /// Clamps [progress] to [0.0, 1.0] and returns a display percentage string.
  static String pctLabel(double progress) =>
      '${(progress.clamp(0.0, 1.0) * 100).round()}%';

  /// Returns an estimated download time label for [remainingFiles]
  /// assuming a rough average of [msPerFile] ms per file.
  static String etaLabel(int remainingFiles, {int msPerFile = 120}) {
    final totalMs = remainingFiles * msPerFile;
    if (totalMs < 5000)  return 'almost done';
    if (totalMs < 60000) return '${(totalMs / 1000).round()} sec left';
    return '${(totalMs / 60000).ceil()} min left';
  }
}
