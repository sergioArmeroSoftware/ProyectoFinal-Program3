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
| `Recurso` | `codigo`, `nombre`, `categoria`, `cantidad_disponible`, `unidad`, `ubicacion`, `zona_codigo` | `codigo` único |
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
{:registrar_recurso, attrs}
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

Las consultas incluyen filtros por dominio, `:resumen` y `:recursos_criticos`. Los nombres definitivos se alinean con las vistas cuando se implemente cada módulo.

El `GenServer` atiende una mutación completa en una sola llamada. Por ejemplo, asignar un recurso valida necesidad, recurso, cantidad, prioridad/estado y stock; si es válida crea la asignación, descuenta inventario, actualiza estado e historial como un solo cambio. Si la persistencia falla, responde error y conserva el estado anterior.

## 4. Errores y validaciones

Las operaciones de dominio devuelven `{:ok, resultado}` o `{:error, motivo}`. El motivo será un átomo o una tupla con datos útiles, nunca un texto usado para decidir lógica.

Motivos compartidos propuestos: `:credenciales_invalidas`, `:no_autorizado`, `:no_encontrado`, `:id_duplicado`, `:cantidad_invalida`, `:stock_insuficiente`, `:capacidad_insuficiente`, `:transicion_invalida`, `:ya_resuelto`, `:coordinador_no_disponible`, `:error_persistencia`.

Reglas invariantes: IDs únicos; cantidades y capacidades no negativas; ninguna asignación excede stock; ninguna estancia excede la capacidad; una necesidad atendida/resuelta no consume inventario otra vez; una coincidencia confirmada cierra los dos reportes una sola vez.

## 5. Roles y permisos - confirmados

| Operación | Ciudadano | Voluntario | Coordinador | Administrador |
|---|---:|---:|---:|---:|
| Reportar necesidad, persona o mascota | Sí, en su zona | Sí, en su zona | Sí, en su zona | Sí, global |
| Consultar reportes y estado de su zona | Sí, datos permitidos | Sí | Sí | Sí |
| Cambiar estado de personas / atender mensajes | Propios o reportados por sí mismo | Sí, en su zona | Sí, en su zona | Sí |
| Asignar necesidades, inventario y transferencias | No | No | Sí, en su zona | Sí, global |
| Registrar entradas/salidas de albergue | No | Sí, en su zona | Sí, en su zona | Sí |
| Confirmar coincidencia de mascotas | No | Proponer | Sí, en su zona | Sí |
| Crear zonas, usuarios y asignar roles privilegiados | No | No | No | Sí |

**Regla de alta confirmada:** si el usuario no existe, `conectar/1` lo crea como `:ciudadano`; el registro público no recibe un rol privilegiado. Voluntario/coordinador/administrador se asignan por administración autorizada. Almacenar `password_hash`, nunca la contraseña en texto plano. La matriz anterior queda aprobada como contrato inicial.

La implementación solicita contraseñas de al menos ocho caracteres y deriva `password_hash` con PBKDF2-HMAC-SHA256 y salt aleatorio. La cuenta administradora inicial se provisiona localmente y solo cuando el conjunto de usuarios está vacío.

## 6. Estados y transiciones - confirmados

| Dominio | Estados | Transiciones confirmadas |
|---|---|---|
| Necesidad | `:pendiente`, `:asignada`, `:en_atencion`, `:atendida`, `:cancelada` | `pendiente → asignada/cancelada`; `asignada → en_atencion/cancelada`; `en_atencion → atendida`; `atendida` y `cancelada` son finales. Cancelar una asignada libera el recurso en la misma mutación. |
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
