# Preparación de App Store

Estado: preparación local; NO publicada, NO subida a App Store Connect y NO aprobada por Apple.

Revisión más reciente: [release-review.md](release-review.md). Los archivos de distribución y logs locales no se incluyen en el repositorio. Generar una candidata nueva antes de distribuir.

Verificación del 26 de septiembre de 2026: `ARCHIVE SUCCEEDED` en Release sin firma, en `/tmp/MiTension-Production.xcarchive`. Se comprobó que el paquete contiene AppIcon y PrivacyInfo.xcprivacy y que declara correctamente el icono y la clave de cifrado. También compilaron las variantes de desarrollo para simulador e iPhone. No se ha realizado validación de distribución con Apple ni una ronda completa de TestFlight.

## Configuración

- Identificador de ejemplo: `com.example.MiTension`. Antes de distribuir, elegir un identificador propio registrado y un equipo de firma. Esta copia pública no incluye la configuración personal de firma.
- Versión inicial: 1.0 (build 1). Incrementar build en cada subida posterior.
- Primera versión enfocada en iPhone, iOS 17 o posterior, orientación vertical. No se declara soporte nativo para iPad sin haber probado su diseño.
- Icono AppIcon: PNG RGB opaco, 1024 × 1024, sin esquinas premarcadas.
- Compilación Release con optimización y símbolos; manifiesto de privacidad incluido como recurso.
- UserDefaults se usa solo para preferencias propias: motivo CA92.1. No seguimiento ni recolección por el desarrollador en el código actual.
- Declaración de exportación: no utiliza cifrado no exento; únicamente mecanismos del sistema. Reevaluar si se añaden SDKs, redes o cifrado propio.

## Bloqueos antes de distribuir

1. Inscribirse en Apple Developer Program de pago. La cuenta actual dispone de firma de desarrollo, no se ha confirmado distribución. No existe autorización para contratar ni pagar en nombre del usuario.
2. Registrar/verificar el bundle ID y crear la ficha en App Store Connect con el equipo de pago correcto.
3. Publicar URLs funcionales de soporte y privacidad; incluir identidad real del responsable y contacto. El correo y la web están pendientes del propietario.
4. Añadir contacto de revisión, copyright, territorios, precio, cuestionario de edad y estado de comerciante cuando proceda. No se han inventado estos datos.
5. Revisar la declaración App Privacy: en esta implementación, los registros se procesan solo en el dispositivo; no hay SDKs ni servidor que los recopile. Revisar de nuevo si esto cambia.
6. Preparar capturas reales con datos sintéticos para las dimensiones vigentes exigidas por Apple. No usar el histórico médico personal del iPhone ni las capturas de Device Hub con el marco del Mac.
7. Probar en TestFlight: instalación limpia, actualización con datos, entradas inválidas, medicamentos, borrado, restauración, exportación, recordatorios, todos los idiomas (incluido árabe), texto ampliado, VoiceOver, dispositivos pequeños y cambios de zona horaria. Una compilación correcta no sustituye estas pruebas.
8. Validar y exportar el archivo con firma App Store Connect usando el equipo de pago; subirlo y esperar el procesamiento. Seleccionar ese build para revisión y confirmar el envío con el propietario.

Los documentos de esta carpeta son borradores, no URLs públicas. No se han introducido datos de prueba en el iPhone físico.

## Compilar y archivar localmente

```sh
xcodebuild -project MiTension.xcodeproj -scheme MiTension -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/MiTension-Production.xcarchive CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO archive
```

Un archivo sin firma sirve para comprobar empaquetado y recursos, pero NO se puede enviar a la tienda. Tras activar el equipo de pago, volver a archivar con firma y validar con Xcode Organizer. No compartir certificados privados ni contraseñas en el chat.

## Fuentes Apple

- [Preparación para distribución](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Envío a App Store](https://developer.apple.com/app-store/submitting/)
- [Privacidad](https://developer.apple.com/app-store/app-privacy-details/)
- [Motivos de API](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Revisión y funciones médicas](https://developer.apple.com/app-store/review/guidelines/)
- [Capturas](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
