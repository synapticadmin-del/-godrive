import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class CaptainBidsSheet extends StatefulWidget {
  final String tripId;
  final String token;
  final String baseUrl;
  final Function(Map<String, dynamic> trip) onBidAccepted;

  const CaptainBidsSheet({
    Key? key,
    required this.tripId,
    required this.token,
    required this.baseUrl,
    required this.onBidAccepted,
  }) : super(key: key);

  @override
  State<CaptainBidsSheet> createState() => _CaptainBidsSheetState();
}

class _CaptainBidsSheetState extends State<CaptainBidsSheet> {
  List<Map<String, dynamic>> _bids = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchBids();
  }

  Future<void> _fetchBids() async {
    try {
      final res = await http.get(
        Uri.parse('${widget.baseUrl}/trips/${widget.tripId}/bids'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _bids = List<Map<String, dynamic>>.from(data['bids'] ?? []);
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _acceptBid(String bidId) async {
    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/trips/${widget.tripId}/accept-bid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({'bidId': bidId}),
      );

      if (res.statusCode < 400) {
        final data = jsonDecode(res.body);
        widget.onBidAccepted(data['trip']);
        if (mounted) Navigator.pop(context);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل قبول العرض، حاول مرة أخرى'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'عروض السعر المقدمة من الكباتن',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _fetchBids,
                  tooltip: 'تحديث العروض',
                ),
              ],
            ),
            const SizedBox(height: 12),

            _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6BB522)))
                : _bids.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'جاري البحث عن كباتن وقبول عروض أسعار جديدة...',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: _bids.length,
                        itemBuilder: (ctx, idx) {
                          final bid = _bids[idx];
                          final counterPrice = (bid['counter_price'] as num).toDouble();
                          final captainName = bid['captain_name'] ?? 'كابتن GoDrive';
                          final rating = (bid['rating_avg'] as num? ?? 5.0).toDouble();
                          final vehicleMake = bid['vehicle_make'] ?? 'سيارة';
                          final vehicleModel = bid['vehicle_model'] ?? '';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFF6BB522).withOpacity(0.2),
                                  child: const Icon(Icons.person, color: Color(0xFF53585F)),
                                ),
                                const SizedBox(width: 10),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        captainName,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(Icons.star, size: 14, color: Colors.amber),
                                          const SizedBox(width: 2),
                                          Text(
                                            rating.toStringAsFixed(1),
                                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '$vehicleMake $vehicleModel',
                                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Price & Accept Button
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${counterPrice.toStringAsFixed(0)} ج.م',
                                      style: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.black,
                                        color: Color(0xFF6BB522),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF6BB522),
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      onPressed: () => _acceptBid(bid['id'] as String),
                                      child: const Text(
                                        'قبول الكابتن',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ],
        ),
      ),
    );
  }
}
