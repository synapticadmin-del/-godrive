import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:share_plus/share_plus.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/app_state.dart';

class SosScreen extends StatefulWidget {
  final String tripId;
  const SosScreen({super.key, required this.tripId});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  bool _loading = false;

  Future<void> _triggerSos() async {
    // Resolved before the confirmation dialog — the dialog is itself an await,
    // and every geolocation and network call after it yields again. Capturing
    // up front means nothing here reaches back into a BuildContext that may
    // have been disposed while the SOS was in flight.
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final strings = AppStrings.of(context);
    final go = GoTheme.of(context);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: go.panel,
        title: Text(strings.sosWarningTitle, style: AppTokens.font(color: AppTokens.danger)),
        content: Text(strings.sosConfirmMessage, style: AppTokens.font(color: go.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(strings.cancelAction)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTokens.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(strings.sosConfirmAction, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    // The rider may have left the screen while the dialog was open.
    if (!mounted) return;

    setState(() => _loading = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(strings.sosLocationServiceError);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception(strings.sosLocationPermissionError);
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
      } catch (_) {
        pos = await Geolocator.getLastKnownPosition();
      }
      if (pos == null) {
        throw Exception(strings.sosLocationUnavailableError);
      }

      await appState.apiPost('/safety/sos', {
        'tripId': widget.tripId,
        'lat': pos.latitude,
        'lng': pos.longitude,
      });
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(strings.sosSentSuccess)));
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _shareTrip() async {
    try {
      final res = await context.read<AppState>().apiPost(
        '/safety/share',
        {'tripId': widget.tripId},
      );
      final url = res['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception(strings.shareTripError);
      }
      await Share.share('${strings.shareTripMessage}$url');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.safetyTitle, style: AppTokens.font()),
        backgroundColor: go.panel,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              onTap: _loading ? null : _triggerSos,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTokens.danger,
                  boxShadow: [
                    BoxShadow(color: AppTokens.danger.withOpacity(0.5), blurRadius: 40, spreadRadius: 10),
                  ],
                ),
                child: Center(
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text('SOS', style: AppTokens.font(fontSize: 48, fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 48),
            Text(
              strings.sosEmergencyOnlyHint,
              style: AppTokens.font(color: go.muted, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _shareTrip,
              icon: const Icon(Icons.share, color: Colors.white),
              label: Text(strings.shareTripDetails, style: AppTokens.font(color: Colors.white, fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
