import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_shared/flutter_shared.dart';
import '../../services/app_state.dart';

class TopupScreen extends StatefulWidget {
  const TopupScreen({super.key});

  @override
  State<TopupScreen> createState() => _TopupScreenState();
}

class _TopupScreenState extends State<TopupScreen> {
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  WebViewController? _webCtrl;

  Future<void> _processTopup() async {
    final amountStr = _amountCtrl.text;
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return;

    setState(() => _loading = true);
    try {
      final url = await context.read<AppState>().topUpViaPaymob(amount);
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (request.url.contains('success=true')) {
                Navigator.pop(context, true);
                return NavigationDecision.prevent;
              } else if (request.url.contains('success=false')) {
                Navigator.pop(context, false);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
      setState(() {
        _webCtrl = ctrl;
        _loading = false;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_webCtrl != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('الدفع'), backgroundColor: AppTokens.lightPanel),
        body: WebViewWidget(controller: _webCtrl!),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('شحن المحفظة', style: GoogleFonts.ibmPlexSansArabic()),
        backgroundColor: AppTokens.lightPanel,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أدخل المبلغ المراد شحنه', style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText, fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0.0',
                hintStyle: const TextStyle(color: AppTokens.lightMuted),
                suffixText: 'ج.م',
                suffixStyle: const TextStyle(color: AppTokens.lightMuted),
                filled: true,
                fillColor: AppTokens.lightSurface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: _loading ? null : _processTopup,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTokens.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTokens.radiusMd)),
              ),
              child: _loading
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white))
                  : Text('متابعة الدفع', style: GoogleFonts.ibmPlexSansArabic(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
