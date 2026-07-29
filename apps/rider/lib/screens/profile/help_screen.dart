import 'package:flutter/material.dart';
import 'package:flutter_shared/flutter_shared.dart';

/// Help center — FAQ + contact support.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faqs = [
    {'q': 'كيف أطلب رحلة؟', 'a': 'افتح التطبيق، اضغط "إلى أين؟"، ابحث عن وجهتك، اختر نوع المركبة، ثم اضغط "تأكيد الطلب".'},
    {'q': 'كيف أدفع؟', 'a': 'يمكنك الدفع كاش للكابتن، أو من رصيد محفظتك بعد شحنها عبر Paymob.'},
    {'q': 'كيف ألغي رحلة؟', 'a': 'اضغط "إلغاء الرحلة" في شاشة الرحلة. قد تُطبّق رسوم إلغاء إذا تأخّر الكابتن.'},
    {'q': 'ما هي رسوم الإلغاء؟', 'a': 'الإلغاء خلال أول دقيقتين مجاني. بعدها قد تُطبّق رسوم بسيطة تعويضًا للكابتن.'},
    {'q': 'كيف أتتبّع رحلتي؟', 'a': 'بعد قبول الكابتن، ستظهر location حية على الخريطة مع ETA متجدّد.'},
    {'q': 'ماذا أفعل عند الطوارئ؟', 'a': 'اضغط زر SOS الأحمر في أعلى الشاشة أثناء الرحلة لإرسال تنبيه فوري للدعم.'},
    {'q': 'كيف أشحن المحفظة؟', 'a': 'من تبويب المحفظة، اختر "شحن الرصيد"، ثم أدخل المبلغ وادفع عبر Paymob.'},
    {'q': 'هل التطبيق متاح خارج القاهرة؟', 'a': 'نعم، نخدم القاهرة، الجيزة، الإسكندرية، ونتوسّع قريبًا لمحافظات أخرى.'},
  ];

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final panel = go.panel;
    final text = go.text;
    final muted = go.muted;
    final border = go.border;

    return Scaffold(
      appBar: AppBar(title: Text('مركز المساعدة', style: AppTokens.font(fontWeight: FontWeight.w700))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Contact support
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [AppTokens.primary, AppTokens.primaryDark]),
              borderRadius: BorderRadius.circular(AppTokens.radiusLg),
            ),
            child: Row(children: [
              const Icon(Icons.support_agent, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('تحتاج مساعدة؟', style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                Text('فريق الدعم متاح 24/7', style: AppTokens.font(fontSize: 12, color: Colors.white70)),
              ])),
              ElevatedButton(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('سيتم التواصل معك قريبًا')),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppTokens.primary),
                child: const Text('تواصل'),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          Text('الأسئلة الشائعة', style: AppTokens.font(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 12),
          ..._faqs.map((faq) => _faqCard(faq['q']!, faq['a']!, panel, text, muted, border)),
        ],
      ),
    );
  }

  Widget _faqCard(String q, String a, Color panel, Color text, Color muted, Color border) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(AppTokens.radiusLg), border: Border.all(color: border)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Text(q, style: AppTokens.font(fontSize: 14, fontWeight: FontWeight.w600, color: text)),
        children: [Text(a, style: AppTokens.font(fontSize: 13, color: muted, height: 1.5))],
      ),
    );
  }
}