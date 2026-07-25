import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../models/ride_request_model.dart';
import '../../services/captain_state.dart';

class NearbyRequestsScreen extends StatefulWidget {
  const NearbyRequestsScreen({Key? key}) : super(key: key);

  @override
  State<NearbyRequestsScreen> createState() => _NearbyRequestsScreenState();
}

class _NearbyRequestsScreenState extends State<NearbyRequestsScreen> {
  List<RideRequestModel> _requests = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchRequests();
  }

  Future<void> _fetchRequests() async {
    final state = context.read<CaptainState>();
    if (state.token == null) return;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final res = await http.get(
        Uri.parse('${state.baseUrl}/captain/nearby-requests?radius=15'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${state.token}',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['requests'] as List? ?? [])
            .map((item) => RideRequestModel.fromJson(item as Map<String, dynamic>))
            .toList();

        setState(() {
          _requests = list;
        });
      } else {
        setState(() {
          _errorMessage = 'فشل تحميل عروض التوصيل القريبة';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'حدث خطأ في الاتصال بالشبكة';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _submitCounterOffer(RideRequestModel req, double price) async {
    final state = context.read<CaptainState>();
    try {
      final res = await http.post(
        Uri.parse('${state.baseUrl}/trips/${req.id}/bid'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${state.token}',
        },
        body: jsonEncode({'counterPrice': price}),
      );

      if (res.statusCode < 400) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تقديم عرض السعر (${price.toStringAsFixed(0)} ج.م) بنجاح'),
            backgroundColor: AppTokens.primary,
          ),
        );
        _fetchRequests();
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فشل تقديم العرض، قد تكون الرحلة اكتملت'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showCounterOfferBottomSheet(RideRequestModel req) {
    final customPriceController = TextEditingController(
      text: (req.offeredPrice + 10).toStringAsFixed(0),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'تقديم عرض سعر جديد',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Current Offered Price Info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTokens.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTokens.primary.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('السعر المعروض من العميل:', style: TextStyle(fontSize: 13)),
                    Text(
                      '${req.offeredPrice.toStringAsFixed(0)} ج.م',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6BB522),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              const Text('اختر زيادات سريعة أو أدخل قيمة خاصة:'),
              const SizedBox(height: 12),

              // Quick Increment Chips
              Wrap(
                spacing: 8,
                children: [5, 10, 15, 20, 30].map((inc) {
                  final calculated = req.offeredPrice + inc;
                  return ActionChip(
                    label: Text('+ $inc ج.م (${calculated.toStringAsFixed(0)})'),
                    backgroundColor: AppTokens.primary.withOpacity(0.15),
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF53585F),
                    ),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _submitCounterOffer(req, calculated);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Custom Input
              TextField(
                controller: customPriceController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'قيمة العرض المخصص (ج.م)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  suffixText: 'ج.م',
                ),
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  final parsed = double.tryParse(customPriceController.text);
                  if (parsed != null && parsed > 0) {
                    Navigator.pop(ctx);
                    _submitCounterOffer(req, parsed);
                  }
                },
                child: const Text(
                  'إرسال العرض المقترح',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('طلبات التوصيل القريبة (المزايدة)'),
          backgroundColor: AppTokens.primary,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchRequests,
              tooltip: 'تحديث العروض',
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _fetchRequests,
          color: AppTokens.primary,
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF6BB522)))
              : _errorMessage != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _fetchRequests,
                            child: const Text('إعادة المحاولة'),
                          )
                        ],
                      ),
                    )
                  : _requests.isEmpty
                      ? const Center(
                          child: Text(
                            'لا توجد طلبات توصيل قريبة منك حالياً\nابقَ متصلاً لاستقبال التنبيهات',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _requests.length,
                          itemBuilder: (ctx, idx) {
                            final req = _requests[idx];
                            return _buildRequestCard(req);
                          },
                        ),
        ),
      ),
    );
  }

  Widget _buildRequestCard(RideRequestModel req) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Rider Info Header
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTokens.primary.withOpacity(0.15),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.network(
                      req.riderAvatar,
                      width: 44,
                      height: 44,
                      errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Color(0xFF53585F)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.riderName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.near_me, size: 14, color: Color(0xFF6BB522)),
                          const SizedBox(width: 4),
                          Text(
                            'بينه وبينك ${req.captainToPickupKm.toStringAsFixed(1)} كم',
                            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Offered Price Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTokens.primary.withOpacity(0.4)),
                  ),
                  child: Text(
                    '${req.offeredPrice.toStringAsFixed(0)} ج.م',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTokens.primary,
                    ),
                  ),
                ),
              ],
            ),

            const Divider(height: 24),

            // Route Info: Origin & Destination
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    const Icon(Icons.circle, size: 12, color: Color(0xFF6BB522)),
                    Container(width: 2, height: 28, color: Colors.grey.shade300),
                    const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'من: ${req.pickupAddress}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'إلى: ${req.dropoffAddress}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'مسافة: ${req.distanceKm.toStringAsFixed(1)} كم',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF53585F)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Action Buttons Row
            Row(
              children: [
                // Instant Accept Button
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTokens.primary,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _submitCounterOffer(req, req.offeredPrice),
                    child: Text(
                      'قبول السعر (${req.offeredPrice.toStringAsFixed(0)} ج.م)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Counter-Offer Button
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF6BB522)),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _showCounterOfferBottomSheet(req),
                    child: const Text(
                      'عرض سعر آخر',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6BB522)),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Skip / Decline Button
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () {
                    setState(() {
                      _requests.removeWhere((item) => item.id == req.id);
                    });
                  },
                  tooltip: 'تجاوز',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
