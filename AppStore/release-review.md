# Revisión previa a distribución

Estado: código preparado para revisión y colaboración. No publicado en App Store, no aprobado por Apple.

## Verificación local

37 pruebas XCTest sin fallos en simulador iPhone con iOS 26.4. Compilación Release sin firma correcta del proyecto mantenido. La copia pública tiene equipo de firma vacío y bundle ID de ejemplo; debe verificarse tras configurarla en cada entorno. Los logs y archivos de distribución locales no se incluyen en GitHub.

La batería cubre persistencia atómica, conservación de archivos corruptos, UUID y medicamentos, clasificación por hora local, grupos individuales, enteros Unicode, Excel ida/vuelta y deduplicación, importación de 1/2/3 tomas de cada periodo, ZIP comprimido/corrupto, rechazo de fórmulas, PDF y paginación de notas, clientes de permisos y avisos, localización y recursos de la guía.

Las imágenes y su visor se revisaron visualmente en modo oscuro en simulador. Las pruebas automatizadas no equivalen a revisión médica, revisión lingüística profesional ni una matriz completa de accesibilidad o dispositivos.

## Límites de verificación

- Los segundos avisos se comprobaron mediante planificación y solicitudes pendientes, no esperando físicamente todos los plazos de 30 minutos.
- Las alarmas se probaron en simulador autorizado. No se certifica el audio físico ni todos los estados de silencio, Concentración y reinicio.
- No se ha completado TestFlight, distribución firmada ni validación de App Store Connect.
- Los tests de importación no cubren todos los proveedores externos de Archivos.
- Una compilación correcta no garantiza ausencia de defectos ni aprobación sanitaria.

## Antes de lanzar

1. Apple Developer Program de pago y equipo correcto.
2. Bundle ID definitivo y ficha App Store Connect.
3. Contacto e identidad del responsable, URLs públicas de soporte/privacidad, copyright, territorios, precio y cuestionarios.
4. Capturas reales con datos sintéticos y dimensiones vigentes; nunca datos del usuario.
5. TestFlight: instalación limpia/actualización, dispositivos pequeños, versiones soportadas, VoiceOver, texto ampliado y todos los idiomas.
6. Pruebas de compartir/imprimir/importar, cambios de zona horaria, horario de verano y avisos en segundo plano.
7. Archivo Release actual con firma de distribución, validación en Organizer y revisión explícita del propietario antes de enviar.

## Repetir tests

Desde la raíz del repositorio:

```sh
xcodebuild -project MiTension.xcodeproj -scheme MiTension \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test
```

Seleccionar un simulador disponible en el Mac. Los tests usan datos sintéticos y archivos temporales; no ejecutarlos con registros médicos reales.

## Referencias

- [Revisión de Apple](https://developer.apple.com/app-store/review/guidelines/es/)
- [Preparar distribución](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
- [Privacidad App Store](https://developer.apple.com/app-store/app-privacy-details/)
