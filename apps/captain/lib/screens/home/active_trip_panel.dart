import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:tempo_captain/services/captain_state.dart';
import 'package:url_launcher/url_launcher.dart';

import 'trip_chat_screen.dart';

/// The captain's in-trip control panel.
///
/// A trip is a sequence, and the previous panel never showed the captain
/// where they were in it — just a coloured pill with the current status. It
/// now leads with a four-stage stepper, so the captain can see at a glance
/// what they have done and what remains.
///
/// The destructive step is also properly guarded: finishing a trip settles
/// money, so it keeps its confirmation dialog, while the routine forward
/// steps stay single-tap because a driver should not have to fight the UI at
/// the kerb.
///
/// Contact with the rider is a pair of equals: the phone call for when the
/// pickup pin is wrong, and the in-app chat for everything else. The chat
/// button carries an unread badge fed by the live trip socket, so a rider
/// message never arrives silently while the panel is on screen.
class ActiveTripPanel extends StatefulWidget {
  const ActiveTripPanel({super.key, required this.trip});

  final Map<String, dynamic> trip;

  @override
  State<ActiveTripPanel> createState() => _ActiveTripPanelState();
}

class _ActiveTripPanelState extends State<ActiveTripPanel> {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _busy = false;

  /// Unread rider messages, driven by the live trip socket. Reset whenever
  /// the chat screen is opened (its fetch marks the thread read server-side).
  int _unreadMessages = 0;
  StreamSubscription<Map<String, dynamic>>? _tripEventsSub;

  static const _stages = ['assigned', 'arrived', 'in_progress'];

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    // Count rider messages as they land on the room socket. The captain's own
    // messages obviously do not increment the badge.
    final state = context.read<CaptainState>();
    _tripEventsSub = state.activeTripWsMessages.listen((ev) {
      if (!mounted) return;
      if (ev['type'] == 'chat.message' &&
          ev['senderRole'] != 'captain' &&
          (ev['tripId'] == null || ev['tripId'] == widget.trip['id'])) {
        setState(() => _unreadMessages++);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tripEventsSub?.cancel();
    super.dispose();
  }

  /// Elapsed time is derived from the trip's own server timestamp rather than
  /// counted in ticks. A tick counter restarts from 00:00 on every rebuild
  /// (each offers poll, each rotation, each app resume), so the captain used
  /// to watch the timer reset repeatedly mid-trip.
  void _tick() {
    if (!mounted) return;
    final raw = (widget.trip['started_at'] ??
            widget.trip['arrived_at'] ??
            widget.trip['assigned_at'])
        ?.toString();
    final startedAt = raw == null ? null : DateTime.tryParse(raw);
    setState(() {
      _elapsed = startedAt == null
          ? _elapsed + const Duration(seconds: 1)
          : DateTime.now().toUtc().difference(startedAt.toUtc());
    });
  }

  String get _formattedTime {
    final total = _elapsed.isNegative ? Duration.zero : _elapsed;
    final h = total.inHours;
    final mm = (total.inMinutes % 60).toString().padLeft(2, '0');
    final ss = (total.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// Transitions hit the network and can fail (a 409 on stale status, or lost
  /// connectivity). They were previously wired as bare VoidCallbacks, so a
  /// failure was invisible: the button appeared to work while the trip
  /// silently stayed in its old state.
  Future<void> _runAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception:', '').trim()),
          backgroundColor: AppTokens.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _callRider(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      // canLaunchUrl('tel:') returns false on Android 11+ unless the scheme
      // is declared in <queries>, which silently turned the call button into
      // a no-op. Launch directly and report failure instead of pre-checking.
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      final strings = AppStrings.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.callOpenError)),
      );
    }
  }

