import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/services/shared_clients_service.dart';

final sharedClientsProvider = StreamProvider<List<SharedClientModel>>((ref) {
  final companyId = ref.watch(teamStateProvider).valueOrNull?.companyId;
  if (companyId == null) return Stream.value([]);
  return SharedClientsService().stream(companyId);
});
