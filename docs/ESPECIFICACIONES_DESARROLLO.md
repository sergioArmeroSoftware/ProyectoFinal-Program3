# Especificaciones comunes de desarrollo

**Alcance:** código, integración, revisión y documentación del proyecto final de Programación III.

Estas especificaciones reúnen las guías del curso, `ESTANDARES_CODIGO.md`, los acuerdos de Ola 0 y las decisiones de implementación del equipo. Sirven como marco compartido para Sergio Armero Salazar, Maria Fernanda Mejía Ocampo y Cristian Camilo Castañeda Benavides.

## 1. Orden de precedencia

Si dos indicaciones parecen contradecirse, se resuelven en este orden:

1. Requisitos de entrega y checklist del PDF del proyecto.
2. Acuerdos confirmados por el grupo en [CONTRATOS_INTEGRACION.md](CONTRATOS_INTEGRACION.md).
3. Estas especificaciones comunes.
4. Guías de Programación III y `ESTANDARES_CODIGO.md`.
5. Preferencias de implementación local que no cambien las capas, los contratos o los requisitos.

Un cambio de modelo, estado, permiso, comando público o formato persistente se propone en `docs/CONTRATOS_INTEGRACION.md` y se acuerda antes de que los módulos dependientes lo adopten. No se resuelve cambiando silenciosamente el contrato de otro integrante.

## 2. Principios para escribir Elixir

- Favorecer funciones puras, datos inmutables y transformaciones explícitas.
- Una función recibe sus datos por argumentos y devuelve un resultado; no consulta estado oculto ni realiza I/O desde la lógica de dominio.
- Usar `PascalCase` para módulos, `snake_case` para funciones y variables, y nombres que expresen acciones o conceptos del dominio.
- Mantener funciones pequeñas y módulos con una sola responsabilidad clara.
- Usar pattern matching y guards para expresar casos y validaciones simples.
- Representar errores funcionales como `{:error, motivo}` con átomos estables; no usar mensajes de interfaz como control lógico.
- Las operaciones públicas documentan propósito, argumentos, resultados y errores relevantes con `@doc`. Cada módulo explica su responsabilidad con `@moduledoc`.
- Mantener formato estándar de Elixir e indentación de dos espacios. Ejecutar `mix format` antes de integrar.

### Uso de `|>`

Usar el pipe cuando un valor pasa en secuencia por transformaciones y se vuelve el primer argumento de cada función:

```elixir
registros
|> Enum.filter(&(&1.zona_codigo == zona_codigo))
|> Enum.sort_by(& &1.fecha)
|> Enum.map(&presentar/1)
```

Preferir `with` cuando haya validaciones encadenadas que puedan fallar y `case` cuando el flujo tenga ramas visibles. No unir en un único pipe una llamada remota, una escritura, una regla de dominio y la conversión de salida; hacer explícitos esos límites.

## 3. Capas y límites de responsabilidad

| Capa | Responsabilidad | No debe hacer |
|---|---|---|
| `EmergenciasWeb.*` | Renderizar LiveView, recoger entradas, llamar a `Emergencias.API` y presentar errores. | Acceder al GenServer, modificar `%Emergencias.Estado{}` o leer/escribir archivos directamente. |
| `Emergencias.API` | Mantener la fachada estable para conectar, desconectar, ejecutar comandos y consultar. | Incluir reglas de negocio o persistir datos. |
| Dominios (`Emergencias.Usuarios`, `Zonas`, `Personas`, `Necesidades`, etc.) | Validar datos y producir estados nuevos usando funciones puras. | Mantener estado global, hablar por red, escribir archivos o renderizar HTML. |
| `Emergencias.EstadoServidor` | Ser el dueño del estado mutable del sistema, serializar mutaciones y coordinar dominio y persistencia. | Exponer su estado para mutaciones directas desde la interfaz. |
| `Emergencias.Persistencia` | Codificar/decodificar el snapshot JSON y realizar operaciones de archivo. | Aplicar reglas del dominio o ser llamado por cada módulo de dominio. |

El único escritor de `data/estado.json` es el nodo coordinador. Una mutación se valida completa, se intenta guardar el estado nuevo y solo entonces se confirma al solicitante. Ante error de persistencia se conserva el estado anterior. Las sesiones se mantienen en memoria y no se serializan.

### Excepción temporal para el front en desarrollo

Las pantallas de Sergio consultan y mutan el estado del coordinador mediante `Emergencias.API`; las reglas del dominio y la persistencia quedan fuera de LiveView. Los datos iniciales dependen del estado JSON y de la zona que el administrador registre durante el primer inicio.

## 4. Estructuras, colecciones e identificadores

