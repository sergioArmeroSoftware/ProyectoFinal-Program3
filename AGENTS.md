# Instrucciones para contribuir

Antes de editar código, leer [las especificaciones de desarrollo](docs/ESPECIFICACIONES_DESARROLLO.md) y [los contratos de integración](docs/CONTRATOS_INTEGRACION.md).

- Mantener las capas acordadas: LiveView -> `Emergencias.API` -> coordinador -> dominios/persistencia.
- No cambiar structs, nombres de campos, estados, permisos, comandos o serialización compartida sin actualizar los contratos y avisar al equipo.
- Mantener funciones de dominio puras, inmutables, pequeñas y con resultados `{:ok, ...}` / `{:error, ...}`.
- Usar `|>` para transformaciones lineales; `with` y `case` para validaciones y ramas.
- Nunca persistir desde LiveView ni escribir el snapshot desde un módulo de dominio.
- No agregar credenciales ni archivos locales generados al repositorio.
- Ejecutar `mix format` y `mix compile` antes de integrar; seguir los acuerdos del equipo sobre cuándo correr pruebas.
