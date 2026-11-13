# Ola 0 - Contratos de integración

**Estado:** Ola 0 cerrada con los acuerdos confirmados por el equipo: alta automática con rol ciudadano, matriz de permisos, transiciones, persistencia JSON con Jason, structs, firmas públicas y arquitectura web/coordinador.

## 1. Acuerdos ya tomados por el equipo

- Lenguaje y curso: Elixir, siguiendo `ESTANDARES_CODIGO.md` y las guías del profesor.
- Interfaz gráfica web con Phoenix LiveView incluida en el alcance del grupo.
- Persistencia en archivos de texto; MySQL queda fuera del alcance.
- Uso de `|>` para secuencias lineales de transformación; `with` / `case` para caminos de error y ramificaciones.
- Equipo: Sergio Armero Salazar, Maria Fernanda Mejía Ocampo y Cristian Camilo Castañeda Benavides.
- Arquitectura de partida: nodo web + nodo coordinador, con un único coordinador dueño del estado compartido.

## 2. Modelo de estado compartido

Las siguientes entidades se modelan como structs Elixir. Las colecciones se mantienen en mapas indexados por identificador para buscar y actualizar sin recorrer listas completas; los historiales ordenados se mantienen como listas.

| Struct | Campos compartidos iniciales | Índice / relación |
|---|---|---|
| `Usuario` | `username`, `password_hash`, `nombre_completo`, `rol`, `zona_principal`, `activo` | `username` único |
| `Zona` | `codigo`, `nombre`, `nivel_afectacion`, `personas_estimadas`, `sectores` | `codigo` único; contiene sectores |
| `Sector` | `codigo`, `nombre`, `puntos` | contenido por una zona |
| `PuntoAtencion` | `codigo`, `nombre`, `personas_estimadas`, `estado` | contenido por un sector |
| `Necesidad` | `id`, `tipo`, `descripcion`, `cantidad`, `prioridad`, `zona_codigo`, `responsable_id`, `estado` | `id` único; zona y responsable por ID |
| `Recurso` | `codigo`, `nombre`, `categoria`, `cantidad_disponible`, `unidad`, `ubicacion`, `zona_codigo` | código único con formato `R-01` (`R-` y dos dígitos) |
| `AsignacionRecurso` | `id`, `necesidad_id`, `recurso_codigo`, `cantidad`, `estado`, `asignado_por`, `fecha` | enlaza una necesidad con un recurso |
| `MovimientoRecurso` | `id`, `recurso_codigo`, `origen`, `destino`, `cantidad`, `fecha`, `usuario_id` | historial de inventario |
| `PersonaAfectada` | `id`, `nombre`, `documento_referencia`, `edad`, `zona_codigo`, `estado` | `id` único |
| `MensajeFamiliar` | `id`, `persona_id`, `fecha`, `remitente`, `destinatario`, `contenido`, `estado` | pertenece a una persona |
| `CambioEstadoPersona` | `id`, `persona_id`, `estado_anterior`, `estado_nuevo`, `fecha`, `usuario_id` | historial ordenado por fecha |
| `ReporteMascota` | `id`, `tipo_reporte`, `especie`, `nombre`, `caracteristicas`, `color`, `tamano`, `zona_codigo`, `contacto`, `estado` | `id` único |
| `CoincidenciaMascota` | `id`, `reporte_perdida_id`, `reporte_encontrada_id`, `puntaje`, `estado`, `confirmada_por`, `fecha` | enlaza los dos reportes |
| `Albergue` | `codigo`, `nombre`, `zona_codigo`, `capacidad_maxima` | `codigo` único |
| `EstanciaAlbergue` | `id`, `albergue_codigo`, `persona_id`, `fecha_ingreso`, `fecha_salida` | la ocupación actual se deriva de estancias activas |
| `RegistroActividad` | `id`, `username`, `accion`, `entidad_id`, `fecha` | lista ordenada de auditoría |

### Estado inicial del coordinador

`Emergencias.Estado` contiene los mapas de registros (`usuarios_por_username`, `zonas_por_codigo`, `necesidades_por_id`, `recursos_por_codigo`, `personas_por_id`, `mensajes_por_id`, `reportes_mascotas_por_id`, `albergues_por_codigo`, `asignaciones_por_id`, `movimientos_por_id`, `estancias_por_id`) y las listas de historiales y actividad. Las sesiones conectadas son estado transitorio y no se escriben al archivo.

La jerarquía de zona, sector y punto de atención queda anidada como en el diagrama aprobado, para que sus consultas y estadísticas puedan recorrerse recursivamente.

