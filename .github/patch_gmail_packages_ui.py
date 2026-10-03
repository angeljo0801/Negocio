from pathlib import Path

p = Path('app/lib/packages.dart')
s = p.read_text()

old = "        _drop('Courier', carrier, ['Auto / Otro', 'UPS', 'FedEx', 'USPS', 'DHL', 'Amazon'].map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(), (v) => setState(() => carrier = v ?? carrier)),"
new = """        FilledButton.tonalIcon(
          onPressed: reconstructing ? null : () => reconstructFromGmail(),
          icon: reconstructing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.mail_search_outlined),
          label: Text(reconstructing ? 'Buscando en Gmail...' : 'Buscar tracking en Gmail y reconstruir compra'),
        ),
        const SizedBox(height: 12),
        TextField(controller: storeCtrl, decoration: const InputDecoration(labelText: 'Tienda detectada / tienda')),
        const SizedBox(height: 12),
        TextField(controller: orderCtrl, decoration: const InputDecoration(labelText: 'Número de orden relacionado')),
        const SizedBox(height: 12),
        TextField(controller: emailStatusCtrl, decoration: const InputDecoration(labelText: 'Estado obtenido del correo')),
        const SizedBox(height: 12),
        TextField(controller: etaCtrl, decoration: const InputDecoration(labelText: 'Entrega estimada obtenida del correo')),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _drop(
              'Courier / agencia',
              carrier,
              carriers.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              (v) => setState(() => carrier = v ?? carrier),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Administrar couriers',
            onPressed: manageCarriers,
            icon: const Icon(Icons.edit_road),
          ),
        ]),"""
if old not in s:
    raise SystemExit('static courier dropdown not found')
s = s.replace(old, new)

anchor = "        const SizedBox(height: 14),\n        if (tracking.text.trim().isNotEmpty) OutlinedButton.icon"
photos = r'''        if (emailPhotoPaths.isNotEmpty || emailPhotoUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionCard(context, 'Fotos obtenidas del correo', Icons.mail_outline, [
            const Text('Se mantienen separadas de las fotos manuales de la compra.'),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: emailPhotoPaths.length + emailPhotoUrls.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemBuilder: (_, index) {
                final local = index < emailPhotoPaths.length;
                final source = local ? emailPhotoPaths[index] : emailPhotoUrls[index - emailPhotoPaths.length];
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: local
                      ? (File(source).existsSync()
                          ? Image.file(File(source), fit: BoxFit.cover)
                          : const Center(child: Icon(Icons.broken_image_outlined)))
                      : Image.network(
                          source,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)),
                        ),
                );
              },
            ),
          ]),
        ],
        const SizedBox(height: 14),
        if (tracking.text.trim().isNotEmpty) OutlinedButton.icon'''
if anchor not in s:
    raise SystemExit('tracking official button anchor not found')
s = s.replace(anchor, photos)
p.write_text(s)
print('package Gmail UI patched')
