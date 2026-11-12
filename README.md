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
$env:EMERGENCIAS_ADMIN_USERNAME = "admin.demo"
$env:EMERGENCIAS_ADMIN_PASSWORD = "una-clave-local-segura"
$env:EMERGENCIAS_ADMIN_NOMBRE = "Administrador de desarrollo"
$env:EMERGENCIAS_ADMIN_ZONA = "Z-01"
mix phx.server
```

El coordinador crea esa cuenta solo cuando la lista de usuarios está vacía. Crea primero la zona `Z-01` desde la vista de zonas para habilitar el registro público. Sin estas variables, no se provisiona un administrador. No guardes las credenciales locales en el repositorio.

## Estado del desarrollo

La Ola 1 incorpora el esqueleto Mix/Phoenix, el árbol OTP inicial, el estado compartido en memoria, la fachada de comunicación y la navegación web. El trabajo priorizado de Sergio incluye reglas de usuarios, sesiones, zonas, sectores, puntos de atención y albergues, además de cuatro funciones recursivas territoriales. Hay pantallas prototipo con formularios para esos módulos.

La interfaz exige una sesión emitida por `Emergencias.API`. Las cuentas y los dominios se guardan en el snapshot JSON del coordinador; las sesiones permanecen en memoria y se invalidan al reiniciar. La aplicación permite ejecutar el coordinador y Phoenix en un mismo nodo o separarlos con la configuración de nodos documentada.

## Documentación

- [Plan y distribución del trabajo](docs/PLAN_TRABAJO.md)
- [Especificaciones comunes de desarrollo](docs/ESPECIFICACIONES_DESARROLLO.md)
- [Contratos de integración](docs/CONTRATOS_INTEGRACION.md)
- [Avance de Ola 2 de Sergio](docs/OLA2_SERGIO.md)
- [Estándares de código del proyecto](docs/ESTANDARES_CODIGO.md)