  Future<void> _openChat() async {
    final tripId = widget.trip['id'] as String?;
    if (tripId == null) return;
    setState(() => _unreadMessages = 0);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CaptainTripChatScreen(tripId: tripId),
      ),
    );
    // Returning from the thread: it marks everything read server-side, so
    // the badge stays cleared unless new messages land afterwards.
    if (mounted) setState(() => _unreadMessages = 0);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    final go = GoTheme.of(context);

    final status = widget.trip['status'] as String?;
    final fare = (widget.trip['final_fare'] as num?)?.toDouble() ??
        (widget.trip['estimated_fare'] as num?)?.toDouble() ??
        0;

    final heading = _headingFor(status);
    final action = _actionFor(status, state, fare, go);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: go.panel,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusXl),
        ),
        boxShadow: AppTokens.shadowSheet,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTokens.spaceLg,
            AppTokens.spaceSm,
            AppTokens.spaceLg,
            AppTokens.spaceMd,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppTokens.spaceMd),
                  decoration: BoxDecoration(
                    color: go.border,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                ),
              ),

              _StageStepper(
                stages: _stages,
                currentIndex: _stageIndex(status),
                border: go.border,
                muted: go.muted,
              ),
              const SizedBox(height: AppTokens.spaceMd),

              // Current stage + running clock.
              Row(
                children: [
                  Expanded(
                    child: Text(
                      heading,
                      style: AppTokens.font(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: go.text,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceSm,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: go.surface,
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 15, color: go.muted),
                        const SizedBox(width: 5),
                        Text(
                          _formattedTime,
                          style: AppTokens.money(
                            fontSize: 15,
                            color: go.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTokens.spaceMd),
              _buildRiderRow(go, fare),
              const SizedBox(height: AppTokens.spaceMd),
              _buildNavRow(status),
              const SizedBox(height: AppTokens.spaceXs + 2),

              SizedBox(
                width: double.infinity,
                height: AppTokens.primaryActionHeight,
                child: ElevatedButton(
                  onPressed: _busy ? null : action.onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: action.color,
                    // go.onAction is guaranteed legible on the action surface
                    // (black on lime in dark mode — white-on-lime ≈ 1.8:1).
                    foregroundColor: go.onAction,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: go.onAction,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(action.icon, size: 21),
                            const SizedBox(width: AppTokens.spaceXs),
                            Text(
                              action.label,
                              style: AppTokens.font(
                                fontSize: 16.5,
                                fontWeight: FontWeight.w800,
                                color: go.onAction,
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
    );
  }

  Widget _buildRiderRow(GoTheme go, double fare) {
    final strings = AppStrings.of(context);
    final name = (widget.trip['rider_name'] as String?)?.trim();
    final phone = (widget.trip['rider_phone'] as String?)?.trim();
    final displayName = (name == null || name.isEmpty) ? strings.riderFallbackName : name;

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: go.surface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: go.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: AppTokens.primary.withOpacity(0.14),
            child: Text(
              displayName.characters.first.toUpperCase(),
              style: AppTokens.font(
                color: AppTokens.primary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTokens.font(
                    color: go.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  widget.trip['final_fare'] != null
                      ? strings.finalFareLabel
                      : strings.estimatedFareLabel,
                  style: AppTokens.font(color: go.muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${fare.toStringAsFixed(0)} ${strings.egp}',
            style: AppTokens.money(fontSize: 22, color: AppTokens.primary),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          // In-app chat with the rider. This button was missing entirely —
          // rider messages were stored and pushed, but the captain had no
          // surface that displayed them. The badge counts rider messages
          // arriving over the live trip socket while the panel is up.
          _RoundActionButton(
            icon: Icons.chat_bubble_rounded,
            color: go.text,
            background: go.bg,
            borderColor: go.border,
            badgeCount: _unreadMessages,
            tooltip: strings.riderChatLabel,
            onTap: _openChat,
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(width: AppTokens.spaceSm),
            // A phone call is the captain's escape hatch when the pickup pin
            // is wrong, so it gets a real 48dp target rather than a text link.
            Material(
              // go.action used here so the call button matches the primary CTA
              // surface; go.onAction ensures legibility (black on lime in dark).
              color: go.action,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _callRider(phone),
                child: SizedBox(
                  width: AppTokens.tapTarget,
                  height: AppTokens.tapTarget,
                  child: Icon(Icons.call_rounded, color: go.onAction, size: 21),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavRow(String? status) {
    final strings = AppStrings.of(context);
    final headingToPickup = status == 'assigned' || status == 'arrived';
    final lat = (headingToPickup
            ? widget.trip['pickup_lat']
            : widget.trip['dropoff_lat']) as num?;
    final lng = (headingToPickup
            ? widget.trip['pickup_lng']
            : widget.trip['dropoff_lng']) as num?;

    if (lat == null || lng == null) return const SizedBox.shrink();

    // In-app navigation: keep the captain inside Tempo with the route drawn
    // on the live map, instead of deep-linking out to Google Maps. The shell
    // switches to the map tab and starts a follow-me navigation mode.
    return NavigationButton(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: headingToPickup ? strings.navToRider : strings.navToDestination,
      onPressed: () => context.read<CaptainState>().startInAppNavigation(
            lat.toDouble(),
            lng.toDouble(),
            headingToPickup,
          ),
    );
  }

  int _stageIndex(String? status) {
    final i = _stages.indexOf(status ?? '');
    return i < 0 ? 0 : i;
  }

  String _headingFor(String? status) {
    final strings = AppStrings.of(context);
    return switch (status) {
      'assigned' => strings.tripHeadingToRider,
      'arrived' => strings.tripWaitingForRider,
      'in_progress' => strings.tripInProgress,
      _ => strings.tripActiveFallback,
    };
  }

  _TripAction _actionFor(String? status, CaptainState state, double fare, GoTheme go) {
    final strings = AppStrings.of(context);
    switch (status) {
      case 'assigned':
        return _TripAction(
          label: strings.arrivedAtPickupAction,
          icon: Icons.place_rounded,
          // go.action so the CTA uses lime in dark mode instead of green,
          // which would produce near-1:1 contrast on a near-black surface.
          color: go.action,
          onPressed: () => _runAction(state.arrived),
        );
      case 'arrived':
        return _TripAction(
          label: strings.startTripAction,
          icon: Icons.play_arrow_rounded,
          color: AppTokens.success,
          onPressed: () => _runAction(state.startTrip),
        );
      case 'in_progress':
        return _TripAction(
          label: strings.endTripAction,
          icon: Icons.flag_rounded,
          color: AppTokens.accent,
          onPressed: () => _confirmComplete(state, fare),
        );
      default:
        return _TripAction(
          label: strings.tripUpdatingAction,
          icon: Icons.hourglass_top_rounded,
          color: go.action,
          onPressed: null,
        );
    }
  }

  Future<void> _confirmComplete(CaptainState state, double fare) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final strings = AppStrings.of(ctx);
        return AlertDialog(
          icon: const Icon(
            Icons.flag_circle_rounded,
            color: AppTokens.success,
            size: 34,
          ),
          title: Text(strings.endTripConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                strings.tripFareLine(fare.toStringAsFixed(2)),
                style: AppTokens.money(fontSize: 26, color: AppTokens.primary),
              ),
              const SizedBox(height: AppTokens.spaceXs),
              Text(
                strings.endTripConfirmQuestion,
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(strings.cancelAction),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.success,
                foregroundColor: Colors.white,
                minimumSize: const Size(140, AppTokens.tapTarget),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(strings.endTripConfirmYes),
            ),
          ],
        );
      },
    );
    if (ok == true) await _runAction(state.complete);
  }
}

class _TripAction {
  const _TripAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
}

/// A circular 48dp action button with an optional unread badge, matching the
/// phone-call button's hit target so both contact paths feel identical.
class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.icon,
    required this.color,
    required this.background,
    required this.borderColor,
    required this.tooltip,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final Color borderColor;
  final String tooltip;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: background,
            shape: CircleBorder(side: BorderSide(color: borderColor)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: AppTokens.tapTarget,
                height: AppTokens.tapTarget,
                child: Icon(icon, color: color, size: 21),
              ),
            ),
          ),
          if (badgeCount > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: AppTokens.danger,
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  border: Border.all(color: background, width: 1.5),
                ),
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: AppTokens.font(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Four-beat progress rail: en route → arrived → underway → done.
class _StageStepper extends StatelessWidget {
  const _StageStepper({
    required this.stages,
    required this.currentIndex,
    required this.border,
    required this.muted,
  });

  final List<String> stages;
  final int currentIndex;
  final Color border;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    final labels = [
      strings.stageEnRoute,
      strings.stageArrived,
      strings.stageUnderway,
      strings.stageDone,
    ];

    // The rail shows the three live stages plus the terminal "done" beat, so
    // the captain can see the finish line from the start.
    const total = 4;

    return Row(
      children: List.generate(total * 2 - 1, (i) {
        // Odd indices are the connectors between beats.
        if (i.isOdd) {
          final segment = i ~/ 2;
          final filled = segment < currentIndex;
          return Expanded(
            child: Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: filled ? AppTokens.primary : border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }

        final index = i ~/ 2;
        final done = index < currentIndex;
        final active = index == currentIndex;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: active ? 22 : 18,
              height: active ? 22 : 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done || active ? AppTokens.primary : Colors.transparent,
                border: Border.all(
                  color: done || active ? AppTokens.primary : border,
                  width: 2,
                ),
                boxShadow: active ? AppTokens.glow(AppTokens.primary, opacity: 0.3) : null,
              ),
              child: done
                  ? const Icon(Icons.check, size: 11, color: Colors.white)
                  : active
                      ? const Center(
                          child: SizedBox(
                            width: 7,
                            height: 7,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        )
                      : null,
            ),
            const SizedBox(height: 5),
            Text(
              labels[index],
              style: AppTokens.font(
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                color: active ? AppTokens.primary : muted,
              ),
            ),
          ],
        );
      }),
    );
  }
}
