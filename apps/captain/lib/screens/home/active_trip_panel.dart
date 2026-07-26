import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:synaptic_go_captain/services/captain_state.dart';
import 'package:url_launcher/url_launcher.dart';

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

  static const _stages = ['assigned', 'arrived', 'in_progress'];

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح تطبيق الاتصال')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<CaptainState>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panel = isDark ? AppTokens.darkPanel : Colors.white;
    final text = isDark ? AppTokens.darkText : AppTokens.lightText;
    final muted = isDark ? AppTokens.darkMuted : AppTokens.lightMuted;
    final border = isDark ? AppTokens.darkBorder : AppTokens.lightBorder;

    final status = widget.trip['status'] as String?;
    final fare = (widget.trip['final_fare'] as num?)?.toDouble() ??
        (widget.trip['estimated_fare'] as num?)?.toDouble() ??
        0;

    final heading = _headingFor(status);
    final action = _actionFor(status, state, fare);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: panel,
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
                    color: border,
                    borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  ),
                ),
              ),

              _StageStepper(
                stages: _stages,
                currentIndex: _stageIndex(status),
                border: border,
                muted: muted,
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
                        color: text,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTokens.spaceSm,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppTokens.darkSurface
                          : AppTokens.lightSurface,
                      borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 15, color: muted),
                        const SizedBox(width: 5),
                        Text(
                          _formattedTime,
                          style: AppTokens.money(
                            fontSize: 15,
                            color: text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTokens.spaceMd),
              _buildRiderRow(fare, text, muted, border, isDark),
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
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
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
                                color: Colors.white,
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

  Widget _buildRiderRow(
    double fare,
    Color text,
    Color muted,
    Color border,
    bool isDark,
  ) {
    final name = (widget.trip['rider_name'] as String?)?.trim();
    final phone = (widget.trip['rider_phone'] as String?)?.trim();
    final displayName = (name == null || name.isEmpty) ? 'راكب' : name;

    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceSm),
      decoration: BoxDecoration(
        color: isDark ? AppTokens.darkSurface : AppTokens.lightSurface,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: border),
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
                    color: text,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Text(
                  widget.trip['final_fare'] != null
                      ? 'الأجرة النهائية'
                      : 'الأجرة المقدرة',
                  style: AppTokens.font(color: muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Text(
            '${fare.toStringAsFixed(0)} ج.م',
            style: AppTokens.money(fontSize: 22, color: AppTokens.primary),
          ),
          if (phone != null && phone.isNotEmpty) ...[
            const SizedBox(width: AppTokens.spaceSm),
            // A phone call is the captain's escape hatch when the pickup pin
            // is wrong, so it gets a real 48dp target rather than a text link.
            Material(
              color: AppTokens.primary,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _callRider(phone),
                child: const SizedBox(
                  width: AppTokens.tapTarget,
                  height: AppTokens.tapTarget,
                  child: Icon(Icons.call_rounded, color: Colors.white, size: 21),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNavRow(String? status) {
    final headingToPickup = status == 'assigned' || status == 'arrived';
    final lat = (headingToPickup
            ? widget.trip['pickup_lat']
            : widget.trip['dropoff_lat']) as num?;
    final lng = (headingToPickup
            ? widget.trip['pickup_lng']
            : widget.trip['dropoff_lng']) as num?;

    if (lat == null || lng == null) return const SizedBox.shrink();

    return NavigationButton(
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      label: headingToPickup ? 'تنقّل إلى الراكب' : 'تنقّل إلى الوجهة',
    );
  }

  int _stageIndex(String? status) {
    final i = _stages.indexOf(status ?? '');
    return i < 0 ? 0 : i;
  }

  String _headingFor(String? status) => switch (status) {
        'assigned' => 'في الطريق إلى الراكب',
        'arrived' => 'في انتظار الراكب',
        'in_progress' => 'الرحلة جارية',
        _ => 'رحلة نشطة',
      };

  _TripAction _actionFor(String? status, CaptainState state, double fare) {
    switch (status) {
      case 'assigned':
        return _TripAction(
          label: 'وصلت لنقطة الالتقاط',
          icon: Icons.place_rounded,
          color: AppTokens.primary,
          onPressed: () => _runAction(state.arrived),
        );
      case 'arrived':
        return _TripAction(
          label: 'بدء الرحلة',
          icon: Icons.play_arrow_rounded,
          color: AppTokens.success,
          onPressed: () => _runAction(state.startTrip),
        );
      case 'in_progress':
        return _TripAction(
          label: 'إنهاء الرحلة',
          icon: Icons.flag_rounded,
          color: AppTokens.accent,
          onPressed: () => _confirmComplete(state, fare),
        );
      default:
        return const _TripAction(
          label: 'جارٍ التحديث…',
          icon: Icons.hourglass_top_rounded,
          color: AppTokens.primary,
          onPressed: null,
        );
    }
  }

  Future<void> _confirmComplete(CaptainState state, double fare) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.flag_circle_rounded,
          color: AppTokens.success,
          size: 34,
        ),
        title: const Text('تأكيد إنهاء الرحلة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'الأجرة: ${fare.toStringAsFixed(2)} ج.م',
              style: AppTokens.money(fontSize: 26, color: AppTokens.primary),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            const Text(
              'هل وصلت بالفعل إلى نقطة الوصول؟',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTokens.success,
              foregroundColor: Colors.white,
              minimumSize: const Size(140, AppTokens.tapTarget),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إنهاء'),
          ),
        ],
      ),
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

  static const _labels = ['في الطريق', 'وصلت', 'جارية', 'اكتملت'];

  @override
  Widget build(BuildContext context) {
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
              _labels[index],
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
