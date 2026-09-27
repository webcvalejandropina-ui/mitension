# Importación Excel

Utiliza un `.xlsx` exportado desde Mi Tensión como plantilla. No se admiten `.xls`, CSV ni JSON. Conserva la fila 1, las posiciones de las columnas y la cabecera `ID` en G. No uses fórmulas. El importador lee la primera hoja (`sheet1.xml`).

Cada fila desde la 2 representa una toma independiente, no un día ni una media. Se admiten una, dos o tres tomas por periodo y día, sin exigir tres. También se conservan más tomas si existen. Se agrupan por día y hora local: antes de las 14:00, mañana; desde las 14:00, noche. B es informativa y no anula la hora.

| Columna | Contenido | Formato |
|---|---|---|
| A | Fecha y hora | Valor de fecha/hora de Excel, no texto. Presentación según el idioma de Excel. Obligatorio. |
| B | Momento | Mañana/Noche; informativo, calculado automáticamente al importar. |
| C | Sistólica | Entero sin unidades, de 40 a 300. Obligatorio. |
| D | Diastólica | Entero sin unidades, de 30 a 200 y menor que C. Obligatorio. |
| E | Pulso | Entero de 20 a 250 o celda vacía. |
| F | Notas | Texto opcional. |
| G | ID | UUID completo y único por toma. Obligatorio. Conservar en copias para evitar duplicados. |
| H | Medicamentos | Texto opcional; se conserva sin deducir dosis. |
| I–K | Metadatos ocultos | No alterar en las copias originales. Dejar vacíos en filas nuevas creadas manualmente; no copiar metadatos de otra toma. |

Ejemplo de dos filas independientes de la misma mañana (A debe introducirse como fecha/hora real en Excel):

| A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|
| 27/09/2026 08:00 | Mañana | 120 | 80 | 65 | Primera toma | 683A774D-7F95-44C7-AED5-71D59608A7D1 | |
| 27/09/2026 08:02 | Mañana | 118 | 78 | 64 | Segunda toma | CC891F08-3298-43BD-A073-C9D1D8C7C4B8 | |

Para una sola toma basta una fila; para tres, tres filas con UUID diferentes. A las 20:55 se clasificará como noche aunque B diga mañana. Los UUID ya presentes se ignoran, sin editar registros guardados. Un archivo inválido se rechaza completo antes de guardar. Máximo de archivo: 32 MiB. Guarda las copias en privado porque contienen datos de salud.
