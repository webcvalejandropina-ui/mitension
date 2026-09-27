# Soporte de Mi Tensión — borrador para publicar

## ¿La app mide la tensión?

No. Introduce las lecturas de un tensiómetro externo. La app sirve para guardarlas y consultar su evolución. Consulta a un profesional sanitario sobre interpretación, objetivos y tratamiento.

## ¿Dónde están mis datos?

En el almacenamiento local del iPhone. La app no requiere cuenta ni envía tu histórico a servidores del desarrollador. Si eliminas la app o cambias de dispositivo, conserva antes una copia y comprueba los ajustes de copia de iOS.

## ¿Cómo asocio medicamentos?

Al crear una toma, pulsa Añadir medicamento. Puedes registrar nombre, dosis y una nota; no son recomendaciones de tratamiento. Las tomas y medicamentos guardados no se pueden editar. Si hay un error, elimina la toma con confirmación y registra una nueva.

## ¿Cómo llevo mis datos al médico?

Abre la vista médica y utiliza Compartir o imprimir para generar el informe PDF. En Más → Cuida tu rutina, la exportación de registros es siempre Excel (.xlsx), no JSON. Esos archivos pueden incluir información de salud: compártelos solo con los destinatarios que elijas.

## ¿Cómo importo registros?

En Más → Importar registros de Excel, selecciona un .xlsx exportado por Mi Tensión. Se añaden los identificadores nuevos, sin borrar el histórico ni modificar tomas existentes. Importar el mismo archivo otra vez no duplica registros. Conserva las columnas e identificadores originales. Las exportaciones nuevas incluyen datos técnicos ocultos para recuperar fechas precisas y medicamentos completos; los Excel antiguos mantienen el texto de medicamentos sin inventar sus dosis. No se admiten archivos .xls ni hojas de otros formatos arbitrarios. Si hay registros inválidos, fórmulas en los datos importados o un archivo corrupto, la importación se rechaza sin guardar parcialmente.

## ¿Cómo activo avisos?

Con un horario activado, si no hay una toma guardada de ese día y periodo (Mañana o Noche), se programa una segunda notificación con sonido a los 30 minutos. Solo se repite una vez y se cancela al guardar la toma correctamente. Una toma de Mañana no cancela la repetición de Noche. La repetición no es una segunda alarma de AlarmKit y puede silenciarse con los ajustes de notificaciones. Se preparan los próximos 21 días y se renuevan al abrir la app, guardar/restaurar/eliminar tomas, cambiar horarios o volver a primer plano. Abre la app al menos cada tres semanas para renovar los segundos avisos; los avisos principales semanales siguen siendo recurrentes.

En iOS 26 o posterior, dentro del horario de Mañana o Noche puedes activar «Alarma sonora además de la notificación». Usa los mismos días y hora y necesita un permiso de alarmas independiente. Puede sonar en silencio o con Concentración; desactívala para recibir solo la notificación. Hay un botón «Probar alarma en 10 segundos». Si has denegado el permiso, abre Ajustes de alarmas, permite Alarmas y vuelve a Guardar. No detecta emergencias ni valores de tensión.

Abre Alertas, elige horarios y días y pulsa Guardar (siempre visible arriba). Cerrar también guarda los cambios pendientes. Permite las notificaciones cuando iOS lo solicite. Sin permiso, se conservan tus horarios y días, pero no se pueden mostrar avisos: actívalos en Ajustes y pulsa Guardar de nuevo. Si no aparecen, revisa también los modos de concentración y los ajustes de notificaciones del iPhone.

## Contacto

PENDIENTE: correo público de soporte y URL definitiva de esta página. No publicar el borrador con estos marcadores pendientes.
