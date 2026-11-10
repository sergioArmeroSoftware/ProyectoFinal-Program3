defmodule Emergencias.Zona do
  @moduledoc "Zona de afectación con sectores y puntos de atención anidados."
  defstruct codigo: nil,
            nombre: nil,
            nivel_afectacion: :medio,
            personas_estimadas: 0,
            sectores: []
end

defmodule Emergencias.Sector do
  @moduledoc "Sector dentro de una zona."
  defstruct codigo: nil, nombre: nil, puntos: []
end

defmodule Emergencias.PuntoAtencion do
  @moduledoc "Punto que presta atención a personas afectadas."
  defstruct codigo: nil, nombre: nil, personas_estimadas: 0, estado: :activo
end
