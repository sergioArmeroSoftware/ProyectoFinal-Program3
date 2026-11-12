defmodule Emergencias.CoincidenciaMascota do
  @moduledoc "Pareja de reportes propuesta o confirmada por una persona autorizada."
  defstruct id: nil,
            reporte_perdida_id: nil,
            reporte_encontrada_id: nil,
            puntaje: nil,
            estado: :propuesta,
            confirmada_por: nil,
            fecha: nil
end
