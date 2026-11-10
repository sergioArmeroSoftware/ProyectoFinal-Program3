# Ola 2 - Avance de Sergio Armero Salazar

## Implementado en módulos independientes

- `Emergencias.Credenciales`: hash de contraseña con PBKDF2-HMAC-SHA256 y salt aleatorio; verificación con comparación de tiempo constante.
- `Emergencias.Usuarios`: alta siempre como ciudadano, autenticación, desactivación, representación pública sin hash, control de permisos y cambio de rol protegido para administradores.
- `Emergencias.Sesiones`: crear/cerrar sesiones, recuperar identidad y comprobar permisos generales y por zona sin mutar el estado original.
- `Emergencias.Zonas`: validación y alta de zonas, sectores y puntos; cambio de estado de puntos; estadísticas y recorridos recursivos.
- `Emergencias.Albergues`: registro validado, disponibilidad, ocupación, entradas y salidas. La variante `registrar_ingreso/7` además valida que la persona esté en el mapa de personas.
- `Emergencias.API`: fachada con las firmas de conexión, desconexión, ejecución y consulta acordadas en Ola 0.

## Recorridos recursivos requeridos

1. `Emergencias.Zonas.contar_sectores/1`
2. `Emergencias.Zonas.contar_puntos/1`
3. `Emergencias.Zonas.contar_puntos_por_estado/2`
4. `Emergencias.Zonas.buscar_punto/2`

Los cuatro recorren estructuras reales de zonas, sectores y puntos. Sus auxiliares tienen casos base explícitos y no cambian los datos recibidos.

## Contrato que falta integrar con Cristian

`Emergencias.API` envía al GenServer estas solicitudes:

```elixir
{:conectar, attrs}
{:desconectar, session_id}
{:ejecutar, session_id, comando}
{:consultar, session_id, consulta}
```

El coordinador debe atenderlas, ejecutar las funciones de dominio contra un único `%Emergencias.Estado{}`, serializar las operaciones que cambien albergues/personas y conservar el estado anterior si guardar el JSON falla. También debe cargar el estado al iniciar y aplicar la configuración para crear el primer administrador desde variables locales, sin credenciales en el repositorio.

Comandos de Sergio propuestos para que el coordinador despache:

```elixir
{:registrar_zona, attrs}
{:registrar_sector, zona_codigo, attrs}
{:registrar_punto_atencion, zona_codigo, sector_codigo, attrs}
{:cambiar_estado_punto_atencion, zona_codigo, sector_codigo, punto_codigo, estado}
{:asignar_rol, username, rol}
{:registrar_albergue, attrs}
{:registrar_entrada_albergue, albergue_codigo, persona_id}
{:registrar_salida_albergue, albergue_codigo, persona_id}
```

El coordinador genera IDs y fechas para estancias, comprueba permisos y agrega actividad a cada operación que modifica datos.

## Contrato que falta integrar con Maria Fernanda

Antes de confirmar el ingreso/salida de un albergue, se debe validar y actualizar la persona afectada en la misma mutación del coordinador:

- Ingreso: verificar que `persona_id` existe, crear estancia y registrar el cambio de estado acordado a `:en_albergue`.
- Salida: cerrar estancia y registrar el estado de persona que definan las reglas del dominio.
- Ambas operaciones deben añadir el historial de cambios de estado.

Para terminar ese acoplamiento, Maria debe entregar `%Emergencias.PersonaAfectada{}`, la estructura de estado e historial, y una función pura para cambiar el estado con validación. No hace falta que ella implemente la interfaz de Sergio.

## Pendiente para cerrar la parte de Sergio

- Conectar las funciones de dominio a los mensajes reales del coordinador.
- Crear formularios LiveView funcionales de registro/inicio de sesión, administración de usuarios, zonas/sectores/puntos y albergues.
- Proteger rutas y acciones por sesión, rol y zona.
- Persistir sesiones solamente en memoria; guardar usuarios, territorio, albergues y estancias en el JSON del estado.
- Completar la entrada/salida de albergue junto con el historial de personas.
- Añadir pruebas cuando el equipo solicite ejecutar la etapa de verificación.
