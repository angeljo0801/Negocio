# Paquetería - backend de webhooks

Este directorio deja preparada la segunda etapa del tracking: recibir eventos `tracker.updated` de EasyPost por HTTPS y convertirlos en notificaciones push casi instantáneas.

## Flujo previsto

EasyPost -> `POST /easypost-webhook` -> validar HMAC -> localizar tracking -> enviar push al dispositivo -> Paquetería abre el paquete correspondiente.

## Requisitos para activarlo

1. Un endpoint HTTPS público para desplegar el backend.
2. `EASYPOST_WEBHOOK_SECRET` configurado como secreto del servidor.
3. Un proyecto de notificaciones push (por ejemplo Firebase Cloud Messaging) y sus credenciales solo en el servidor.
4. Registrar en EasyPost la URL pública del webhook con el mismo secreto HMAC.

No se deben guardar secretos de servidor dentro del APK ni dentro del repositorio.

Mientras este backend no esté desplegado, Paquetería 1.2 usa Android WorkManager para consultar EasyPost periódicamente y mostrar notificaciones locales cuando detecta cambios.
