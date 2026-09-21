import 'dart:math' as math;

class FinanceKnowledgeChunk {
  final String title;
  final String tags;
  final String text;
  const FinanceKnowledgeChunk(this.title, this.tags, this.text);
}

/// Local financial knowledge base.
///
/// It uses a tiny deterministic feature-hashing embedding so retrieval is fully
/// offline, very fast and does not need another neural model in RAM. The guide
/// is embedded once per app process and each query is compared by cosine
/// similarity. Critical accounting guards still live in application logic.
class FinanceKnowledge {
  static const int dimensions = 384;

  static const chunks = <FinanceKnowledgeChunk>[
    FinanceKnowledgeChunk(
      'Partida doble y equilibrio',
      'debe haber asiento cuadrar partida doble',
      '''Todo asiento debe quedar equilibrado: total Debe = total Haber. Un asiento no se considera completo si solo tiene una cuenta o si ambas cuentas son la misma. Activos y gastos normalmente aumentan por el Debe; pasivos, patrimonio e ingresos normalmente aumentan por el Haber.''',
    ),
    FinanceKnowledgeChunk(
      'No inventar datos',
      'aclarar duda falta informacion no asumir',
      '''No inventar forma de pago, origen de deuda, impuesto, fecha, contraparte ni cuenta. Si falta un dato que cambia el asiento, preguntar una sola cosa concreta antes de proponerlo. Una respuesta ambigua debe producir una aclaración, no un pseudoasiento en texto libre.''',
    ),
    FinanceKnowledgeChunk(
      'Dirección de deudas',
      'yo debo le debo me deben cobrar pagar',
      '''"Yo debo", "le debo" y "tengo que pagarle" significan una obligación del negocio y nunca Cuentas por cobrar. "Me deben", "el cliente me debe" y "me tienen que pagar" apuntan a un derecho de cobro y nunca Cuentas por pagar. La dirección de la deuda no se puede invertir.''',
    ),
    FinanceKnowledgeChunk(
      'Deuda sin origen',
      'me deben le debo deuda origen ambiguo preguntar',
      '''Decir solo "me deben 500" o "le debo 500 a alguien" no alcanza para construir el asiento completo. Hay que conocer el origen: venta a crédito, préstamo entregado o recibido, compra/gasto pendiente, adelanto u otra causa. Sin ese dato se debe aclarar antes de elegir la contrapartida.''',
    ),
    FinanceKnowledgeChunk(
      'Cuentas por cobrar 1020',
      '1020 cuentas por cobrar cliente me debe cobro',
      '''Cuentas por cobrar 1020 representa dinero que terceros deben al negocio. Aumenta al Debe cuando nace un derecho de cobro y disminuye al Haber cuando el cliente paga. No es una cuenta para representar dinero que el negocio debe a otra persona.''',
    ),
    FinanceKnowledgeChunk(
      'Cuentas por pagar 2010',
      '2010 cuentas por pagar proveedor debo deuda',
      '''Cuentas por pagar 2010 representa obligaciones comerciales pendientes. Aumenta al Haber cuando el negocio compra o incurre en un gasto a crédito; disminuye al Debe cuando se paga la obligación. El Debe de la operación original depende de lo comprado o del gasto incurrido.''',
    ),
    FinanceKnowledgeChunk(
      'Préstamo recibido',
      'prestamo recibido me prestaron 2500 efectivo',
      '''Si el negocio recibe dinero prestado: Debe Efectivo 1010 y Haber Préstamo bancario 2500 u otra cuenta de pasivo adecuada. No asumir que hubo entrada de efectivo solo porque el usuario diga que debe dinero; debe estar claro que recibió el préstamo.''',
    ),
    FinanceKnowledgeChunk(
      'Pago de préstamo',
      'pago prestamo principal interes 2500 7010',
      '''El pago de principal reduce el pasivo: Debe Préstamo 2500 / Haber Efectivo 1010. Los intereses son un gasto separado, normalmente 7010. Si un pago combina principal e interés y no se conoce el desglose, pedirlo o explicar que requiere más de dos líneas.''',
    ),
    FinanceKnowledgeChunk(
      'Dinero prestado a otra persona',
      'preste dinero amigo tercero por cobrar',
      '''Si el negocio presta dinero a una persona y espera recuperarlo, normalmente nace un activo por cobrar y sale efectivo. Debe una cuenta por cobrar adecuada / Haber Efectivo. Confirmar que fue dinero efectivamente entregado como préstamo y no una venta o un gasto pagado por otra persona.''',
    ),
    FinanceKnowledgeChunk(
      'Venta en efectivo',
      'venta contado efectivo 1010 4010',
      '''Una venta cobrada inmediatamente normalmente registra Debe Efectivo 1010 / Haber Ventas 4010. Si además debe reconocerse costo de mercancía vendida, esa parte requiere líneas adicionales y no debe forzarse a un asiento de solo dos líneas.''',
    ),
    FinanceKnowledgeChunk(
      'Venta a crédito',
      'venta credito cliente debe 1020 4010',
      '''Una venta a crédito normalmente registra Debe Cuentas por cobrar 1020 / Haber Ventas 4010. No usar este asiento si el usuario solo dice "me deben" sin explicar que el origen fue una venta.''',
    ),
    FinanceKnowledgeChunk(
      'Cobro de cliente',
      'cliente pago cobre cuenta por cobrar 1010 1020',
      '''Cuando se cobra una cuenta ya existente: Debe Efectivo 1010 / Haber Cuentas por cobrar 1020. Este cobro no crea un ingreso nuevo si el ingreso ya se reconoció cuando nació la cuenta por cobrar.''',
    ),
    FinanceKnowledgeChunk(
      'Compra de inventario',
      'mercancia inventario compra 1030 efectivo credito',
      '''Mercancía comprada para vender aumenta Inventario 1030 por el Debe. Si se paga al momento, Haber Efectivo 1010. Si queda pendiente con proveedor, Haber Cuentas por pagar 2010. El costo pasa a Costo de ventas 5010 cuando corresponda reconocer la venta.''',
    ),
    FinanceKnowledgeChunk(
      'Compra por cuenta de un cliente',
      'adelanto cliente reembolso compra por cliente',
      '''Si el negocio paga una compra por cuenta de un cliente y el cliente debe reembolsarla, normalmente es un adelanto recuperable: Debe Cuentas por cobrar 1020 / Haber Efectivo 1010, salvo que los hechos indiquen que realmente era inventario o un gasto del propio negocio.''',
    ),
    FinanceKnowledgeChunk(
      'Gastos pagados',
      'gasto operativo pague efectivo',
      '''Un gasto del negocio pagado al momento aumenta la cuenta de gasto por el Debe y reduce Efectivo 1010 por el Haber. Elegir la categoría específica si se conoce; no usar Otros gastos si el mensaje identifica claramente gasolina, alquiler, publicidad, servicios, salarios, viaje u otra categoría existente.''',
    ),
    FinanceKnowledgeChunk(
      'Gastos a crédito',
      'gasto credito pendiente pagar proveedor',
      '''Si el gasto ya ocurrió pero todavía no se ha pagado: Debe la cuenta de gasto correspondiente / Haber Cuentas por pagar 2010, si esa es la naturaleza de la obligación. El pago posterior reduce Cuentas por pagar y Efectivo.''',
    ),
    FinanceKnowledgeChunk(
      'Transporte y gasolina',
      'gasolina combustible uber taxi transporte 6060',
      '''Gasolina y transporte operativo se registran normalmente en 6060 Transporte/gasolina. Si fue pagado: Debe 6060 / Haber 1010. Si quedó pendiente, la contrapartida puede ser 2010 si corresponde.''',
    ),
    FinanceKnowledgeChunk(
      'Viajes y envíos',
      'vuelo hotel equipaje viaje envio 6070',
      '''Costos de viaje, vuelo, hotel, equipaje o envío del negocio pueden corresponder a 6070 Viajes/envíos cuando esa sea la clasificación adecuada. Distinguir entre gasto operativo y compra de un activo o inventario.''',
    ),
    FinanceKnowledgeChunk(
      'Alquiler, servicios, salarios y publicidad',
      'alquiler renta servicios luz internet salario nomina publicidad',
      '''Usar cuentas específicas cuando existan: 6010 Salarios, 6020 Alquiler, 6030 Publicidad, 6040 Servicios básicos. Confirmar si fueron pagados o quedaron por pagar, porque la contrapartida cambia.''',
    ),
    FinanceKnowledgeChunk(
      'Equipo y activos fijos',
      'maquinaria equipo computadora laptop activo fijo 1500',
      '''Una compra de equipo o maquinaria que será usada por el negocio no es gasto inmediato: normalmente Debe Maquinaria/activo 1500 y Haber Efectivo o Cuentas por pagar según se haya pagado o quedado pendiente. El desembolso suele clasificarse como inversión.''',
    ),
    FinanceKnowledgeChunk(
      'Aporte del propietario',
      'aporte capital dueno propietario 3010',
      '''Dinero aportado por el propietario al negocio: Debe Efectivo 1010 / Haber Capital aportado 3010. No registrarlo como ingreso por ventas.''',
    ),
    FinanceKnowledgeChunk(
      'Retiro del propietario',
      'retiro propietario saque dinero personal 3030',
      '''Dinero que el propietario saca para uso personal: Debe Retiros 3030 / Haber Efectivo 1010. No es un gasto operativo del negocio.''',
    ),
    FinanceKnowledgeChunk(
      'Ingresos por servicios de paquetería',
      'paqueteria envio servicio ingreso 4030',
      '''Ingresos por envíos o servicios de paquetería pueden usar 4030 Ingresos por envíos y servicios. Si se cobra al momento, Debe Efectivo; si queda pendiente de cobro, puede corresponder Cuentas por cobrar.''',
    ),
    FinanceKnowledgeChunk(
      'Remesas',
      'remesa comision 4020 principal pendiente',
      '''En remesas debe distinguirse el principal administrado de la comisión realmente ganada. La comisión puede reconocerse en 4020 cuando corresponda. No tratar automáticamente todo el dinero recibido como ingreso del negocio. Para control operativo usar también el módulo de Remesas.''',
    ),
    FinanceKnowledgeChunk(
      'Efectivo no es utilidad',
      'efectivo caja utilidad ganancia ingreso',
      '''No confundir entrada de efectivo con ingreso ni salida de efectivo con gasto. Un préstamo recibido aumenta efectivo pero no utilidad. Una venta a crédito puede generar ingreso sin entrada inmediata de efectivo. Un pago de principal de deuda reduce efectivo pero no crea un gasto nuevo.''',
    ),
    FinanceKnowledgeChunk(
      'Pagos parciales de deuda',
      'abono parcial deuda saldo restante',
      '''Un pago parcial reduce solo una parte de la obligación o del derecho de cobro. Registrar el importe efectivamente pagado/cobrado y mantener el saldo restante. No marcar toda la deuda como liquidada si queda saldo pendiente.''',
    ),
    FinanceKnowledgeChunk(
      'Depósitos y anticipos de clientes',
      'anticipo deposito cliente dinero antes servicio',
      '''Dinero recibido de un cliente antes de haber ganado el ingreso puede ser un anticipo o pasivo, no una venta definitiva. Confirmar si el servicio o venta ya se realizó antes de reconocer ingreso.''',
    ),
    FinanceKnowledgeChunk(
      'Reembolsos y devoluciones',
      'reembolso devolucion refund compra venta',
      '''Un reembolso o devolución debe revertir o ajustar la naturaleza de la operación original. Antes de proponer el asiento, identificar si se devuelve una venta, una compra, un gasto o un anticipo y cómo se pagó originalmente.''',
    ),
    FinanceKnowledgeChunk(
      'Impuestos',
      'impuesto tax 8010 obligacion legal',
      '''No inventar tasas, obligaciones ni jurisdicción. 8010 puede representar gasto de impuestos cuando corresponda, pero la clasificación exacta depende del tipo de impuesto. Para decisiones fiscales específicas puede ser necesario verificar reglas externas o consultar un profesional.''',
    ),
    FinanceKnowledgeChunk(
      'Flujo de caja',
      'operating investing financing noncash flujo caja',
      '''Clasificar flujo de caja según la naturaleza real: actividades operativas para operaciones ordinarias; investing para compra/venta de activos de largo plazo; financing para aportes, retiros y principal de préstamos; noncash cuando no hubo movimiento de efectivo.''',
    ),
    FinanceKnowledgeChunk(
      'Asientos con más de dos líneas',
      'multiples lineas asiento costo venta interes',
      '''Si una operación requiere más de un Debe o más de un Haber, no forzarla a exactamente dos líneas. Explicar que necesita un asiento compuesto o separar operaciones. Ejemplos: venta con costo de ventas, pago de préstamo con interés, impuestos retenidos o transacciones mixtas.''',
    ),
    FinanceKnowledgeChunk(
      'Moneda y conversiones',
      'usd moneda conversion tipo cambio',
      '''No inventar un tipo de cambio. Si la operación está en una moneda distinta a la contable y la conversión es necesaria, pedir el tipo de cambio o el importe convertido. Mantener claramente identificada la moneda del importe.''',
    ),
    FinanceKnowledgeChunk(
      'Separación negocio y propietario',
      'personal negocio propietario gasto personal',
      '''Distinguir operaciones del negocio de gastos personales del propietario. Un gasto personal pagado con dinero del negocio normalmente no debe clasificarse como gasto operativo; puede ser un retiro del propietario según los hechos.''',
    ),
    FinanceKnowledgeChunk(
      'Validación final del lenguaje natural',
      'revisar comparar mensaje propuesta asiento',
      '''Antes de enseñar una propuesta, comparar literalmente el significado del mensaje original con el asiento: quién pagó, quién debe a quién, qué se compró o vendió, si hubo efectivo, si quedó pendiente y si el importe coincide. Si cualquiera de estos puntos cambia la cuenta y no está claro, aclarar primero.''',
    ),
  ];