Para la primera implementación, los niveles de afectación de una zona son `:baja`, `:media`, `:alta` y `:critica`; los estados de punto de atención son `:activo`, `:inactivo` y `:saturado`. Capacidades y estimados aceptan cero, pero nunca valores negativos.

Los códigos usan prefijos mayúsculos y dos dígitos: zona `Z-01`, sector `SEC-01`, punto de atención `PA-01` y albergue `A-01`. El formulario valida mientras se escribe y el módulo de dominio repite la validación al procesar el comando. Las referencias de zona se seleccionan de zonas existentes; nunca se aceptan como números aislados como `1`.

## 3. Interfaz pública entre LiveView y el coordinador

LiveView llama a `Emergencias.API`; no accede directamente a los archivos ni modifica el estado.

```elixir
Emergencias.API.conectar(attrs)
# attrs nuevo usuario: %{username: ..., password: ..., nombre_completo: ..., zona_principal: ...}
# existente: %{username: ..., password: ...}
# {:ok, %{session_id: id, usuario: usuario_publico}} | {:error, motivo}

Emergencias.API.desconectar(session_id)
# :ok | {:error, motivo}

Emergencias.API.ejecutar(session_id, comando)
# {:ok, resultado} | {:error, motivo}

Emergencias.API.consultar(session_id, consulta)
# {:ok, resultado} | {:error, motivo}
```

Comandos de dominio iniciales, enviados como tuplas para mantener un contrato pequeño:

```elixir
{:registrar_necesidad, attrs}
{:cambiar_estado_necesidad, necesidad_id, estado}
{:registrar_recurso, attrs}
{:ingresar_recurso, recurso_codigo, cantidad}
{:asignar_recurso, necesidad_id, recurso_codigo, cantidad}
{:transferir_recurso, recurso_codigo, origen, destino, cantidad}
{:reportar_persona, attrs}
{:enviar_mensaje_familiar, persona_id, attrs}
{:reportar_mascota, attrs}
{:confirmar_coincidencia_mascota, reporte_perdida_id, reporte_encontrada_id}
{:registrar_albergue, attrs}
{:registrar_entrada_albergue, albergue_codigo, persona_id}
{:registrar_salida_albergue, albergue_codigo, persona_id}
```

Consulta de identidad aprobada para la etapa 6, fase B:

```elixir
Emergencias.API.consultar(session_id, :sesion_actual)
# {:ok, usuario_publico} | {:error, :sesion_invalida}
```

Devuelve exclusivamente el usuario público de la sesión autenticada, con el formato
existente de `Usuarios.usuario_publico/1`, sin `password_hash`. No acepta un username
ni permite consultar otra identidad. Reutiliza la validación de sesión y cuenta activa
del coordinador; no crea sesiones ni cambia las firmas de la API. Debe comunicarse
a Sergio y Cristian junto con la ruta `/personas` y sus componentes visuales antes
de integrar en la rama principal. La autenticación web sigue pendiente de Sergio.

Operaciones adicionales de personas aprobadas para la etapa 3:

```elixir
Emergencias.API.ejecutar(session_id, {:cambiar_estado_persona, persona_id, estado})
Emergencias.API.consultar(session_id, {:personas, filtros})
Emergencias.API.consultar(session_id, {:persona, persona_id})
Emergencias.API.consultar(session_id, {:personas_por_documento, documento})
Emergencias.API.consultar(session_id, {:historial_persona, persona_id})
```

Los filtros de personas aceptan `zona_codigo` y `estado`. Las búsquedas por documento
devuelven una lista; las consultas por ID devuelven una persona. Los listados se
ordenan por ID y el historial por fecha ascendente. Todas las respuestas usan
`{:ok, resultado}` o `{:error, motivo}`. Las consultas se restringen a la zona
de sesión salvo administración; un ID fuera del alcance devuelve `:no_encontrado`.
La autoría ciudadana se verifica únicamente con un `RegistroActividad` de
`:reportar_persona` cuyo `entidad_id` y `username` coincidan con persona y actor.
El coordinador genera ese registro junto con el alta y lo persiste en la misma
operación. Sin evidencia de autoría no se concede ese permiso. `:reunificada`
permanece final en esta etapa; no se implementa corrección administrativa.

Operaciones adicionales de mensajes aprobadas para la etapa 4:

```elixir
Emergencias.API.ejecutar(session_id, {:marcar_mensaje_entregado, mensaje_id})
Emergencias.API.consultar(session_id, {:mensajes_familiares, filtros})
```

