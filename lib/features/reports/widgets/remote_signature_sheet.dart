import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../shared/utils/share_origin.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/services/local_db_service.dart';
import '../../../shared/services/remote_signature_service.dart';
import '../../../shared/services/team_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/report_model.dart';
import '../providers/reports_provider.dart';

/// Bottom sheet that guides a tech through getting a remote client signature.
///
/// States: generating → awaiting → signed (auto-closes) | error
///
/// Pass [initialToken]/[initialCode]/[initialShareUrl] to restore a previously
/// suspended session (skip generation, go straight to awaiting).
/// Pop result: `true` = signed, `false` = cancelled, `'suspended'` = dismissed
/// without cancelling (token saved to SharedPreferences).
class RemoteSignatureSheet extends ConsumerStatefulWidget {
  final ReportModel report;
  final String? initialToken;
  final String? initialCode;
  final String? initialShareUrl;
  const RemoteSignatureSheet({
    super.key,
    required this.report,
    this.initialToken,
    this.initialCode,
    this.initialShareUrl,
  });

  @override
  ConsumerState<RemoteSignatureSheet> createState() =>
      _RemoteSignatureSheetState();
}

class _RemoteSignatureSheetState extends ConsumerState<RemoteSignatureSheet> {
  _SheetState _state = _SheetState.generating;
  String? _token;
  String? _code;
  String? _shareUrl;
  String? _error;
  StreamSubscription<Map<String, dynamic>?>? _sub;

  @override
  void initState() {
    super.initState();
    if (widget.initialToken != null) {
      _token = widget.initialToken;
      _code = widget.initialCode;
      _shareUrl = widget.initialShareUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _state = _SheetState.awaiting);
          _startListening();
        }
      });
    } else {
      _generate();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() { _state = _SheetState.generating; _error = null; });
    try {
      final uid = ref.read(firebaseUserProvider).valueOrNull?.uid ?? '';
      final team = ref.read(teamStateProvider).valueOrNull;
      final req = await RemoteSignatureService.createRequest(
        reportId: widget.report.id,
        techUid: uid,
        companyId: team?.companyId,
        clientName: widget.report.clientName,
        lang: context.locale.languageCode, // localizes the remote signature page
      );
      _token = req.token;
      _code = req.code;
      _shareUrl = req.shareUrl;
      setState(() => _state = _SheetState.awaiting);
      _startListening();
    } catch (e) {
      setState(() { _state = _SheetState.error; _error = e.toString(); });
    }
  }

  void _startListening() {
    _sub = RemoteSignatureService.streamRequest(_token!).listen((data) async {
      if (data?['status'] != 'signed') return;
      final sig = data!['signature_b64'] as String?;
      if (sig == null || sig.isEmpty) return;
      _sub?.cancel();
      await _applySignature(sig);
    });
  }

  Future<void> _applySignature(String base64Sig) async {
    try {
      final updated = widget.report.copyWith(
        signatureClientData: base64Sig,
        signedRemotely: true,
      );
      await LocalDbService().updateReport(updated);
      await ref.read(reportsProvider.notifier).refresh();

      final team = ref.read(teamStateProvider).valueOrNull;
      if (team?.companyId != null) {
        await TeamService().syncReport(team!.companyId!, updated);
      }

      if (mounted) {
        setState(() => _state = _SheetState.signed);
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() { _state = _SheetState.error; _error = e.toString(); });
    }
  }

  Future<void> _cancel() async {
    if (_token != null) {
      try { await RemoteSignatureService.cancelRequest(_token!); } catch (_) {}
    }
    if (mounted) Navigator.pop(context, false);
  }

  // Dismiss without cancelling — saves token to SharedPrefs so the detail
  // screen can show a persistent banner and re-open later.
  Future<void> _suspend() async {
    _sub?.cancel();
    if (_token != null) {
      final prefs = await SharedPreferences.getInstance();
      final id = widget.report.id;
      await prefs.setString('pending_sig_token_$id', _token!);
      await prefs.setString('pending_sig_url_$id', _shareUrl ?? '');
      await prefs.setString('pending_sig_code_$id', _code ?? '');
    }
    if (mounted) Navigator.pop(context, 'suspended');
  }

  void _share() {
    final client = widget.report.clientName.isNotEmpty
        ? widget.report.clientName
        : 'rs_dear_client'.tr();
    Share.share(
      'rs_share_text'.tr(args: [client, _shareUrl ?? '', _code ?? '']),
      sharePositionOrigin: shareOrigin(context),
    );
  }

  void _copyLink() {
    Clipboard.setData(ClipboardData(
      text: 'rs_copy_text'.tr(args: [_shareUrl ?? '', _code ?? '']),
    ));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('rs_copied'.tr())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: switch (_state) {
          _SheetState.generating => _buildGenerating(),
          _SheetState.awaiting   => _buildAwaiting(),
          _SheetState.signed     => _buildSigned(),
          _SheetState.error      => _buildError(),
        },
      ),
    );
  }

  Widget _buildGenerating() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _handle(),
      const SizedBox(height: 24),
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text('rs_generating'.tr(),
          style: const TextStyle(fontSize: 15)),
    ],
  );

  Widget _buildAwaiting() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _handle(),
      const SizedBox(height: 8),
      Text(
        'rs_title'.tr(),
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        'rs_send_to'.tr(args: [widget.report.clientName.isNotEmpty ? widget.report.clientName : 'rs_your_client'.tr()]),
        style: const TextStyle(fontSize: 13, color: Colors.black54),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),

      // Code display
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text('rs_validation_code'.tr(),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Text(
              _code ?? '',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: AppColors.primary,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'rs_enter_code_after'.tr(),
              style: const TextStyle(fontSize: 11, color: Colors.black45),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),

      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _copyLink,
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text('pw_copy'.tr()),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: _share,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text('td_share_btn'.tr()),
          ),
        ),
      ]),

      const SizedBox(height: 20),
      // Waiting indicator
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('rs_awaiting_sig'.tr(),
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ],
      ),

      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _suspend,
        icon: const Icon(Icons.arrow_back_outlined, size: 18),
        label: Text('rs_close_later'.tr()),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(44),
        ),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _cancel,
        child: Text('rs_cancel_request'.tr(),
            style: const TextStyle(color: Colors.black38, fontSize: 13)),
      ),
    ],
  );

  Widget _buildSigned() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _handle(),
      const SizedBox(height: 24),
      const Icon(Icons.check_circle_outline,
          color: Colors.green, size: 56),
      const SizedBox(height: 12),
      Text('rs_received'.tr(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
              color: Colors.green)),
      const SizedBox(height: 6),
      Text('rs_locked'.tr(),
          style: const TextStyle(color: Colors.black54)),
    ],
  );

  Widget _buildError() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _handle(),
      const SizedBox(height: 16),
      const Icon(Icons.error_outline, color: Colors.red, size: 48),
      const SizedBox(height: 8),
      Text(
        _error ?? 'rs_error_generic'.tr(),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _generate, child: Text('rs_retry'.tr())),
      TextButton(onPressed: _cancel, child: Text('common_cancel'.tr())),
    ],
  );

  Widget _handle() => Center(
    child: Container(
      width: 36, height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

enum _SheetState { generating, awaiting, signed, error }
