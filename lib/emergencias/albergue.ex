defmodule Emergencias.Albergue do
  @moduledoc "Albergue con capacidad máxima definida."
  defstruct codigo: nil, nombre: nil, zona_codigo: nil, capacidad_maxima: 0
end

defmodule Emergencias.EstanciaAlbergue do
  @moduledoc "Registro de ingreso y eventual salida de una persona."
  defstruct id: nil,
            albergue_codigo: nil,
            persona_id: nil,
            fecha_ingreso: nil,
            fecha_salida: nil
end
