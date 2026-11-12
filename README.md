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

En desarrollo, abrir [http://localhost:4000](http://localhost:4000). El login es obligatorio antes de entrar al panel o a cualquier módulo. El registro público crea usuarios ciudadanos; el rol determina las operaciones habilitadas.

Para revisar las funciones administrativas en la demostración, define una contraseña de al menos ocho caracteres antes de iniciar Phoenix:

```powershell
$env:EMERGENCIAS_DEMO_ADMIN_PASSWORD = "una-clave-local-segura"
mix phx.server
```

La cuenta inicial es `admin.demo`, en la zona `Z-01`. Sin esa variable, las cuentas de registro son ciudadanas y no pueden otorgarse permisos privilegiados por su cuenta. La variable es solo para el entorno local: no la guardes en el repositorio.

## Estado del desarrollo

La Ola 1 incorpora el esqueleto Mix/Phoenix, el árbol OTP inicial, el estado compartido en memoria, la fachada de comunicación y la navegación web. El trabajo priorizado de Sergio incluye reglas de usuarios, sesiones, zonas, sectores, puntos de atención y albergues, además de cuatro funciones recursivas territoriales. Hay pantallas prototipo con formularios para esos módulos.

La interfaz exige una sesión y aplica permisos de demostración según el rol y la zona. Las cuentas y sesiones residen en memoria y se borran al reiniciar la aplicación; las pantallas operativas todavía usan datos de demostración. La autenticación aún debe integrarse con `Emergencias.API` y el coordinador antes de considerarse persistente o lista para producción. El snapshot JSON y la distribución entre nodos siguen pendientes.

## Documentación

- [Plan y distribución del trabajo](docs/PLAN_TRABAJO.md)
- [Especificaciones comunes de desarrollo](docs/ESPECIFICACIONES_DESARROLLO.md)
- [Contratos de integración](docs/CONTRATOS_INTEGRACION.md)
- [Avance de Ola 2 de Sergio](docs/OLA2_SERGIO.md)
- [Estándares de código del proyecto](docs/ESTANDARES_CODIGO.md)