Los filtros aceptan `persona_id`, `estado` y `zona_codigo`. La consulta devuelve
`{:ok, lista_de_mensajes}`, ordenada por fecha ascendente e ID; la entrega devuelve
`{:ok, mensaje_actualizado}`. Los errores usan `{:error, motivo}`. Solo se permite
`pendiente → entregado`; repetir la entrega devuelve `:ya_resuelto`.
Crear mensajes exige acceso a la persona y permiso de reporte en su zona.
Los ciudadanos consultan únicamente mensajes creados por ellos, con evidencia de
`RegistroActividad` que incluya `:enviar_mensaje_familiar`, ID del mensaje y usuario
autenticado. Sin evidencia no se concede autoría. No pueden confirmar entregas.
Voluntarios y coordinadores consultan y entregan en su zona; administración tiene
alcance global. Los filtros nunca amplían el alcance de la sesión.
`remitente` y `destinatario` son informativos y no acreditan identidad ni permisos.
El coordinador genera ID, fecha y auditoría, y solo confirma después de persistir.

Operaciones adicionales de mascotas aprobadas para la etapa 5:

```elixir
Emergencias.API.ejecutar(session_id, {:proponer_coincidencia_mascota, reporte_perdida_id, reporte_encontrada_id})
Emergencias.API.consultar(session_id, {:reportes_mascotas, filtros})
Emergencias.API.consultar(session_id, {:reporte_mascota, reporte_id})
Emergencias.API.consultar(session_id, {:posibles_coincidencias_mascota, reporte_id})
Emergencias.API.consultar(session_id, {:coincidencias_mascotas, filtros})
```

Los tipos son `:perdida` y `:encontrada`; el registro siempre inicia en `:activa`.
ID, tipo, especie, características, zona existente y contacto son obligatorios;
nombre, color y tamaño son opcionales. Los filtros de reportes son `tipo_reporte`,
`especie`, `zona_codigo` y `estado`, con orden por ID. Para consultar activos se usa
`estado: :activa`. Los filtros de coincidencias son `reporte_id`, `estado` y
`zona_codigo`, con orden por fecha e ID. Las coincidencias usan `:propuesta` y
`:confirmada` y se almacenan en `coincidencias_mascotas_por_id`, inicialmente `%{}`.
Los snapshots anteriores conservan sus datos y reciben esa colección vacía.

Las respuestas mantienen `{:ok, resultado}` / `{:error, motivo}`. Registrar devuelve
un reporte; proponer y confirmar devuelven una coincidencia. Consultar un ID devuelve
un reporte y las demás consultas devuelven listas. Un ID fuera del alcance devuelve
`:no_encontrado`. Los tipos o especies incompatibles devuelven `:tipo_invalido`;
proponer la misma pareja devuelve `:id_duplicado`; operar con un reporte resuelto
devuelve `:ya_resuelto`. Ambos reportes deben estar dentro del alcance de sesión.
Los campos de contacto no conceden permisos. Ciudadanos consultan y registran en
su zona; voluntarios y coordinadores pueden proponer en su zona. Coordinadores
confirman en su zona y administración propone y confirma globalmente.

Consultar posibles coincidencias no cambia estados. Proponer registra una pareja y
marca ambos reportes como `:posible_coincidencia`; confirmar crea o actualiza la
pareja a `:confirmada`, con `confirmada_por` y fecha de confirmación, y resuelve ambos
reportes en una sola mutación persistida. No se exige propuesta previa para conservar
el comando de confirmación existente. Las propuestas alternativas se conservan para
consulta, pero no pueden confirmarse si algún reporte ya fue resuelto. El dominio
ofrece las transiciones acordadas; no se agrega un comando de cambio arbitrario de
estado. Los estados expuestos se actualizan mediante propuesta y confirmación.

Ponderación de similitud: especie 30, color 20, tamaño 15, características 20,
zona 10 y nombre 5 (máximo 100). Tamaños equivalentes reconocen variantes comunes;
tonos castaños relacionados reciben el 65 % del peso de color. Se exigen tipos pérdida/hallazgo y especie compatible;
se excluyen resueltos. Se normalizan minúsculas, tildes y espacios. Para características
se usa `20 * |palabras comunes| / |palabras distintas de ambos textos|`, con conjuntos
de palabras alfanuméricas, sin `de, del, la, el, los, las, y, con, un, una, en`.
Se redondea a dos decimales. Especie, zona y nombre usan igualdad normalizada no vacía.
Vacíos aportan cero, sin redistribuir pesos. Se devuelve puntaje y desglose de los seis
criterios, ordenando por puntaje descendente e ID del candidato en empates. Ningún
puntaje confirma automáticamente una pareja.

Cambios que deben comunicarse a Sergio y Cristian antes de integrar en la rama principal:

