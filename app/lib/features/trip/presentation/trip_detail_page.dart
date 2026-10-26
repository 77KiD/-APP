import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:group_trip/app/app_scope.dart';
import 'package:group_trip/core/time/time_rules.dart';
import 'package:group_trip/core/widgets/form_widgets.dart';
import 'package:group_trip/features/trip/domain/trip_models.dart';
import 'package:group_trip/features/trip/domain/trip_policy.dart';
import 'package:group_trip/features/trip/presentation/member_avatar.dart';
import 'package:group_trip/l10n/app_strings.dart';

class TripDetailPage extends StatefulWidget {
  const TripDetailPage({required this.tripId, super.key});

  final String tripId;

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  Trip? _trip;
  List<TripMember> _members = [];
  List<InviteRecord> _invites = [];
  DateTime? _deviceNow;
  List<ModificationRequest> _requests = [];
  String? _error;
  String? _notice;
  bool _loading = true;
  bool _busy = false;
  bool _prefilled = false;
  final _returnDate = TextEditingController();
  final _returnTime = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _returnDate.dispose();
    _returnTime.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final deps = AppScope.of(context);
    try {
      final trip = await deps.trips.getTrip(widget.tripId);
      final members = await deps.trips.listMembers(widget.tripId);
      final invites = await deps.trips.listInvites(widget.tripId);
      final deviceNow = await deps.clock.now();
      final requests = await deps.trips.listRequests(widget.tripId);
      if (!mounted) return;
      if (!_prefilled && trip.expectedReturnAt != null) {
        final formatted = TripTime.format(trip.expectedReturnAt!, trip.timeZone);
        _returnDate.text = formatted.substring(0, 10);
        _returnTime.text = formatted.substring(11);
        _prefilled = true;
      }
      setState(() {
        _trip = trip;
        _members = members;
        _invites = invites;
        _deviceNow = deviceNow;
        _requests = requests;
        _loading = false;
      });
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    }
  }

  Future<void> _saveReturn() async {
    final trip = _trip;
    if (trip == null) return;
    final deps = AppScope.of(context);
    final self = _self;
    if (self == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final now = await deps.clock.now();
      final date = _returnDate.text.trim();
      final time = _returnTime.text.trim();
      DateTime? proposed;
      if (date.isEmpty && time.isEmpty) {
        proposed = null;
      } else {
        final parsed = TripPolicy.parseNewTrip(
          NewTripForm(
            title: trip.title,
            startDate: trip.startDate,
            endDate: trip.endDate,
            timeZone: trip.timeZone,
            returnDate: date,
            returnTime: time,
          ),
          now,
        );
        if (parsed.error != null) throw ValidationException(parsed.error!);
        proposed = parsed.expectedReturnAt;
      }
      if (self.role.canEditExpectedReturnDirectly) {
        await deps.trips.updateExpectedReturnTime(
          tripId: trip.id,
          proposed: proposed,
        );
      } else {
        if (proposed == null) {
          throw ValidationException(AppStrings.incompleteReturn);
        }
        await deps.trips.submitExpectedReturnRequest(
          tripId: trip.id,
          proposed: proposed,
        );
      }
      if (!mounted) return;
      await _load();
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clearReturn() async {
    final trip = _trip;
    final self = _self;
    if (trip == null || self == null) return;
    if (!self.role.canEditExpectedReturnDirectly) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).trips.updateExpectedReturnTime(
        tripId: trip.id,
        proposed: null,
      );
      _returnDate.clear();
      _returnTime.clear();
      if (!mounted) return;
      await _load();
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve(ModificationRequest request) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).trips.approveRequest(
        tripId: request.tripId,
        requestId: request.id,
      );
      if (!mounted) return;
      await _load();
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assign(TripMember member) async {
    setState(() => _busy = true);
    try {
      await AppScope.of(context).trips.assignViceCaptain(
        tripId: widget.tripId,
        userId: member.userId,
      );
      if (!mounted) return;
      await _load();
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyInvite(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _notice = AppStrings.copiedInvite);
  }

  Future<void> _issueInvite() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).trips.issueInviteCode(widget.tripId);
      if (!mounted) return;
      setState(() => _notice = AppStrings.inviteIssued);
      await _load();
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPublicInvite(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(context).trips.setPublicInvite(
        tripId: widget.tripId,
        enabled: enabled,
      );
      if (!mounted) return;
      await _load();
    } on TripException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool get _canIssueInvite {
    final self = _self;
    final trip = _trip;
    if (self == null || trip == null) return false;
    return TripPolicy.canIssueInvite(
      role: self.role,
      publicInvite: trip.publicInvite,
    );
  }

  TripMember? get _self {
    final id = AppScope.of(context).auth.current?.id;
    for (final member in _members) {
      if (member.userId == id) return member;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(
      appBar: AppBar(title: Text(trip?.title ?? AppStrings.appTitle)),
      body: _loading
          ? const Center(child: Text('正在載入旅程'))
          : trip == null
          ? FormColumn(children: [FormErrorText(_error)])
          : FormColumn(
              children: [
                PageHeading(trip.title),
                Text('${AppStrings.startDate}：${trip.startDate}'),
                Text('${AppStrings.endDate}：${trip.endDate}'),
                Text('${AppStrings.timeZone}：${trip.timeZone}'),
                Text(
                  trip.expectedReturnAt == null
                      ? '${AppStrings.expectedReturn}：${AppStrings.expectedReturnUnset}'
                      : '${AppStrings.expectedReturn}：${TripTime.format(trip.expectedReturnAt!, trip.timeZone)}',
                ),
                const PageHeading(AppStrings.inviteCode),
                if (TripPolicy.canTogglePublicInvite(_self?.role))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(AppStrings.publicInvite),
                    subtitle: const Text(AppStrings.publicInviteHelp),
                    value: trip.publicInvite,
                    onChanged: _busy ? null : _setPublicInvite,
                  ),
                for (final invite in _invites) ...[
                  SelectableText(
                    invite.code,
                    key: invite.code == trip.inviteCode
                        ? const Key('invite-code')
                        : Key('invite-${invite.code}'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    TripPolicy.memberInviteBlocked(
                      invitesResetAt: trip.invitesResetAt,
                      issuerRole: invite.issuerRole,
                      createdAt: invite.createdAt,
                    )
                        ? AppStrings.inviteClosedByPublicInvite
                        : _deviceNow == null
                        ? AppStrings.inviteAdvisory
                        : AppStrings.inviteRemaining(
                            TripPolicy.inviteRemaining(
                              invite.expiresAt,
                              _deviceNow!,
                            ),
                          ),
                  ),
                  OutlinedButton(
                    onPressed: () => _copyInvite(invite.code),
                    child: Text(AppStrings.copyInviteCode(invite.code)),
                  ),
                ],
                const Text(AppStrings.inviteAdvisory),
                OutlinedButton(
                  key: const Key('issue-invite'),
                  onPressed: _busy || !_canIssueInvite ? null : _issueInvite,
                  child: const Text(AppStrings.issueInvite),
                ),
                if (!_canIssueInvite) const Text(AppStrings.inviteRestricted),
                if (_notice != null)
                  Semantics(liveRegion: true, child: Text(_notice!)),
                const PageHeading(AppStrings.members),
                if (_members.length <= 4 && _self?.role == MemberRole.captain)
                  const Text(AppStrings.noViceSmallGroup),
                if (_members.length >= 5 && _members.length <= 7)
                  const Text(AppStrings.viceOptional),
                if (TripPolicy.viceCaptainRequiredToStart(_members.length) &&
                    !_members.any((member) => member.role == MemberRole.viceCaptain))
                  const Text(AppStrings.viceRequired),
                for (final member in _members) _MemberTile(
                  member: member,
                  canAssign:
                      !_busy &&
                      _self?.role == MemberRole.captain &&
                      TripPolicy.canAssignViceCaptain(_members.length) &&
                      member.role == MemberRole.member,
                  onAssign: () => _assign(member),
                ),
                const PageHeading(AppStrings.expectedReturn),
                LabeledField(
                  label: AppStrings.returnDate,
                  controller: _returnDate,
                  hint: AppStrings.dateHint,
                  helper: AppStrings.dateHelper,
                  keyboardType: TextInputType.datetime,
                ),
                LabeledField(
                  label: AppStrings.returnTime,
                  controller: _returnTime,
                  hint: AppStrings.timeHint,
                  helper: AppStrings.timeHelper,
                  keyboardType: TextInputType.datetime,
                ),
                FilledButton(
                  onPressed: _busy ? null : _saveReturn,
                  child: Text(
                    _self?.role.canEditExpectedReturnDirectly ?? false
                        ? AppStrings.saveExpectedReturn
                        : AppStrings.submitReturnRequest,
                  ),
                ),
                if (_self?.role.canEditExpectedReturnDirectly ?? false)
                  OutlinedButton(
                    onPressed: _busy ? null : _clearReturn,
                    child: const Text(AppStrings.clearExpectedReturn),
                  ),
                if (_self?.role.canEditExpectedReturnDirectly ?? false) ...[
                  const PageHeading(AppStrings.pendingRequests),
                  for (final request in _requests)
                    if (request.status == RequestStatus.pending)
                      _RequestTile(
                        request: request,
                        timeZone: trip.timeZone,
                        busy: _busy,
                        onApprove: () => _approve(request),
                      ),
                ],
                FormErrorText(_error),
              ],
            ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.canAssign,
    required this.onAssign,
  });

  final TripMember member;
  final bool canAssign;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MemberAvatar(name: member.displayName),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  member.displayName,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              RoleChip(role: member.role),
            ],
          ),
          if (canAssign)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onAssign,
                child: Text(AppStrings.assignVice(member.displayName)),
              ),
            ),
        ],
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile({
    required this.request,
    required this.timeZone,
    required this.busy,
    required this.onApprove,
  });

  final ModificationRequest request;
  final String timeZone;
  final bool busy;
  final VoidCallback onApprove;

  @override
  Widget build(BuildContext context) {
    final when = TripTime.format(request.proposedExpectedReturnAt, timeZone);
    final expiry = request.expiresAt == null
        ? AppStrings.requestWaitsForLeader
        : AppStrings.requestExpires(
            TripTime.format(request.expiresAt!, timeZone),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${request.requesterName}：$when'),
        Text(expiry),
        FilledButton(
          onPressed: busy ? null : onApprove,
          child: Text(AppStrings.approveReturn(when)),
        ),
      ],
    );
  }
}