  static final List<List<double>> _vectors = chunks
      .map((c) => _embed('${c.title} ${c.tags} ${c.text}'))
      .toList(growable: false);

  static String retrieve(String query, {int topK = 6}) {
    final clean = query.trim();
    if (clean.isEmpty) return '';
    final q = _embed(clean);
    final scored = <MapEntry<int, double>>[];
    for (var i = 0; i < _vectors.length; i++) {
      var dot = 0.0;
      final v = _vectors[i];
      for (var j = 0; j < dimensions; j++) {
        dot += q[j] * v[j];
      }
      scored.add(MapEntry(i, dot));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));

    final take = math.min(topK, scored.length);
    final selected = <FinanceKnowledgeChunk>[];
    for (var i = 0; i < take; i++) {
      if (scored[i].value < 0.025 && selected.length >= 3) break;
      selected.add(chunks[scored[i].key]);
    }
    return selected
        .map((c) => '[${c.title}]\n${c.text}')
        .join('\n\n');
  }

  static List<double> _embed(String input) {
    var s = input.toLowerCase();
    const from = 'áéíóúüñ';
    const to = 'aeiouun';
    for (var i = 0; i < from.length; i++) {
      s = s.replaceAll(from[i], to[i]);
    }
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    final tokens = s.isEmpty
        ? <String>[]
        : s.split(RegExp(r'\s+')).where((e) => e.length > 1).toList();

    final v = List<double>.filled(dimensions, 0.0);
    void add(String feature, double weight) {
      final h = _hash(feature);
      final index = h % dimensions;
      final sign = (h & 0x80000000) == 0 ? 1.0 : -1.0;
      v[index] += sign * weight;
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      add('w:$token', 1.0);
      if (i + 1 < tokens.length) {
        add('b:$token_${tokens[i + 1]}', 1.35);
      }
      if (token.length >= 4) {
        for (var j = 0; j <= token.length - 3; j++) {
          add('c:${token.substring(j, j + 3)}', 0.22);
        }
      }
    }

    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final norm = math.sqrt(sum);
    if (norm > 0) {
      for (var i = 0; i < v.length; i++) {
        v[i] /= norm;
      }
    }
    return v;
  }

  static int _hash(String value) {
    var h = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      h ^= unit;
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
