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

### Datos de demostración

En una instalación de desarrollo, ejecuta una vez `mix demo.seed`. El comando crea la zona Centro, un sector y un punto de atención, y prepara cuentas para los cuatro roles. Después inicia la interfaz con `mix phx.server`.

| Rol | Usuario | Contraseña |
|---|---|---|
| Administrador | `demo.admin` | `AdminDemo2026!` |
| Coordinadora | `laura.coord` | `LauraDemo2026!` |
| Voluntario | `voluntario.demo` | `Voluntario2026!` |
| Ciudadano | `ciudadano.demo` | `Ciudadano2026!` |

Estas credenciales son públicas y **solo sirven para desarrollo local**. No las reutilices fuera de la demostración ni las despliegues en producción. El inicializador es idempotente para registros ya creados; en una base local con cuentas existentes, el administrador debe coincidir con `demo.admin` para autenticarlo.

## Estado del desarrollo

La aplicación reúne módulos de usuarios, territorio, albergues, personas, mensajes, mascotas, necesidades y recursos. Las operaciones se procesan mediante el coordinador y los datos de dominio se conservan en un snapshot JSON local.

La interfaz exige una sesión emitida por `Emergencias.API`. Las cuentas y los dominios se guardan en el snapshot JSON del coordinador; las sesiones permanecen en memoria y se invalidan al reiniciar. La aplicación permite ejecutar el coordinador y Phoenix en un mismo nodo o separarlos con la configuración de nodos documentada.

## Documentación

- [Especificaciones comunes de desarrollo](docs/ESPECIFICACIONES_DESARROLLO.md)
- [Contratos de integración](docs/CONTRATOS_INTEGRACION.md)
- [Estándares de código del proyecto](docs/ESTANDARES_CODIGO.md)