- Etapa 3: comando y consultas de personas, historial consistente y evidencia de autoría.
- Etapa 4: operaciones de mensajes y aclaración de entrega exclusiva de roles autorizados.
- Etapa 5: operaciones, tipos, filtros, puntaje, estados de coincidencia y nueva colección.
- Persistencia: precargar módulos de dominio conocidos antes de decodificar los átomos
  del snapshot, para recuperar datos también en un proceso nuevo. No cambia el JSON
  ni permite crear átomos a partir de texto arbitrario.
- Corrección mínima de `Usuarios`: agregar `:proponer_coincidencia` al voluntario y
  `:confirmar_coincidencia` al coordinador para cumplir la matriz ya aprobada. No cambia
  permisos de personas, mensajes u otros dominios.

Consultas de necesidades y recursos:

```elixir
Emergencias.API.consultar(session_id, {:necesidades, filtros})
Emergencias.API.consultar(session_id, {:recursos, filtros})
Emergencias.API.consultar(session_id, {:movimientos, filtros})
Emergencias.API.consultar(session_id, {:recursos_criticos, filtros})
Emergencias.API.consultar(session_id, :necesidades_pendientes)
Emergencias.API.consultar(session_id, :recursos_criticos)
Emergencias.API.consultar(session_id, :resumen)
```

Los filtros de necesidades aceptan `zona_codigo`, `tipo`, `prioridad` y `estado`; los de recursos aceptan `zona_codigo`, `categoria`, `ubicacion` y `codigo`. Los filtros de recursos críticos identifican existencias con cero unidades disponibles. Los movimientos se presentan del más reciente al más antiguo. Las consultas de personas no administradoras se limitan a su zona de sesión.

El `GenServer` atiende una mutación completa en una sola llamada. Por ejemplo, asignar un recurso valida necesidad, recurso, cantidad, prioridad/estado y stock; si es válida crea la asignación, descuenta inventario, actualiza estado e historial como un solo cambio. Si la persistencia falla, responde error y conserva el estado anterior.

## 4. Errores y validaciones

Las operaciones de dominio devuelven `{:ok, resultado}` o `{:error, motivo}`. El motivo será un átomo o una tupla con datos útiles, nunca un texto usado para decidir lógica.

Motivos compartidos propuestos: `:credenciales_invalidas`, `:no_autorizado`, `:no_encontrado`, `:id_duplicado`, `:cantidad_invalida`, `:stock_insuficiente`, `:capacidad_insuficiente`, `:zona_incompatible`, `:prioridad_invalida`, `:tipo_invalido`, `:estado_invalido`, `:origen_invalido`, `:destino_invalido`, `:transicion_invalida`, `:ya_resuelto`, `:dominio_no_disponible`, `:comando_no_reconocido`, `:consulta_no_reconocida`, `:coordinador_no_disponible`, `:error_persistencia`.

Reglas invariantes: IDs únicos; cantidades y capacidades no negativas; ninguna asignación excede stock; ninguna estancia excede la capacidad; una necesidad atendida/resuelta no consume inventario otra vez; una coincidencia confirmada cierra los dos reportes una sola vez.

## 5. Roles y permisos - confirmados

| Operación | Ciudadano | Voluntario | Coordinador | Administrador |
|---|---:|---:|---:|---:|
| Reportar necesidad, persona o mascota | Sí, en su zona | Sí, en su zona | Sí, en su zona | Sí, global |
| Consultar reportes y estado de su zona | Sí, datos permitidos | Sí | Sí | Sí |
| Cambiar estado de personas | Propios o reportados por sí mismo | En su zona | En su zona | Global |
| Marcar mensajes como entregados | No autorizado | En su zona | En su zona | Global |
| Asignar necesidades, inventario y transferencias | No | No | Sí, en su zona | Sí, global |
| Registrar entradas/salidas de albergue | No | Sí, en su zona | Sí, en su zona | Sí |
| Confirmar coincidencia de mascotas | No | Proponer | Sí, en su zona | Sí |
| Crear zonas, usuarios y asignar roles privilegiados | No | No | No | Sí |

**Regla de alta confirmada:** si el usuario no existe, `conectar/1` lo crea como `:ciudadano`; el registro público no recibe un rol privilegiado. Voluntario/coordinador/administrador se asignan por administración autorizada. Almacenar `password_hash`, nunca la contraseña en texto plano. La matriz anterior queda aprobada como contrato inicial.

La implementación solicita contraseñas de al menos ocho caracteres y deriva `password_hash` con PBKDF2-HMAC-SHA256 y salt aleatorio. La cuenta administradora inicial se provisiona localmente y solo cuando el conjunto de usuarios está vacío.

