import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

/// A button that opens the trip destination in Google Maps (or Waze) via
/// deep-link. Renders a prominent pill button with a navigation icon.
class NavigationButton extends StatelessWidget {
  const NavigationButton({
    super.key,
    required this.lat,
    required this.lng,
    this.label = 'تنقّل',
  });

  final double lat;
  final double lng;
  final String label;

  Future<void> _openMaps() async {
    // Try Google Maps navigation intent first
    final googleUrl = 'google.navigation:q=$lat,$lng&mode=d';
    if (await canLaunchUrl(Uri.parse(googleUrl))) {
      await launchUrl(Uri.parse(googleUrl));
      return;
    }
    // Fallback: geo: URI that lets the user pick a maps app
    final geoUrl = 'geo:$lat,$lng?q=$lat,$lng';
    if (await canLaunchUrl(Uri.parse(geoUrl))) {
      await launchUrl(Uri.parse(geoUrl));
      return;
    }
    // Last resort: web URL
    final webUrl = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    await launchUrl(Uri.parse(webUrl), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _openMaps,
        icon: const Icon(Icons.navigation, size: 20),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTokens.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
        ),
      ),
    );
  }
}