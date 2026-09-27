# GitHub y producción son fases separadas

Repositorio público solo iOS: `webcvalejandropina-ui/mitension`. Preparación App Store independiente.

## Repositorio solo iOS

Esta copia contiene solo iOS, con historial nuevo y configuración personal anonimizada. No se borró ni reescribió el checkout original.

## Antes del primer push

- Revisar `git status`, `git diff --cached` y todos los archivos previstos para subir.
- Excluir históricos, Excel/PDF médicos, capturas con datos personales, `.env`, tokens, `.p12`, `.p8` y perfiles de firma.
- `.gitignore` no elimina secretos ya versionados ni del historial. Revisar el historial antes de publicar el repositorio existente.
- Team ID y bundle ID no son claves, pero son configuración del autor. Seleccionar un equipo propio; no subir claves ni perfiles. Se conserva la firma local para no interrumpir las pruebas del usuario.
- Esta copia no incluye rutas personales ni identificadores de dispositivos. Mantener esa exclusión en futuros cambios.
- Acordar licencia antes de añadir `LICENSE`; no se concede una licencia libre automáticamente.

## CI

`Docs/ios-ci.example.yml` es una plantilla para compilar Release sin firma y ejecutar tests. Para activarla, copiar a `.github/workflows/ios.yml` con permisos de workflows. La sesión de publicación no tiene ese permiso: CI no activada. Sin secretos de Apple, distribución ni subida de datos.

Referencia del entorno: [imagen oficial macOS 26 de GitHub Actions](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md). Revisar Xcode en el log porque el runner puede cambiar.

## App Store

Seguir `AppStore/README.md`: cuenta Apple Developer de pago, firma de distribución, bundle ID definitivo, contacto y URLs públicas, capturas sin datos reales, archivo Release actual y TestFlight. Tener código en GitHub no significa aprobación para producción.
