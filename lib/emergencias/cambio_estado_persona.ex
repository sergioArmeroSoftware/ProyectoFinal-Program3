defmodule Emergencias.CambioEstadoPersona do
  @moduledoc "Cambio de estado de una persona con fecha y usuario responsable."
  defstruct id: nil,
            persona_id: nil,
            estado_anterior: nil,
            estado_nuevo: nil,
            fecha: nil,
            usuario_id: nil
end
