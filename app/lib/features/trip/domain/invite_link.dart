import 'package:group_trip/features/trip/domain/trip_policy.dart';

/// 網頁版的邀請連結：`https://<專案>.web.app/j/<邀請碼>`（ADR 0012 第 3 點）。
abstract final class InviteLink {
  static const pathPrefix = 'j';

  /// 有 Firebase 專案時才有網址；本機模式回傳 null。
  static String? build({required String projectId, required String code}) {
    if (projectId.isEmpty) return null;
    final normalized = TripPolicy.normalizeInviteCode(code);
    return 'https://$projectId.web.app/$pathPrefix/$normalized';
  }

  /// 從網址讀出邀請碼。支援 `/j/<碼>` 與 hash 路由 `#/j/<碼>`；格式不對就回傳 null。
  static String? parse(Uri? uri) {
    if (uri == null) return null;
    final fromPath = _fromSegments(uri.pathSegments);
    if (fromPath != null) return fromPath;
    if (uri.fragment.isEmpty) return null;
    final fragment = Uri.tryParse(
      uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}',
    );
    return fragment == null ? null : _fromSegments(fragment.pathSegments);
  }

  static String? _fromSegments(List<String> segments) {
    final index = segments.indexOf(pathPrefix);
    if (index < 0 || index + 1 >= segments.length) return null;
    final code = TripPolicy.normalizeInviteCode(segments[index + 1]);
    return RegExp(r'^[A-Z0-9]{8,12}$').hasMatch(code) ? code : null;
  }
}
