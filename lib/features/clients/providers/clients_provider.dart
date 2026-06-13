import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/client_model.dart';
import '../../../shared/services/local_db_service.dart';

final clientsProvider =
    AsyncNotifierProvider<ClientsNotifier, List<ClientModel>>(
  ClientsNotifier.new,
);

class ClientsNotifier extends AsyncNotifier<List<ClientModel>> {
  @override
  Future<List<ClientModel>> build() => LocalDbService().getAllClients();

  Future<void> saveClient(ClientModel client) async {
    final db = LocalDbService();
    final exists = (state.valueOrNull ?? []).any((c) => c.id == client.id);
    if (exists) {
      await db.updateClient(client);
    } else {
      await db.insertClient(client);
    }
    ref.invalidateSelf();
    await future;
  }

  Future<void> deleteClient(String id) async {
    await LocalDbService().deleteClient(id);
    ref.invalidateSelf();
    await future;
  }
}
