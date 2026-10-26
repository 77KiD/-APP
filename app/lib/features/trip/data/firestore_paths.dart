/// 旅程是根。安全規則由後端撰寫，這裡只固定用戶端使用的路徑。
abstract final class FirestorePaths {
  static const trips = 'trips';
  static const members = 'members';
  static const requests = 'requests';
  static const itineraryDays = 'itineraryDays';
  static const itineraryHistory = 'itineraryHistory';
  static const handover = 'handover';
  static const soloNotices = 'soloNotices';
  static const locations = 'locations';
  static const inviteCodes = 'inviteCodes';
  static const users = 'users';
  static const meta = '_meta';
  static const clock = 'clock';

  static const all = [
    trips,
    members,
    requests,
    itineraryDays,
    itineraryHistory,
    handover,
    soloNotices,
    locations,
    inviteCodes,
    users,
    meta,
    clock,
  ];
}
