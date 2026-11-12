defmodule Emergencias.Estado do
  @moduledoc "Estado compartido en memoria del sistema de emergencias."

  defstruct usuarios_por_username: %{},
            zonas_por_codigo: %{},
            necesidades_por_id: %{},
            recursos_por_codigo: %{},
            personas_por_id: %{},
            mensajes_por_id: %{},
            reportes_mascotas_por_id: %{},
            coincidencias_mascotas_por_id: %{},
            albergues_por_codigo: %{},
            asignaciones_por_id: %{},
            movimientos_por_id: %{},
            estancias_por_id: %{},
            historial_personas: [],
            actividad: [],
            sesiones: %{}
end
