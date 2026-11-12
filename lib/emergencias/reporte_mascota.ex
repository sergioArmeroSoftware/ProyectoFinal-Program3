defmodule Emergencias.ReporteMascota do
  @moduledoc "Reporte de pérdida o hallazgo de una mascota en una zona."
  defstruct id: nil,
            tipo_reporte: nil,
            especie: nil,
            nombre: nil,
            caracteristicas: nil,
            color: nil,
            tamano: nil,
            zona_codigo: nil,
            contacto: nil,
            estado: :activa
end