- Las entidades compartidas se representan con structs y los nombres/campos se mantienen alineados con la tabla de [CONTRATOS_INTEGRACION.md](CONTRATOS_INTEGRACION.md).
- Indexar entidades por clave única en mapas: usuarios por `username`, zonas/albergues por `codigo`, personas/necesidades/mensajes por `id`.
- Usar listas para historiales cuya secuencia temporal tenga significado.
- Mantener la jerarquía `Zona -> sectores -> puntos` anidada. No aplanarla sin actualizar primero el contrato y el diagrama.
- Usar átomos para estados y roles internos; validar valores entrantes antes de construir structs. No convertir texto arbitrario del usuario con `String.to_atom/1`.
- Mantener los códigos canónicos: zonas `Z-01`, sectores `SEC-01`, puntos `PA-01` y albergues `A-01` (prefijo en mayúscula, guion y exactamente dos dígitos). Validar al escribir en la interfaz y volver a validar en dominio; los identificadores de zona deben referenciar una zona existente.
- IDs nuevos y marcas de tiempo se generan en la frontera coordinadora, no dentro de una función que deba ser pura.
- No guardar contraseñas en texto plano. No exponer `password_hash` en los datos entregados a LiveView.

## 5. Convención para módulos de dominio

Cada responsable implementa sus reglas en módulos separados bajo `lib/emergencias/`. Una operación que prepara una mutación recibe los datos requeridos y devuelve `{:ok, nuevo_valor}` o `{:error, motivo}`. El coordinador la invoca dentro de una llamada indivisible.

Convenciones para compartir módulos entre responsables:

1. Mantener la firma acordada o proponer el cambio en el contrato antes de implementarlo.
2. Aceptar los structs y mapas por su forma documentada; evitar depender de cómo los construye otro módulo.
3. Mantener errores de dominio como átomos estables (por ejemplo `:no_encontrado`, `:id_duplicado`, `:no_autorizado`, `:capacidad_insuficiente`). La interfaz traduce esos errores a mensajes para las personas.
4. No capturar ni descartar errores con valores por defecto que parezcan éxito.
5. Las reglas que relacionan dos dominios —por ejemplo albergue/persona o necesidad/recurso— se despachan desde el coordinador como una mutación completa, usando funciones puras de ambos dominios.

### Reparto y puntos de integración

- **Sergio:** `Usuarios`, `Sesiones`, `Zonas`, `Albergues` y sus LiveViews.
- **Maria Fernanda:** `Personas`, historial, mensajes y mascotas; define las funciones puras para validar referencias y cambios de estado de personas.
- **Cristian Camilo:** `Necesidades`, `Recursos`, asignaciones/movimientos, GenServer coordinador, persistencia y comunicación entre nodos.
- **Todos:** no editar la responsabilidad ajena para desbloquear integración sin acordarlo; reportar la firma o regla que falta y proponer el cambio de contrato.

## 6. Recursión requerida

El proyecto debe conservar al menos cuatro funciones recursivas propias, útiles para consultar la jerarquía territorial. La implementación de Sergio cubre:

- `Emergencias.Zonas.contar_sectores/1`
- `Emergencias.Zonas.contar_puntos/1`
- `Emergencias.Zonas.contar_puntos_por_estado/2`
- `Emergencias.Zonas.buscar_punto/2`

Cada recorrido debe mantener caso base y caso recursivo identificables, trabajar con los datos recibidos y explicar qué consulta del sistema resuelve. No cambiar estos cuatro recorridos por `Enum` sin conservar otras cuatro recursiones útiles en el proyecto.

## 7. Interfaz, seguridad y errores

- Todas las pantallas operativas requieren una sesión válida. El registro público inicia con rol ciudadano; la cuenta administradora de desarrollo solo existe si se configura `EMERGENCIAS_DEMO_ADMIN_PASSWORD`.
- La interfaz de demostración restringe administración al rol administrador y operaciones de albergue al permiso `gestionar_albergue` dentro de la zona asignada. Estas comprobaciones en LiveView son una protección del prototipo; al integrar el coordinador, cada comando debe validar nuevamente identidad, rol y zona en el servidor.
- Las cuentas y sesiones de la interfaz de demostración están en memoria y se borran al reiniciar la app. No las describir como autenticación persistente.
- Las vistas llaman únicamente a `Emergencias.API`; no asumen que una mutación fue exitosa hasta recibir respuesta.
- Mostrar estados de carga y mensajes comprensibles para errores funcionales; no presentar stack traces a usuarios.
- La autorización se comprueba en el coordinador en cada comando, incluso si la vista oculta el botón. Validar tanto el rol como el alcance de zona.
- La sesión identifica al actor; no se acepta `username`, rol o zona enviados desde el formulario como prueba de identidad.
- Alta pública crea ciudadanos; roles privilegiados solo se otorgan por acción autorizada.
- No incluir contraseñas, tokens, secretos o datos locales de administrador en commits, fixtures públicos o capturas.

