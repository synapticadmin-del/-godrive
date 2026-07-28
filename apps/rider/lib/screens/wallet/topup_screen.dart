import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                navigator.pop(true);
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

  @override
  Widget build(BuildContext context) {
    final go = GoTheme.of(context);
    final strings = AppStrings.of(context);

    if (_webCtrl != null) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.paymentTitle), backgroundColor: go.panel),
        body: WebViewWidget(controller: _webCtrl!),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.topUpTitle, style: AppTokens.font()),
        backgroundColor: go.panel,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.topUpAmountPrompt, style: AppTokens.font(color: go.text, fontSize: 18), textAlign: TextAlign.center),
            const SizedBox(height: 24),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: go.text, fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '0.0',
                hintStyle: TextStyle(color: go.muted),
                suffixText: strings.egp,
                suffixStyle: TextStyle(color: go.muted),
                filled: true,
                fillColor: go.surface,
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
                  : Text(strings.continuePayment, style: AppTokens.font(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
