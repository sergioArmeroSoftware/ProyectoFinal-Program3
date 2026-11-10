# Diagramas del proyecto

## Arquitectura de módulos

`arquitectura-modulos.drawio` muestra el nodo web Phoenix LiveView separado del nodo coordinador. La fachada recibe las acciones de la interfaz y solicita los cambios al `EstadoServidor`, un GenServer supervisado que aplica funciones de dominio y persiste los cambios válidos en archivos de texto. Mantener un solo coordinador de escrituras ayuda a proteger inventario y necesidades ante operaciones concurrentes.

## Modelo conceptual de datos

`modelo-dominio.drawio` está organizado en dos páginas para mantener legibles las relaciones:

1. **Territorio y logística:** zonas, sectores, puntos de atención, albergues, estancias, necesidades, recursos, asignaciones y movimientos.
2. **Personas y comunidad:** personas afectadas, mensajes familiares, cambios de estado, reportes de mascotas, coincidencias, usuarios y actividad.

Representa structs y relaciones del dominio Elixir, no tablas SQL. Las colecciones pueden vivir en mapas indexados por identificador y los historiales en listas ordenadas. Las referencias entre contextos y páginas se expresan como IDs en los structs para evitar líneas largas que atraviesen el diagrama. La persistencia acordada es en archivos de texto. Actualizar ambos diagramas cuando el código integrado cierre los nombres y responsabilidades definitivos.
