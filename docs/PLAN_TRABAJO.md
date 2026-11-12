# Reparto de trabajo - Proyecto final Programación III

## Equipo

- Sergio Armero Salazar
- Maria Fernanda Mejía Ocampo
- Cristian Camilo Castañeda Benavides

## Alcance acordado

El trabajo del equipo debe seguir las [especificaciones comunes de desarrollo](ESPECIFICACIONES_DESARROLLO.md) y los [contratos de integración](CONTRATOS_INTEGRACION.md). La guía del curso está enlazada allí para consulta común.

- Sistema de coordinación de emergencias en Elixir.
- Interfaz gráfica web con Phoenix LiveView. La interfaz forma parte del alcance del grupo; Phoenix se adopta como la opción de implementación en Elixir.
- Persistencia principal en archivos de texto. No se usará MySQL: no es requisito del checklist y añadirlo no mejora el cumplimiento de persistencia textual.
- Arquitectura propuesta con un nodo web y un nodo coordinador. El coordinador es el único dueño del estado persistente; las mutaciones remotas pasan por la API del sistema.
- Uso de `|>` en cadenas legibles de transformación. Para flujos con `{:ok, dato}` / `{:error, motivo}`, usar `with` o `case` cuando deje más claro el manejo de fallos.
- Los diagramas son propuesta inicial y deben actualizarse para corresponder con el código final.

## Reparto por responsabilidad

| Integrante | Módulos y trabajo principal | Evidencia / cierre |
|---|---|---|
| **Sergio Armero Salazar** | Usuarios, conexión/desconexión, roles, permisos y registro de actividad; zonas, sectores, puntos de atención y albergues. Implementar al menos cuatro funciones recursivas útiles sobre la jerarquía territorial. Vistas LiveView de autenticación, zonas y albergues. | Se pueden autenticar roles, restringir acciones y consultar estadísticas territoriales y ocupación. Las cuatro funciones tienen casos base y recursivos explicables. |
| **Maria Fernanda Mejía Ocampo** | Personas afectadas, búsqueda, mensajes familiares, historial de estado, reportes de mascotas y coincidencias por puntaje. Vistas LiveView de personas, mensajes y mascotas. | Se reproducen búsquedas, entrega de mensajes y coincidencias; la confirmación cierra ambos reportes relacionados. |
| **Cristian Camilo Castañeda Benavides** | Necesidades y prioridades; inventario, asignaciones y transferencias; coordinador de estado con GenServer, supervisor y comunicación con el nodo web. Vistas LiveView de necesidades y recursos. | La prioridad afecta la atención; dos solicitudes concurrentes no sobreasignan el inventario; procesos se inician bajo supervisión. |
| **Trabajo compartido** | Contratos entre módulos, formato de archivos, integración de Mix/Phoenix, revisión cruzada, pruebas de integración, diagramas finales, commits y video de sustentación. | Cada integrante aporta código y commits identificables y explica su módulo en el video. |

### Dependencia compartida importante

Antes de desarrollar las vistas y módulos en paralelo, los tres acuerdan: structs y campos, IDs, roles/permisos, valores y transiciones válidas de estado, firmas públicas, formato de errores, esquema de texto y API entre Phoenix y el coordinador.

## Plan por olas

### Ola 0 - Contratos

- [x] Revisar y cerrar `docs/CONTRATOS_INTEGRACION.md` con los acuerdos confirmados.
- [x] Registrar como acuerdos los roles, transiciones y formato de persistencia confirmados.
- [x] Definir firmas públicas y estructuras de datos compartidas en `docs/CONTRATOS_INTEGRACION.md`.
- [x] Aprobar matriz de permisos y alta automática como ciudadano.
- [x] Acordar estados y transiciones de necesidades, personas, mascotas y mensajes.
- [x] Acordar snapshot JSON con Jason; si falta el archivo, iniciar con estado vacío.
- [x] Definir nombres de nodos, API remota y flujo de inicio.

### Ola 1 - Esqueleto Mix y supervisión

