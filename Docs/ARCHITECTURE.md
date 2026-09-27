# Arquitectura

## Recorrido de una toma

`AddReadingView` mantiene borradores → valida el lote → crea UUID individuales → `ReadingStore.add` normaliza periodo → escribe atómicamente → publica el histórico → cancela segundos avisos satisfechos.

Una escritura fallida no actualiza las pantallas ni guarda un lote parcial. Un archivo corrupto bloquea escrituras para conservar el original. Las tomas guardadas no tienen operación de edición.

## Mapa del código

| Archivo | Responsabilidad |
|---|---|
| `MiTensionApp.swift` | Entrada y almacén compartido. |
| `Models/BloodPressureReading.swift` | Tomas, medicamentos, validación, día/periodo y localización. |
| `Services/ReadingStore.swift` | Persistencia protegida, carga, eliminación e importación. |
| `Services/ExcelExport.swift` | ZIP/XML XLSX, validación y metadatos de ida/vuelta. |
| `Services/ReportPDFGenerator.swift` | Informe A4 y paginación de notas. |
| `Views/RootView.swift` | Navegación, histórico, guía, configuración y servicios de avisos/AlarmKit. |
| `Views/AddReadingView.swift` | Formulario y navegación del teclado. |
| `Views/DashboardView.swift` | Resumen, grupos reutilizables, referencias y colores adaptativos. |
| `Views/MedicalReportView.swift` | Consulta e informe PDF por periodo. |
| `Views/FeaturesView.swift` | Gráficas, menú secundario y exportación Excel. |
| `Views/BackupView.swift` | Importación y explicación de filas/columnas. |
| `Views/ShareSheet.swift` | Hoja nativa de compartir. |
| `MiTensionTests/ProductionTests.swift` | Regresiones con datos y permisos aislados. |

## Contratos importantes

Excel: cada fila es una toma, no una media. G es UUID obligatorio; los existentes no se sobrescriben. B no prevalece sobre la fecha/hora. I/K permiten conservar la fecha exacta si A no cambia; J conserva medicamentos estructurados mientras H no cambie. H modificado se conserva como texto sin deducir dosis. ZIP limitado a 32 MiB de entrada y 64 MiB de expansión, CRC comprobado y sin extracción a disco. No se admiten fórmulas ni XML externo. No es un importador universal: consultar el documento de formato.

Avisos: IDs separados para avisos principales y segundos avisos. Una toma del mismo día/periodo satisface el segundo aviso. Cola serial y número de revisión evitan que tareas antiguas reprogramen avisos cancelados. El horizonte de 21 días se renueva al abrir/activar la app y cambiar histórico/preferencias. AlarmKit desde iOS 26 tiene permiso independiente; nunca activar permisos reales desde CI.

Idiomas: `L10n` accede al catálogo y acepta enteros Unicode. Las imágenes no llevan texto incrustado; controles y etiquetas son localizados. Colores adaptativos para claro/oscuro. El PDF tiene maquetación propia, no es una captura de pantalla.

Los comentarios explican responsabilidades, contratos y motivos de seguridad. No repiten cada modificador SwiftUI: así permanece visible la lógica relevante.
