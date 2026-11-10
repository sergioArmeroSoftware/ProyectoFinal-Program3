defmodule Emergencias.Usuario do
  @moduledoc "Cuenta de usuario; nunca contiene una contraseña en texto plano."
  defstruct username: nil,
            password_hash: nil,
            nombre_completo: nil,
            rol: :ciudadano,
            zona_principal: nil,
            activo: true
end

defmodule Emergencias.RegistroActividad do
  @moduledoc "Registro auditable de una acción ejecutada por un usuario."
  defstruct id: nil, username: nil, accion: nil, entidad_id: nil, fecha: nil
end
