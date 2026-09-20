part of 'main.dart';

String _normalizeClientPhone(String value) =>
    value.replaceAll(RegExp(r'[^0-9+]'), '').replaceFirst(RegExp(r'^00'), '+');

String _contactPhone(Contact contact) {
  if (contact.phones.isEmpty) return '';
  for (final phone in contact.phones) {
    if (phone.isPrimary == true) return phone.number.trim();
  }
  return contact.phones.first.number.trim();
}

String _contactEmail(Contact contact) {
  if (contact.emails.isEmpty) return '';
  for (final email in contact.emails) {
    if (email.isPrimary == true) return email.address.trim();
  }
  return contact.emails.first.address.trim();
}

class ContactImportPage extends StatefulWidget {
  final List<Contact> contacts;
  const ContactImportPage({super.key, required this.contacts});

  @override
  State<ContactImportPage> createState() => _ContactImportPageState();
}

class _ContactImportPageState extends State<ContactImportPage> {
  final selected = <String>{};
  String q = '';

  String _key(Contact c, int index) =>
      c.id ?? '${c.displayName ?? ''}|${_contactPhone(c)}|$index';

  @override
  Widget build(BuildContext context) {
    final query = q.trim().toLowerCase();
    final filtered = widget.contacts.where((c) {
      final text =
          '${c.displayName ?? ''} ${_contactPhone(c)} ${_contactEmail(c)}'
              .toLowerCase();
      return query.isEmpty || text.contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Importar contactos'),
        actions: [
          TextButton(
            onPressed: filtered.isEmpty
                ? null
                : () {
                    setState(() {
                      final visibleKeys = <String>{};
                      for (var i = 0; i < widget.contacts.length; i++) {
                        final c = widget.contacts[i];
                        if (filtered.contains(c)) visibleKeys.add(_key(c, i));
                      }
                      final allSelected =
                          visibleKeys.isNotEmpty &&
                          visibleKeys.every(selected.contains);
                      if (allSelected) {
                        selected.removeAll(visibleKeys);
                      } else {
                        selected.addAll(visibleKeys);
                      }
                    });
                  },
            child: const Text('Todos'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar en tus contactos',
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No hay contactos que mostrar.'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, index) {
                      final contact = filtered[index];
                      final originalIndex = widget.contacts.indexOf(contact);
                      final key = _key(contact, originalIndex);
                      final phone = _contactPhone(contact);
                      final email = _contactEmail(contact);
                      final subtitle = [
                        if (phone.isNotEmpty) phone,
                        if (email.isNotEmpty) email,
                      ].join('\n');

                      return CheckboxListTile(
                        value: selected.contains(key),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            selected.add(key);
                          } else {
                            selected.remove(key);
                          }
                        }),
                        secondary: const CircleAvatar(
                          child: Icon(Icons.person_outline),
                        ),
                        title: Text(
                          (contact.displayName ?? '').trim().isEmpty
                              ? 'Sin nombre'
                              : contact.displayName!.trim(),
                        ),
                        subtitle:
                            subtitle.isEmpty ? null : Text(subtitle),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: selected.isEmpty
            ? null
            : () {
                final chosen = <Contact>[];
                for (var i = 0; i < widget.contacts.length; i++) {
                  final c = widget.contacts[i];
                  if (selected.contains(_key(c, i))) chosen.add(c);
                }
                Navigator.pop(context, chosen);
              },
        icon: const Icon(Icons.person_add_alt_1),
        label: Text('Crear ${selected.length} cliente(s)'),
      ),
    );
  }
}

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});
  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  List<Map<String, dynamic>> rows = [], purchases = [], payments = [];
  String q = '';
  bool importing = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([
      Store.list('clients'),
      Store.list('purchases'),
      Store.list('payments'),
    ]);
    if (!mounted) return;
    setState(() {
      rows = active(r[0]);
      purchases = active(r[1]);
      payments = active(r[2]);
    });
  }

  Future<void> importFromContacts() async {
    if (importing) return;
    setState(() => importing = true);
    try {
      final status =
          await FlutterContacts.permissions.request(PermissionType.read);
      final allowed =
          status == PermissionStatus.granted ||
          status == PermissionStatus.limited;

      if (!allowed) {
        if (!mounted) return;
        final openSettings = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Permiso de contactos'),
            content: const Text(
              'Paquetería necesita permiso para leer tus contactos solo cuando quieras importar clientes.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Abrir ajustes'),
              ),
            ],
          ),
        );
        if (openSettings == true) {
          await FlutterContacts.permissions.openSettings();
        }
        return;
      }

      final contacts = await FlutterContacts.getAll(
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
        },
      );
      contacts.sort(
        (a, b) => (a.displayName ?? '')
            .toLowerCase()
            .compareTo((b.displayName ?? '').toLowerCase()),
      );

      if (!mounted) return;
      final chosen = await Navigator.push<List<Contact>>(
        context,
        MaterialPageRoute(
          builder: (_) => ContactImportPage(contacts: contacts),
        ),
      );
      if (chosen == null || chosen.isEmpty) return;

      final allRows = await Store.list('clients');
      final liveRows = active(allRows);
      final existingPhones = liveRows
          .map((e) => _normalizeClientPhone('${e['phone'] ?? ''}'))
          .where((e) => e.isNotEmpty)
          .toSet();
      final existingEmails = liveRows
          .map((e) => '${e['email'] ?? ''}'.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();

      var created = 0;
      var duplicates = 0;
      var withoutName = 0;

      for (final contact in chosen) {
        final contactName = (contact.displayName ?? '').trim();
        if (contactName.isEmpty) {
          withoutName++;
          continue;
        }

        final contactPhone = _contactPhone(contact);
        final contactEmail = _contactEmail(contact);
        final normalizedPhone = _normalizeClientPhone(contactPhone);
        final normalizedEmail = contactEmail.trim().toLowerCase();

        final duplicate =
            (normalizedPhone.isNotEmpty &&
                existingPhones.contains(normalizedPhone)) ||
            (normalizedEmail.isNotEmpty &&
                existingEmails.contains(normalizedEmail));

        if (duplicate) {
          duplicates++;
          continue;
        }

        allRows.add({
          'id': newId(),
          'name': contactName,
          'phone': contactPhone,
          'email': contactEmail,
          'notes': 'Importado desde contactos',
          'deleted': false,
        });

        if (normalizedPhone.isNotEmpty) {
          existingPhones.add(normalizedPhone);
        }
        if (normalizedEmail.isNotEmpty) {
          existingEmails.add(normalizedEmail);
        }
        created++;
      }

      if (created > 0) {
        await Store.saveList('clients', allRows);
        await load();
      }

      if (!mounted) return;
      final details = <String>[
        '$created cliente(s) creado(s)',
        if (duplicates > 0) '$duplicates duplicado(s) omitido(s)',
        if (withoutName > 0) '$withoutName sin nombre omitido(s)',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(details.join(' · '))),
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = rows.where((e) {
      final haystack =
          '${e['name']} ${e['phone'] ?? ''} ${e['email'] ?? ''}'
              .toLowerCase();
      return haystack.contains(q.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Crear clientes desde contactos',
            onPressed: importing ? null : importFromContacts,
            icon: importing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.contacts_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar cliente',
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No hay clientes todavía.'))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final due = clientDue(
                        '${c['id']}',
                        purchases,
                        payments,
                      );
                      final phone = '${c['phone'] ?? ''}'.trim();
                      final email = '${c['email'] ?? ''}'.trim();
                      final contactLine = [
                        if (phone.isNotEmpty) phone,
                        if (email.isNotEmpty) email,
                      ].join(' · ');
                      return ListTile(
                        leading:
                            const CircleAvatar(child: Icon(Icons.person)),
                        title: Text('${c['name']}'),
                        subtitle: Text(
                          '${contactLine.isEmpty ? 'Sin teléfono' : contactLine}\nPendiente: ${money(due)}',
                        ),
                        isThreeLine: true,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClientDetailPage(
                                clientId: '${c['id']}',
                              ),
                            ),
                          );
                          load();
                        },
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      ClientEditPage(existing: c),
                                ),
                              );
                            }
                            if (v == 'delete' &&
                                await confirmDelete(
                                  context,
                                  'este cliente',
                                )) {
                              await softDelete(
                                'clients',
                                '${c['id']}',
                              );
                            }
                            load();
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Editar'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Eliminar'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ClientEditPage()),
          );
          load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Cliente'),
      ),
    );
  }
}

