# Mi Tensión para iOS

Aplicación nativa SwiftUI para registrar lecturas de un tensiómetro, consultar tendencias y preparar informes por día, mañana y noche. El iPhone no mide la presión: se introducen las lecturas del aparato. Los datos se guardan en el dispositivo; se intercambian mediante Excel `.xlsx` y se imprimen mediante PDF, no mediante JSON.

## Requisitos

- Xcode 26 o posterior (SDK de AlarmKit)
- iOS 17 o posterior

Abre `MiTension.xcodeproj`, selecciona un simulador de iPhone y pulsa Run.

Para un iPhone real, selecciona tu propio equipo en Signing & Capabilities. El Team ID del autor no concede acceso a su cuenta. No se incluyen certificados ni perfiles. Las alarmas requieren iOS 26 y permiso independiente; en versiones anteriores funcionan las notificaciones.

## Funciones y privacidad

Tomas individuales con UUID, pulso, notas y medicamentos. Formulario de una o tres tomas; importación de una, dos, tres o más filas independientes. No se editan registros guardados, solo se eliminan. El periodo es automático: antes de las 14:00, mañana; desde las 14:00, noche.

Modo claro/oscuro, guía ilustrada y diez idiomas del dispositivo: español, inglés, francés, alemán, italiano, portugués, catalán, chino simplificado, japonés y árabe.

No hay cuenta, backend, analítica ni sincronización propia. Los datos se escriben atómicamente con protección de archivos de iOS. Las copias del dispositivo pueden incluirlos según los ajustes de iOS. El JSON es solo persistencia interna/compatibilidad heredada; la interfaz de intercambio ofrece Excel. Los archivos compartidos contienen datos de salud: no subirlos a GitHub. La app no diagnostica ni recomienda dosis.

Los segundos avisos a los 30 minutos se planifican durante 21 días y se renuevan al abrir la app. No son segundas alarmas AlarmKit. Permisos, silencio y Concentración pueden afectar las notificaciones.

## Compilar y probar

Desde la raíz de este repositorio:

```sh
xcodebuild -project MiTension.xcodeproj -scheme MiTension \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# Sustituye el nombre por un simulador disponible en tu Mac.
xcodebuild -project MiTension.xcodeproj -scheme MiTension \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO test
```

No requiere Node, CocoaPods ni paquetes Swift externos. Los tests usan datos sintéticos y almacenamiento aislado, nunca el histórico real. El bundle ID `com.example.MiTension` es un ejemplo; el equipo de firma está vacío. Configura ambos con tus propios datos para ejecutar en un iPhone.

## Documentación

- [Arquitectura](Docs/ARCHITECTURE.md)
- [Preparación GitHub](Docs/GITHUB.md)
- [Formato de importación](Design/formato-importacion.md)
- [Preparación App Store, separada de GitHub](AppStore/README.md)
- [Revisión y límites de las pruebas](AppStore/release-review.md)

Este repositorio contiene solo la app iOS. No incluye el proyecto web anterior.
