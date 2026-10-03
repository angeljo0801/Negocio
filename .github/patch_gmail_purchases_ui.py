from pathlib import Path

p = Path('app/lib/purchases.dart')
s = p.read_text()

old = "        TextField(controller: order, decoration: const InputDecoration(labelText: 'Número de pedido (opcional)')),"
new = """        TextField(
          controller: order,
          decoration: InputDecoration(
            labelText: 'Número de pedido / orden (opcional)',
            suffixIcon: IconButton(
              tooltip: 'Buscar esta orden en Gmail',
              onPressed: gmailLoading ? null : () => reconstructFromGmail(),
              icon: gmailLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.mail_search_outlined),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: trackingCtrl, decoration: const InputDecoration(labelText: 'Trackings detectados (separados por coma)')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: subtotalCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Subtotal'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: taxCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Impuestos'))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: TextField(controller: shippingCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Envío'))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: discountCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Descuento'))),
        ]),
        const SizedBox(height: 12),
        TextField(controller: currencyCtrl, decoration: const InputDecoration(labelText: 'Moneda')),
        const SizedBox(height: 12),
        TextField(controller: emailStatusCtrl, decoration: const InputDecoration(labelText: 'Estado según Gmail')),
        const SizedBox(height: 12),
        TextField(controller: etaCtrl, decoration: const InputDecoration(labelText: 'Entrega estimada')),
        const SizedBox(height: 12),
        TextField(controller: shipToCtrl, decoration: const InputDecoration(labelText: 'Nombre / destinatario detectado en el correo')),"""
if old not in s:
    raise SystemExit('order field anchor missing')
s = s.replace(old, new)

old = """          Card(
            child: ListTile(
              title: Text('${e['name']}'),
              subtitle: Text('${clientName(clients, '${e['clientId']}')} · x${number(e['qty']).toStringAsFixed(number(e['qty']) % 1 == 0 ? 0 : 2)}'),
              trailing: Wrap(children: [
                Text(money(number(e['price']) * number(e['qty'] ?? 1))),"""
new = """          Card(
            child: ListTile(
              leading: Checkbox(
                value: e['received'] == true,
                onChanged: (v) => setState(() => e['received'] = v == true),
              ),
              title: Text('${e['name']}'),
              subtitle: Text('${clientName(clients, '${e['clientId']}')} · x${number(e['qty']).toStringAsFixed(number(e['qty']) % 1 == 0 ? 0 : 2)} · ${money(number(e['price']))} c/u'),
              trailing: Wrap(children: [
                Text(money(number(e['price']) * number(e['qty'] ?? 1))),"""
if old not in s:
    raise SystemExit('item card anchor missing')
s = s.replace(old, new)

anchor = "        const SizedBox(height: 12),\n        FilledButton.tonalIcon(\n          onPressed: importReceipt,"
email_photos = r'''        const SizedBox(height: 18),
        Row(children: [
          const Expanded(child: Text('Fotos obtenidas del correo', style: TextStyle(fontWeight: FontWeight.bold))),
          Text('${emailPhotoPaths.length + emailPhotoUrls.length}'),
        ]),
        const SizedBox(height: 6),
        const Text('Estas imágenes vienen de Gmail y se mantienen separadas de las fotos que añades manualmente.'),
        const SizedBox(height: 10),
        if (emailPhotoPaths.isEmpty && emailPhotoUrls.isEmpty)
          const Text('Todavía no hay fotos recuperadas del correo.', style: TextStyle(fontSize: 12)),
        if (emailPhotoPaths.isNotEmpty || emailPhotoUrls.isNotEmpty)
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
              return Stack(fit: StackFit.expand, children: [
                ClipRRect(
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
                ),
                Positioned(
                  right: 2,
                  top: 2,
                  child: IconButton.filled(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Quitar de esta compra',
                    onPressed: () => setState(() {
                      if (local) {
                        emailPhotoPaths.removeAt(index);
                      } else {
                        emailPhotoUrls.removeAt(index - emailPhotoPaths.length);
                      }
                    }),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ]);
            },
          ),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: importReceipt,'''
if anchor not in s:
    raise SystemExit('receipt button anchor missing')
s = s.replace(anchor, email_photos)
p.write_text(s)
print('purchase Gmail UI patched')
