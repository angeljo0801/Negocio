# Finanzas Definitiva

Aplicación Flutter offline de contabilidad por partida doble para pequeños negocios.

## Incluye

- Libro diario con validación automática de débitos y créditos.
- Catálogo de cuentas precargado.
- Estado de Resultados, Balance General, Flujo de Efectivo, Cambios en el Patrimonio y Balance de Comprobación.
- Indicadores y comprobaciones de cuadre.
- Posición diaria con selector de fecha: efectivo, patrimonio, activos, pasivos, cuentas pendientes, inventario, ingresos, gastos y flujo diario.
- Comparación del efectivo disponible con el cierre del día anterior.
- Inventario, activos fijos, depreciación, cuentas por cobrar y pagar mediante cuentas contables.
- Exportación y uso compartido de reportes PDF.
- SQLite local: no requiere cuenta ni conexión a Internet.

## Compilar

1. Instala Flutter estable.
2. En esta carpeta ejecuta `flutter create . --platforms=android` para generar/actualizar la carpeta Android.
3. Ejecuta `flutter pub get`.
4. Ejecuta `flutter test`.
5. Ejecuta `flutter build apk --release`.

El APK quedará en `build/app/outputs/flutter-apk/app-release.apk`.

## Uso contable

Cada asiento necesita al menos dos líneas y el total de débitos debe ser igual al total de créditos. La clasificación de flujo indica si el movimiento pertenece a operación, inversión, financiamiento o no utiliza efectivo.

## Alcance

Esta versión sirve para aprendizaje y control administrativo interno. Antes de utilizar reportes para impuestos o trámites oficiales, adapte el catálogo y las reglas a la normativa del país y solicite revisión profesional.
