# Sistema de coordinación de emergencias

Proyecto final de Programación III, desarrollado en Elixir con Phoenix LiveView.

## Requisitos locales

- Elixir y Erlang/OTP compatibles con `mix.exs` (Elixir `~> 1.17`).
- Git y conexión a Internet para descargar dependencias.

## Preparar y ejecutar

```powershell
mix deps.get
mix phx.server
```

Abrir [http://localhost:4000](http://localhost:4000). Para ejecutar solo el coordinador o configurar nodos distribuidos se documentará el procedimiento cuando se integre esa ola.

## Estado del desarrollo

La Ola 1 incorpora el esqueleto Mix/Phoenix, el árbol OTP inicial, el estado compartido en memoria, la fachada de comunicación y la navegación web. El trabajo priorizado de Sergio incluye structs y reglas iniciales de usuarios, zonas, sectores, puntos de atención y albergues, además de cuatro funciones recursivas territoriales.

La persistencia JSON, autenticación, operaciones completas desde formularios, distribución entre nodos y los demás dominios están pendientes de integración. El estado actual se reinicia al reiniciar la aplicación.

## Documentación

- [Plan y distribución del trabajo](docs/PLAN_TRABAJO.md)
- [Especificaciones comunes de desarrollo](docs/ESPECIFICACIONES_DESARROLLO.md)
- [Contratos de integración](docs/CONTRATOS_INTEGRACION.md)
- [Avance de Ola 2 de Sergio](docs/OLA2_SERGIO.md)
- [Estándares de código del proyecto](docs/ESTANDARES_CODIGO.md)