class ClientEditPage extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const ClientEditPage({super.key, this.existing});
  @override
  State<ClientEditPage> createState() => _ClientEditPageState();
}

class _ClientEditPageState extends State<ClientEditPage> {
  late final TextEditingController name, phone, email, notes;

  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: '${widget.existing?['name'] ?? ''}');
    phone =
        TextEditingController(text: '${widget.existing?['phone'] ?? ''}');
    email =
        TextEditingController(text: '${widget.existing?['email'] ?? ''}');
    notes =
        TextEditingController(text: '${widget.existing?['notes'] ?? ''}');
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) return;
    final rows = await Store.list('clients');
    final item = {
      'id': widget.existing?['id'] ?? newId(),
      'name': name.text.trim(),
      'phone': phone.text.trim(),
      'email': email.text.trim(),
      'notes': notes.text.trim(),
      'deleted': false,
    };
    final i = rows.indexWhere((e) => e['id'] == item['id']);
    if (i >= 0) {
      rows[i] = {...rows[i], ...item};
    } else {
      rows.add(item);
    }
    await Store.saveList('clients', rows);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.existing == null ? 'Nuevo cliente' : 'Editar cliente',
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Nombre *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration:
                  const InputDecoration(labelText: 'Teléfono / WhatsApp'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notas'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: save,
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
          ],
        ),
      );
}

