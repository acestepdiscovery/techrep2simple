import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/constants/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/services/shared_clients_service.dart';
import '../models/client_model.dart';
import '../providers/clients_provider.dart';
import '../providers/shared_clients_provider.dart';

class ClientsListScreen extends ConsumerStatefulWidget {
  const ClientsListScreen({super.key});

  @override
  ConsumerState<ClientsListScreen> createState() => _ClientsListScreenState();
}

class _ClientsListScreenState extends ConsumerState<ClientsListScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openForm({ClientModel? client}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ClientFormSheet(
        existing: client,
        onSave: (c) => ref.read(clientsProvider.notifier).saveClient(c),
      ),
    );
  }

  Future<void> _confirmDelete(ClientModel client) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Supprimer ce client ?'),
        content: Text('${client.name} sera supprimé définitivement.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(clientsProvider.notifier).deleteClient(client.id);
    }
  }

  Future<void> _shareClient(ClientModel client) async {
    final teamState = ref.read(teamStateProvider).valueOrNull;
    final user = ref.read(firebaseUserProvider).valueOrNull;
    final companyId = teamState?.companyId;
    if (companyId == null || user == null) return;
    await SharedClientsService().shareClient(
      companyId,
      client,
      sharedByUid: user.uid,
      sharedByName: user.displayName ?? user.email ?? 'Admin',
    );
  }

  Future<void> _unshareClient(String clientId) async {
    final companyId = ref.read(teamStateProvider).valueOrNull?.companyId;
    if (companyId == null) return;
    await SharedClientsService().unshareClient(companyId, clientId);
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(clientsProvider);
    final teamState = ref.watch(teamStateProvider).valueOrNull;
    final isAdmin = teamState?.isAdmin ?? false;
    final isInTeam = teamState?.hasTeam ?? false;
    final sharedClients = ref.watch(sharedClientsProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                hintText: 'Rechercher un client…',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
        ),
      ),
      body: clientsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (clients) {
          final filtered = _query.isEmpty
              ? clients
              : clients
                  .where((c) =>
                      c.name.toLowerCase().contains(_query) ||
                      c.phone.toLowerCase().contains(_query) ||
                      c.email.toLowerCase().contains(_query))
                  .toList();

          final personalIds = clients.map((c) => c.id).toSet();
          final sharedIds = sharedClients.map((sc) => sc.id).toSet();

          // Shared clients visible in the shared section = not already in personal list
          final sharedToShow = sharedClients
              .where((sc) =>
                  !personalIds.contains(sc.id) &&
                  (_query.isEmpty ||
                      sc.name.toLowerCase().contains(_query) ||
                      sc.phone.toLowerCase().contains(_query) ||
                      sc.email.toLowerCase().contains(_query)))
              .toList();

          if (filtered.isEmpty && sharedToShow.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.people_outline,
                      size: 72, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    _query.isEmpty
                        ? 'Aucun client\nAppuyez sur + pour en ajouter un'
                        : 'Aucun résultat pour "$_query"',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return CustomScrollView(
            slivers: [
              if (filtered.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final c = filtered[i];
                        return Padding(
                          padding: EdgeInsets.only(
                              bottom: i < filtered.length - 1 ? 8 : 0),
                          child: _ClientCard(
                            client: c,
                            onEdit: () => _openForm(client: c),
                            onDelete: () => _confirmDelete(c),
                            isSharedByMe:
                                isAdmin && sharedIds.contains(c.id),
                            onShare: isAdmin &&
                                    isInTeam &&
                                    !sharedIds.contains(c.id)
                                ? () => _shareClient(c)
                                : null,
                            onUnshare: isAdmin &&
                                    isInTeam &&
                                    sharedIds.contains(c.id)
                                ? () => _unshareClient(c.id)
                                : null,
                          ),
                        );
                      },
                      childCount: filtered.length,
                    ),
                  ),
                ),
              if (isInTeam && sharedToShow.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Row(
                      children: [
                        Icon(Icons.group_outlined,
                            size: 15, color: Colors.teal.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Clients partagés par l\'équipe',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final sc = sharedToShow[i];
                        return Padding(
                          padding: EdgeInsets.only(
                              bottom: i < sharedToShow.length - 1 ? 8 : 0),
                          child: _SharedClientCard(
                            sharedClient: sc,
                            onUnshare:
                                isAdmin ? () => _unshareClient(sc.id) : null,
                          ),
                        );
                      },
                      childCount: sharedToShow.length,
                    ),
                  ),
                ),
              ],
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 80 + MediaQuery.of(context).viewPadding.bottom,
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_clients',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Nouveau client'),
        backgroundColor: AppColors.primary,
      ),
    );
  }
}

// ── Personal client card ──────────────────────────────────────────────────────

class _ClientCard extends StatelessWidget {
  final ClientModel client;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool isSharedByMe;
  final VoidCallback? onShare;
  final VoidCallback? onUnshare;

