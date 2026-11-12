defmodule Emergencias.PersonaAfectada do
  @moduledoc "Persona afectada identificada dentro de una zona."
  defstruct id: nil,
            nombre: nil,
            documento_referencia: nil,
            edad: nil,
            zona_codigo: nil,
            estado: :reportada
end
