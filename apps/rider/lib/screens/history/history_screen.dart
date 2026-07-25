import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_shared/flutter_shared.dart';
import 'package:intl/intl.dart';
import '../../services/app_state.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic> _trips = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    try {
      final res = await context.read<AppState>().apiGet('/trips/history');
      setState(() {
        _trips = res['trips'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('رحلاتي', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: AppTokens.lightPanel,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _trips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 64, color: AppTokens.lightMuted),
                      const SizedBox(height: 16),
                      Text('لا توجد رحلات سابقة', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightMuted, fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _trips.length,
                  itemBuilder: (context, index) {
                    final trip = _trips[index];
                    final date = DateTime.tryParse(trip['createdAt'] ?? '');
                    final formattedDate = date != null ? DateFormat('yyyy-MM-dd HH:mm').format(date) : '';
                    
                    return Card(
                      color: AppTokens.lightPanel,
                      margin: const EdgeInsets.only(bottom: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(formattedDate, style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightMuted)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: trip['status'] == 'completed' ? AppTokens.success.withOpacity(0.2) : AppTokens.danger.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(AppTokens.radiusSm),
                                  ),
                                  child: Text(
                                    trip['status'] == 'completed' ? 'مكتملة' : 'ملغاة',
                                    style: GoogleFonts.ibmPlexSansArabic(
                                      color: trip['status'] == 'completed' ? AppTokens.success : AppTokens.danger,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Column(
                                  children: [
                                    const Icon(Icons.circle, size: 12, color: AppTokens.primary),
                                    Container(width: 2, height: 20, color: AppTokens.lightBorder),
                                    const Icon(Icons.place, size: 12, color: AppTokens.accent),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(trip['pickupAddress'] ?? 'موقع غير معروف', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
                                      const SizedBox(height: 12),
                                      Text(trip['dropoffAddress'] ?? 'وجهة غير معروفة', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(color: AppTokens.lightBorder, height: 32),
                            Text(
                              '${trip['finalFare'] ?? trip['estimatedFare'] ?? 0} ج.م',
                              style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, fontWeight: FontWeight.bold, color: AppTokens.primary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
