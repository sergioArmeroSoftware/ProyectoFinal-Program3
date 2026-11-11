defmodule Emergencias.Necesidad do
  @moduledoc "Solicitud de ayuda asociada a una zona y a una persona responsable."

  defstruct id: nil,
            tipo: nil,
            descripcion: nil,
            cantidad: 0,
            prioridad: :media,
            zona_codigo: nil,
            responsable_id: nil,
            estado: :pendiente
end
