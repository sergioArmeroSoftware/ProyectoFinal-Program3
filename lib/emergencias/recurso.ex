defmodule Emergencias.Recurso do
  @moduledoc "Existencia de un recurso en una ubicación de apoyo."

  defstruct codigo: nil,
            nombre: nil,
            categoria: nil,
            cantidad_disponible: 0,
            unidad: nil,
            ubicacion: nil,
            zona_codigo: nil
end

defmodule Emergencias.AsignacionRecurso do
  @moduledoc "Cantidad de inventario reservada para atender una necesidad."

  defstruct id: nil,
            necesidad_id: nil,
            recurso_codigo: nil,
            cantidad: 0,
            estado: :asignada,
            asignado_por: nil,
            fecha: nil
end

defmodule Emergencias.MovimientoRecurso do
  @moduledoc "Registro histórico de una entrada, asignación, devolución o transferencia."

  defstruct id: nil,
            recurso_codigo: nil,
            origen: nil,
            destino: nil,
            cantidad: 0,
            fecha: nil,
            usuario_id: nil
end