La aclaración de la matriz de mensajes de la etapa 4 deberá comunicarse al equipo
antes de integrar los cambios en la rama principal. No modifica los permisos de
personas ni requiere cambios en `Emergencias.Usuarios`.

## 6. Estados y transiciones - confirmados

| Dominio | Estados | Transiciones confirmadas |
|---|---|---|
| Necesidad | `:pendiente`, `:asignada`, `:en_atencion`, `:atendida`, `:cancelada` | `pendiente → asignada/cancelada`; `asignada → en_atencion/cancelada`; `en_atencion → atendida`; `atendida` y `cancelada` son finales. Cancelar una asignada libera el recurso en la misma mutación. |
| Asignación de recurso | `:asignada`, `:en_atencion`, `:atendida`, `:cancelada` | Sigue el estado de su necesidad. Cancelar libera una asignación activa y registra la devolución en el historial de movimientos. |
| Persona | `:sin_informacion`, `:reportada`, `:localizada`, `:trasladada`, `:en_albergue`, `:reunificada` | cambio explícito y registrado en historial; `:reunificada` final salvo corrección administrativa auditada. |
| Reporte de mascota | `:activa`, `:posible_coincidencia`, `:resuelta` | activa → posible coincidencia/resuelta; posible coincidencia → activa/resuelta; resuelta final. Confirmar pareja marca ambos reportes resueltos en una mutación. |
| Mensaje | `:pendiente`, `:entregado` | pendiente → entregado; entregado final. |
| Albergue | No requiere estado | entradas y salidas crean/cierra estancias; ocupación = cantidad de estancias activas. |

**Prioridad acordada:** `:critica > :alta > :media > :baja`; el listado de pendientes se ordena por prioridad y luego por fecha de creación.

## 7. Persistencia textual - acordada

- Un snapshot JSON legible: `data/estado.json`, codificado y decodificado con Jason.
- `Emergencias.Persistencia` es el único módulo con efectos de archivos; crea `data/` si falta, carga el snapshot al iniciar y guarda el nuevo estado validado. Si el archivo no existe, inicia con estado vacío. Si existe pero no se puede leer o decodificar, el inicio falla explícitamente: nunca reemplaza datos corruptos por un estado vacío.
- La mutación se confirma al usuario solo después de guardar correctamente. Una falla de lectura/escritura no debe borrar registros ni producir éxito aparente.
- Solo el nodo coordinador escribe el archivo; el nodo web envía solicitudes remotas.
- Jason se declara como dependencia de Mix. Antes de codificar/decodificar, el estado se convierte de structs a mapas JSON simples y se reconstruye al cargar.
- Las sesiones nunca se serializan. Los cambios de inventario registran movimientos para el ingreso inicial, la asignación, la devolución por cancelación y las transferencias.
- Una transferencia parcial separa el lote trasladado en un recurso con código generado por el coordinador; el registro original conserva la cantidad que permanece en el origen.

## 8. Distribución de decisiones de Ola 0

| Decisión | Responsable para preparar propuesta | Participan en confirmación |
|---|---|---|
| Structs, firmas y errores | Cristian Camilo | Los tres |
| Roles, alta y permisos | Sergio Armero | Los tres |
| Estados, coincidencias e historial | Maria Fernanda | Los tres |
| Archivo, formato y carga inicial | Cristian Camilo | Los tres |
| Nombres de nodos y flujo remoto | Cristian Camilo | Los tres |
| Pipe, carpetas y estándar de código | Los tres | Los tres |

**Cierre de Ola 0:** matriz, estados, persistencia y arquitectura confirmados. Los detalles de firmas y nombres quedan especificados en las secciones 3 y 9. Ola 1 puede comenzar.




## 9. Nodos y secuencia de inicio - acordado

- Nodo web: `emergencias_web@localhost`; ejecuta Phoenix LiveView y no mantiene copia autoritativa de los datos.
- Nodo coordinador: `emergencias_core@localhost`; supervisa `Emergencias.EstadoServidor` y es el único nodo que lee/escribe `data/estado.json`.
- El nombre remoto del servidor es `Emergencias.EstadoServidor`. La fachada web establece conexión al nodo core y envía llamadas por `GenServer.call({Emergencias.EstadoServidor, nodo_core}, solicitud)`; las vistas nunca llaman al GenServer directamente.
- Si el nodo core está desconectado o no responde, `Emergencias.API` devuelve `{:error, :coordinador_no_disponible}` y no simula éxito.
- En el primer inicio sin archivo se crea estado vacío y se provisiona el administrador inicial mediante configuración local de primer inicio; no se suben credenciales al repositorio.
