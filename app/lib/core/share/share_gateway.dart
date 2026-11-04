import 'package:share_plus/share_plus.dart';

/// 用系統分享選單送出文字（例如分享到 LINE）。ADR 0011 第 3 點：
/// 第一版只用系統分享，不串 LINE SDK。
abstract class ShareGateway {
  Future<void> shareText(String text, {String? subject});
}

class SystemShareGateway implements ShareGateway {
  const SystemShareGateway();

  @override
  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}

/// 測試用：記下分享過的文字，不打開系統選單。
class RecordingShareGateway implements ShareGateway {
  final shared = <String>[];

  @override
  Future<void> shareText(String text, {String? subject}) async {
    shared.add(text);
  }
}