  const _ClientCard({
    required this.client,
    required this.onEdit,
    required this.onDelete,
    this.isSharedByMe = false,
    this.onShare,
    this.onUnshare,
  });

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                backgroundColor:
                    AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  client.name.isNotEmpty
                      ? client.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold),
                ),
              ),
              if (isSharedByMe)
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.teal.shade600,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Icon(Icons.group,
                        size: 9, color: Colors.white),
                  ),
                ),
            ],
          ),
          title: Text(client.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (client.phone.isNotEmpty)
                Text(client.phone,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              if (client.address.isNotEmpty)
                Text(client.address,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.history,
                    size: 20, color: AppColors.primary),
                tooltip: 'Historique des interventions',
                onPressed: () => context.push(
                  '/client-history/${client.id}',
                  extra: client.name,
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                  if (v == 'share') onShare?.call();
                  if (v == 'unshare') onUnshare?.call();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'edit', child: Text('Modifier')),
                  if (onShare != null)
                    PopupMenuItem(
                      value: 'share',
                      child: Row(children: [
                        Icon(Icons.group_add_outlined,
                            size: 18, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        const Text('Partager avec l\'équipe'),
                      ]),
                    ),
                  if (onUnshare != null)
                    PopupMenuItem(
                      value: 'unshare',
                      child: Row(children: [
                        Icon(Icons.group_remove_outlined,
                            size: 18, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        Text('Retirer du partage',
                            style:
                                TextStyle(color: Colors.teal.shade700)),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Supprimer',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => context.push(
            '/client-history/${client.id}',
            extra: client.name,
          ),
        ),
      );
}

// ── Shared client card (read-only for techs) ──────────────────────────────────

class _SharedClientCard extends StatelessWidget {
  final SharedClientModel sharedClient;
  final VoidCallback? onUnshare;

  const _SharedClientCard({
    required this.sharedClient,
    this.onUnshare,
  });

  @override
  Widget build(BuildContext context) => Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.teal.shade200, width: 1),
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: Colors.teal.shade50,
            child: Icon(Icons.group_outlined,
                color: Colors.teal.shade700, size: 20),
          ),
          title: Text(sharedClient.name,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sharedClient.phone.isNotEmpty)
                Text(sharedClient.phone,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              if (sharedClient.address.isNotEmpty)
                Text(sharedClient.address,
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              if (sharedClient.sharedByName.isNotEmpty)
                Text(
                  'Partagé par ${sharedClient.sharedByName}',
                  style: TextStyle(
                      color: Colors.teal.shade600,
                      fontSize: 10,
                      fontStyle: FontStyle.italic),
                ),
            ],
          ),
          trailing: onUnshare != null
              ? PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'unshare') onUnshare?.call();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'unshare',
                      child: Row(children: [
                        Icon(Icons.group_remove_outlined,
                            size: 18, color: Colors.teal.shade700),
                        const SizedBox(width: 8),
                        Text('Retirer du partage',
                            style:
                                TextStyle(color: Colors.teal.shade700)),
                      ]),
                    ),
                  ],
                )
              : null,
        ),
      );
}

// ── Client form sheet ──────────────────────────────────────────────────────────

class _ClientFormSheet extends StatefulWidget {
  final ClientModel? existing;
  final Future<void> Function(ClientModel) onSave;

  const _ClientFormSheet({this.existing, required this.onSave});

  @override
  State<_ClientFormSheet> createState() => _ClientFormSheetState();
}

class _ClientFormSheetState extends State<_ClientFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _contact;
  late final TextEditingController _contract;
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _name = TextEditingController(text: c?.name ?? '');
    _address = TextEditingController(text: c?.address ?? '');
    _phone = TextEditingController(text: c?.phone ?? '');
    _email = TextEditingController(text: c?.email ?? '');
    _contact = TextEditingController(text: c?.contactPerson ?? '');
    _contract = TextEditingController(text: c?.contractNumber ?? '');
    _notes = TextEditingController(text: c?.notes ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _address,
      _phone,
      _email,
      _contact,
      _contract,
      _notes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final client = ClientModel(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim(),
      address: _address.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      contactPerson: _contact.text.trim(),
      contractNumber: _contract.text.trim(),
      notes: _notes.text.trim(),
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );
    await widget.onSave(client);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Row(
              children: [
                Text(
                  widget.existing == null
                      ? 'Nouveau client'
                      : 'Modifier le client',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            _sheetField(
              controller: _name,
              label: 'Nom du client *',
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            _sheetField(controller: _address, label: 'Adresse'),
            _sheetField(
              controller: _phone,
              label: 'Téléphone',
              keyboardType: TextInputType.phone,
            ),
            _sheetField(
              controller: _email,
              label: 'Email',
              keyboardType: TextInputType.emailAddress,
            ),
            _sheetField(controller: _contact, label: 'Contact sur place'),
            _sheetField(controller: _contract, label: 'N° de contrat'),
            _sheetField(
              controller: _notes,
              label: 'Notes internes',
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text(widget.existing == null
                  ? 'Créer le client'
                  : 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sheetField({
  required TextEditingController controller,
  required String label,
  int maxLines = 1,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
