import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// In-app notifications center — shows recent push + in-app notifications.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final List<_Notif> _items = [
    _Notif(icon: Icons.local_taxi, color: AppTokens.primary, title: 'رحلة مكتملة', body: 'وصلت بسلامة. الأجرة 45 ج.م.', time: 'منذ 5 دقائق', unread: true),
    _Notif(icon: Icons.local_offer, color: AppTokens.accent, title: 'عرض جديد', body: 'خصم 20% على رحلتك القادمة بكود GO20', time: 'منذ ساعة', unread: true),
    _Notif(icon: Icons.account_balance_wallet, color: AppTokens.success, title: 'تم شحن المحفظة', body: 'تم إضافة 100 ج.م إلى محفظتك.', time: 'منذ 3 ساعات', unread: false),
    _Notif(icon: Icons.star, color: AppTokens.accent, title: 'قيّم رحلتك', body: 'كيف كانت رحلتك مع الكابتن أحمد؟', time: 'أمس', unread: false),
  ];

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.notificationsTitle, style: AppTokens.font(fontWeight: FontWeight.w700)),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                for (final n in _items) {
                  n.unread = false;
                }
              });
            },
            child: Text(strings.markAllRead, style: AppTokens.font(fontSize: 12, color: AppTokens.primary)),
          ),
        ],
      ),
      body: _items.isEmpty
          ? EmptyState(icon: Icons.notifications_none, title: strings.noNotifications, subtitle: strings.notificationsWillAppearHere)
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final n = _items[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: n.unread ? n.color.withOpacity(0.05) : go.panel,
                    borderRadius: BorderRadius.circular(AppTokens.radiusLg),
                    border: Border.all(color: n.unread ? n.color.withOpacity(0.2) : go.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(color: n.color.withOpacity(0.12), borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
                        child: Icon(n.icon, color: n.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(n.title, style: AppTokens.font(fontSize: 14, fontWeight: FontWeight.w700, color: go.text)),
                                if (n.unread) ...[
                                  const SizedBox(width: 6),
                                  Container(width: 8, height: 8, decoration: BoxDecoration(color: n.color, shape: BoxShape.circle)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(n.body, style: AppTokens.font(fontSize: 13, color: go.muted, height: 1.4)),
                            const SizedBox(height: 4),
                            Text(n.time, style: AppTokens.font(fontSize: 11, color: go.muted.withOpacity(0.7))),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _Notif {
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String time;
  bool unread;
  _Notif({required this.icon, required this.color, required this.title, required this.body, required this.time, required this.unread});
}