- [x] Crear el proyecto Mix y separar `lib/`, `priv/` y `docs/` (Phoenix LiveView).
- [x] Crear la aplicación OTP y el árbol Supervisor inicial.
- [x] Definir la estructura de estado en mapas indexados por identificador.
- [x] Definir el contrato documental de Persistencia y carga del estado; falta implementar el módulo.
- [x] Crear el esqueleto Phoenix LiveView y navegación por módulos.
- [x] Adelantar por prioridad el dominio de Sergio: usuarios/permisos, zonas/sectores/puntos, albergues y cuatro recorridos recursivos.
- [ ] Completar operaciones de dominio conectadas al coordinador, autenticación y formularios interactivos.
- [ ] Implementar persistencia JSON y recuperación del snapshot.

### Ola 2 - Dominios

- [x] Sergio: reglas puras de usuarios, roles, zonas, sectores, puntos y albergues.
- [x] Sergio: hash de contraseñas, sesiones, comprobación de permisos y cuatro recorridos recursivos.
- [x] Sergio: prototipo LiveView con formularios y cambios temporales para usuarios, zonas y albergues.
- [ ] Sergio: conectar las pantallas y el control de sesión a los comandos reales de API cuando el coordinador los atienda.
- [ ] Sergio: coordinar ingresos/salidas con la persona e historial de Maria.
- [ ] Maria Fernanda: personas, mensajes familiares, cambios de estado y mascotas.
- [ ] Maria Fernanda: función de similitud y registro de coincidencia confirmada.
- [ ] Cristian: necesidades, prioridades, recursos, asignaciones, movimientos y transferencias.
- [ ] Cada responsable: validar antes de cambiar estado; devolver resultados explícitos.

El detalle de este avance y las interfaces requeridas a los otros módulos está en `docs/OLA2_SERGIO.md`.

### Ola 3 - Persistencia e interfaz

- [ ] Persistir y recuperar registros desde archivos de texto usando la API acordada.
- [ ] Mantener efectos de archivo fuera de las funciones puras de dominio.
- [ ] Implementar vistas LiveView por dominio, con llamadas a la API y sin acceso directo a archivos.
- [x] Crear el primer prototipo de las vistas de Sergio; sus datos son temporales y deben migrarse a la API.
- [ ] Mostrar errores funcionales en la interfaz sin detener la aplicación.

### Ola 4 - Concurrencia y distribución

- [ ] Ejecutar el nodo coordinador y el nodo web de acuerdo con el contrato acordado.
- [ ] Enviar cambios al GenServer coordinador; no escribir el archivo desde dos nodos.
- [ ] Demostrar dos asignaciones simultáneas sobre inventario limitado.
- [ ] Verificar capacidad de albergue y cierre único de necesidades/reportes bajo operaciones concurrentes.

### Ola 5 - Checklist, documentación y entrega

- [ ] Marcar cada ítem del checklist del PDF solo con evidencia reproducible.
- [ ] Completar diagrama de arquitectura, modelo de datos, secuencia, árbol OTP y estructura del proyecto.
- [ ] Revisar que todos los diagramas coincidan con el código integrado.
- [ ] Grabar el video: cada integrante se presenta, explica su contribución y participa en la demostración.
- [ ] Añadir enlace del repositorio y verificar README de ejecución.

## Política del pipe `|>`

Usarlo para transformaciones donde el resultado de una función es la entrada natural de la siguiente, por ejemplo: listar necesidades → filtrar por zona → ordenar por prioridad → generar reporte. Evitar pipelines largos con escrituras, llamadas remotas y mutaciones mezcladas; esos límites deben quedar explícitos. Para validaciones encadenadas que devuelven tuplas, preferir `with` o `case`.

## Checklist de aceptación tomado del PDF

- [ ] Gestión de usuarios.
- [ ] Gestión de zonas y sectores.
- [ ] Gestión de necesidades.
- [ ] Gestión de recursos.
- [ ] Comunicación entre familiares.
- [ ] Gestión de mascotas perdidas y encontradas.
- [ ] Gestión de albergues.
- [ ] Varias estructuras de datos justificadas.
- [ ] Al menos cuatro funciones recursivas propias.
- [ ] Procesos concurrentes.
- [ ] GenServer.
- [ ] Supervisor y/o DynamicSupervisor.
- [ ] Conflicto concurrente resuelto correctamente.
- [ ] Persistencia en archivos de texto.
- [ ] Pruebas.
- [ ] Diagramas correspondientes al código final.
- [ ] Participación de todos en repositorio y sustentación.
- [ ] Decisión del grupo: interfaz gráfica funcional.
