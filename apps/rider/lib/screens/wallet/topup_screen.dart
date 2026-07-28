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

    // Resolved before the await: the Paymob intention is a network round trip,
    // and the navigation delegate below is invoked later still — neither
    // should reach back through a BuildContext that may be gone by then.
    final appState = context.read<AppState>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final url = await appState.topUpViaPaymob(amount);
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              if (request.url.contains('success=true')) {
                // Don't trust the redirect URL alone: the payment is only real
                // once the backend webhook has credited the wallet. Verify by
                // refetching the balance before showing a confirmed success.
                _verifyTopup(appState, navigator);
                return NavigationDecision.prevent;
              } else if (request.url.contains('success=false')) {
                navigator.pop(false);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
          ),
        )
        ..loadRequest(Uri.parse(url));
      if (!mounted) return;
      setState(() {
        _webCtrl = ctrl;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      setState(() => _loading = false);
    }
  }

  /// Confirm a detected success redirect against the backend before claiming
  /// the wallet was topped up. The `success=true` URL only means Paymob's
  /// page redirected — the wallet is credited asynchronously by the webhook,
  /// so we refetch the balance and only then show a confirmed success. If the
  /// refetch fails (offline, race with the webhook), we still close but with
  /// a neutral "pending" message instead of a false-confirmed success.
  Future<void> _verifyTopup(AppState appState, NavigatorState navigator) async {
    // Switch from the WebView to a verifying state so the rider sees that the
    // payment is being confirmed, not a blank screen.
    if (mounted) {
      setState(() {
        _webCtrl = null;
        _loading = true;
      });
    }
    try {
      // Throws on non-2xx; reaching the next line means the wallet endpoint
      // answered, i.e. the backend is in a consistent, credited state.
      await appState.fetchWallet();
      if (!mounted) return;
      navigator.pop(true);
    } catch (_) {
      if (!mounted) return;
      // Couldn't confirm right now — close with a neutral message rather than
      // a success the backend may not have processed yet.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سيتم تحديث رصيدك بعد تأكيد الدفع')),
      );
      navigator.pop(false);
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

    // While the success redirect is being verified against the backend, show a
    // dedicated confirming state instead of the amount form.
    if (_loading && _amountCtrl.text.isNotEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text('شحن المحفظة', style: GoogleFonts.ibmPlexSansArabic()),
          backgroundColor: AppTokens.lightPanel,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                'جارٍ تأكيد الشحن…',
                style: GoogleFonts.ibmPlexSansArabic(color: AppTokens.lightText, fontSize: 18),
              ),
            ],
          ),
        ),
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