class ClientDetailPage extends StatefulWidget {
  final String clientId;
  const ClientDetailPage({super.key, required this.clientId});
  @override
  State<ClientDetailPage> createState() => _ClientDetailPageState();
}

class _ClientDetailPageState extends State<ClientDetailPage> {
  Map<String, dynamic>? client;
  List<Map<String, dynamic>> recipients = [],
      purchases = [],
      packages = [],
      payments = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await Future.wait([
      Store.list('clients'),
      Store.list('recipients'),
      Store.list('purchases'),
      Store.list('packages'),
      Store.list('payments'),
    ]);
    final cs = active(r[0]);
    if (!mounted) return;
    setState(() {
      client = cs
          .where((e) => '${e['id']}' == widget.clientId)
          .cast<Map<String, dynamic>?>()
          .firstOrNull;
      recipients = active(r[1])
          .where((e) => '${e['clientId']}' == widget.clientId)
          .toList();
      purchases = active(r[2])
          .where((e) => purchaseHasClient(e, widget.clientId))
          .toList();
      packages = active(r[3])
          .where((e) => '${e['clientId']}' == widget.clientId)
          .toList();
      payments = active(r[4])
          .where((e) => '${e['clientId']}' == widget.clientId)
          .toList();
    });
  }

  Future<void> editRecipient([Map<String, dynamic>? existing]) async {
    final n =
        TextEditingController(text: '${existing?['name'] ?? ''}');
    final p =
        TextEditingController(text: '${existing?['phone'] ?? ''}');
    final province =
        TextEditingController(text: '${existing?['province'] ?? ''}');
    final address =
        TextEditingController(text: '${existing?['address'] ?? ''}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          existing == null
              ? 'Nuevo destinatario en Cuba'
              : 'Editar destinatario',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: n,
                decoration: const InputDecoration(labelText: 'Nombre'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: p,
                decoration: const InputDecoration(labelText: 'Teléfono'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: province,
                decoration:
                    const InputDecoration(labelText: 'Provincia / municipio'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: address,
                decoration: const InputDecoration(labelText: 'Dirección'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true && n.text.trim().isNotEmpty) {
      final rows = await Store.list('recipients');
      final item = {
        'id': existing?['id'] ?? newId(),
        'clientId': widget.clientId,
        'name': n.text.trim(),
        'phone': p.text.trim(),
        'province': province.text.trim(),
        'address': address.text.trim(),
        'deleted': false,
      };
      final i =
          rows.indexWhere((e) => '${e['id']}' == '${item['id']}');
      if (i >= 0) {
        rows[i] = {...rows[i], ...item};
      } else {
        rows.add(item);
      }
      await Store.saveList('recipients', rows);
      load();
    }
  }

  Future<void> addRecipient() => editRecipient();

  Future<void> editPayment([Map<String, dynamic>? existing]) async {
    final a = TextEditingController(
      text: existing == null ? '' : '${existing['amount']}',
    );
    final date =
        TextEditingController(text: '${existing?['date'] ?? today()}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existing == null ? 'Registrar pago' : 'Editar pago'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: a,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Monto'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: date,
                decoration:
                    const InputDecoration(labelText: 'Fecha (AAAA-MM-DD)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok == true && number(a.text) > 0) {
      final rows = await Store.list('payments');
      final item = {
        'id': existing?['id'] ?? newId(),
        'clientId': widget.clientId,
        'amount': number(a.text),
        'date': date.text.trim().isEmpty ? today() : date.text.trim(),
        'deleted': false,
      };
      final i =
          rows.indexWhere((e) => '${e['id']}' == '${item['id']}');
      if (i >= 0) {
        rows[i] = {...rows[i], ...item};
      } else {
        rows.add(item);
      }
      await Store.saveList('payments', rows);
      load();
    }
  }

  Future<void> addPayment() => editPayment();

  @override
  Widget build(BuildContext context) {
    if (client == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final due = purchases.fold<double>(
          0,
          (a, e) => a + purchaseAmountForClient(e, widget.clientId),
        ) -
        payments.fold<double>(
          0,
          (a, e) => a + number(e['amount']),
        );
    final clientEmail = '${client!['email'] ?? ''}'.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text('${client!['name']}'),
        actions: [
          IconButton(
            tooltip: 'Editar cliente',
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ClientEditPage(existing: client),
                ),
              );
              await load();
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _sectionCard(
            context,
            'Resumen',
            Icons.person,
            [
              Text('${client!['phone'] ?? ''}'),
              if (clientEmail.isNotEmpty) Text(clientEmail),
              Text(
                'Saldo pendiente: ${money(due)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if ('${client!['notes'] ?? ''}'.isNotEmpty)
                Text('${client!['notes']}'),
            ],
          ),
          const SizedBox(height: 10),
          _sectionCard(
            context,
            'Destinatarios en Cuba',
            Icons.location_on,
            [
              for (final r in recipients)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${r['name']}'),
                  subtitle: Text(
                    '${r['province']} · ${r['phone']}\n${r['address']}',
                  ),
                  onTap: () => editRecipient(r),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => editRecipient(r),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDelete(
                            context,
                            'este destinatario',
                          )) {
                            await softDelete(
                              'recipients',
                              '${r['id']}',
                            );
                            load();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: addRecipient,
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir destinatario'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _sectionCard(
            context,
            'Pedidos / compras',
            Icons.shopping_bag,
            [
              if (purchases.isEmpty)
                const Text('Sin compras todavía.'),
              for (final p in purchases)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${p['store']} · ${money(purchaseAmountForClient(p, widget.clientId))}',
                  ),
                  subtitle:
                      Text('${p['description']}\n${p['status']}'),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PurchaseEditPage(existing: p),
                      ),
                    );
                    await load();
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Boletín',
                        icon: const Icon(Icons.receipt_long),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BulletinPage(
                                purchase: p,
                                initialClientId: widget.clientId,
                              ),
                            ),
                          );
                          await load();
                        },
                      ),
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  PurchaseEditPage(existing: p),
                            ),
                          );
                          await load();
                        },
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _sectionCard(
            context,
            'Paquetes',
            Icons.inventory_2,
            [
              if (packages.isEmpty)
                const Text('Sin paquetes todavía.'),
              for (final p in packages)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${p['tracking']}'),
                  subtitle: Text(
                    '${p['carrier']} · ${p['status']} · ${number(p['billWeight']).toStringAsFixed(1)} lb',
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PackageEditPage(existing: p),
                      ),
                    );
                    await load();
                  },
                  trailing: IconButton(
                    tooltip: 'Editar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PackageEditPage(existing: p),
                        ),
                      );
                      await load();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _sectionCard(
            context,
            'Pagos',
            Icons.payments,
            [
              if (payments.isEmpty)
                const Text('Sin pagos registrados.'),
              for (final p in payments)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(money(number(p['amount']))),
                  subtitle: Text('${p['date'] ?? ''}'),
                  onTap: () => editPayment(p),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => editPayment(p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirmDelete(
                            context,
                            'este pago',
                          )) {
                            await softDelete(
                              'payments',
                              '${p['id']}',
                            );
                            load();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: addPayment,
                  icon: const Icon(Icons.add),
                  label: const Text('Registrar pago'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

extension FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