## 8. Dependencias y configuración

- Declarar dependencias Elixir en `mix.exs` y mantener `mix.lock` versionado.
- No añadir Ecto/MySQL: la persistencia acordada es snapshot JSON con Jason.
- Mantener secretos, credenciales de primer inicio, nombres de nodo y puertos fuera de código fuente cuando deban variar por ambiente; documentar sus variables de entorno sin publicar valores privados.
- No subir `deps/`, `_build/`, `data/estado.json`, artefactos generados ni archivos locales de entorno.
- No añadir paquetes JavaScript sin justificar por qué el esqueleto Phoenix/LiveView existente no basta.

## 9. Flujo de trabajo de equipo

1. Leer este documento, los contratos y el issue/tarea antes de tocar una capa compartida.
2. Trabajar en una rama con alcance pequeño, por ejemplo `sergio/usuarios-zonas`, `maria/personas-mascotas` o `cristian/coordinador-json`.
3. Si una firma ajena está pendiente, seguir con funciones puras independientes y registrar la dependencia con nombre de módulo, función, argumentos, resultado esperado y efecto en el flujo.
4. No sobrescribir cambios de otro integrante. Revisar `git status` y el diff antes de editar, integrar o preparar commits.
5. Hacer commits pequeños con verbo y alcance, por ejemplo `feat(usuarios): agrega autenticación y permisos`.
6. Para integrar, revisar que el diff solo incluya el trabajo previsto, que los diagramas sigan representando la arquitectura y que no haya archivos sensibles o generados.

## 10. Criterio de terminado

Una tarea de dominio se considera lista para integrar cuando:

- las reglas y validaciones están en el módulo responsable y tienen resultados explícitos;
- los datos inválidos no producen una mutación parcial;
- las funciones públicas tienen documentación y nombres alineados con el contrato;
- la vista usa la API y presenta errores sin saltárselos;
- se ejecutó `mix format` y el proyecto compila;
- se añadieron/actualizaron pruebas de los casos de éxito, error y límites cuando corresponda;
- los contratos y diagramas se actualizaron si cambió una estructura, transición, permiso o flujo.

El checklist del PDF incluye pruebas como requisito de entrega. La verificación de cada ola se hará cuando el equipo acuerde ejecutarla; no marcar casos como verificados si no hay evidencia.

## 11. Fuentes del curso

Las siguientes guías del profesor respaldan el enfoque de este documento. Úsenlas como material de consulta y expliquen con palabras propias las decisiones aplicadas al proyecto.

- [Guías de Programación III - página principal](https://caflorezvi.github.io/guias-programacion3/) — mapa de fundamentos, datos, recursión, OTP, concurrencia y Mix.
- [Programación funcional](https://caflorezvi.github.io/guias-programacion3/03.programacion-funcional.html) — pureza, inmutabilidad, efectos aislados y composición con `|>`.
- [Guards y manejo de resultados](https://caflorezvi.github.io/guias-programacion3/06.guards-manejo-resultados.html) — validación con guards, `{:ok, ...}` / `{:error, ...}`, `with` y decisiones entre `case`/`cond`.
- [Colecciones en Elixir](https://caflorezvi.github.io/guias-programacion3/07.colecciones.html) — mapas, listas y transformaciones funcionales.
- [Recursividad](https://caflorezvi.github.io/guias-programacion3/08.recursividad.html) — casos base/recursivos y recorridos.
- [Structs](https://caflorezvi.github.io/guias-programacion3/09.structs.html) — entidades y estructuras de datos nombradas.
- [Manejo de archivos](https://caflorezvi.github.io/guias-programacion3/11.archivos.html) — lectura/escritura en los límites del sistema.
- [Procesos en Elixir](https://caflorezvi.github.io/guias-programacion3/12.procesos.html), [aplicaciones distribuidas I](https://caflorezvi.github.io/guias-programacion3/13.nodos-dist-1.html), [OTP](https://caflorezvi.github.io/guias-programacion3/15.otp.html), [supervisores](https://caflorezvi.github.io/guias-programacion3/16.supervisores.html) y [Mix](https://caflorezvi.github.io/guias-programacion3/17.mix.html) — procesos, nodos, GenServer, supervisión y estructura de proyecto.
- [Estándares de código del equipo](ESTANDARES_CODIGO.md) — nombres, documentación, funciones pequeñas, pipes y organización.
