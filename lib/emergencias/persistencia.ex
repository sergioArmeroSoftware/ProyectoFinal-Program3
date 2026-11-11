defmodule Emergencias.Persistencia do
  @moduledoc "Carga y guarda el snapshot JSON del estado compartido."

  alias Emergencias.Estado

  @structs [
    Emergencias.Estado,
    Emergencias.Usuario,
    Emergencias.RegistroActividad,
    Emergencias.Zona,
    Emergencias.Sector,
    Emergencias.PuntoAtencion,
    Emergencias.Necesidad,
    Emergencias.Recurso,
    Emergencias.AsignacionRecurso,
    Emergencias.MovimientoRecurso,
    Emergencias.Albergue,
    Emergencias.EstanciaAlbergue,
    Emergencias.PersonaAfectada,
    Emergencias.MensajeFamiliar,
    Emergencias.CambioEstadoPersona,
    Emergencias.ReporteMascota,
    Emergencias.CoincidenciaMascota,
    Date,
    Time,
    NaiveDateTime,
    DateTime,
    Calendar.ISO,
    MapSet
  ]

  @doc "Devuelve la ruta configurada o el archivo data/estado.json del proyecto."
  def ruta do
    Application.get_env(:emergencias, :state_path) ||
      Path.expand("../../data/estado.json", __DIR__)
  end

  @doc "Carga el snapshot. Un archivo ausente produce un estado vacío."
  def cargar(path \\ ruta()) do
    case File.read(path) do
      {:ok, contenido} -> decodificar(contenido)
      {:error, :enoent} -> {:ok, %Estado{}}
      {:error, _razon} -> {:error, :error_persistencia}
    end
  end

  @doc "Guarda el estado sin serializar las sesiones y reemplaza el snapshot atómicamente."
  def guardar(estado, path \\ ruta())

  def guardar(%Estado{} = estado, path) do
    estado = %{estado | sesiones: %{}}

    with {:ok, contenido} <- codificar(estado),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, temporal} <- escribir_temporal(path, contenido),
         :ok <- reemplazar_snapshot(temporal, path) do
      :ok
    else
      {:error, _razon} -> {:error, :error_persistencia}
    end
  end

  def guardar(_estado, _path), do: {:error, :error_persistencia}

  defp decodificar(contenido) do
    with {:ok, datos} <- Jason.decode(contenido),
         {:ok, %Estado{sesiones: sesiones} = estado} <- decodificar_valor(datos),
         true <- sesiones == %{} do
      {:ok, estado}
    else
      _resultado -> {:error, :error_persistencia}
    end
  rescue
    _error -> {:error, :error_persistencia}
  end

  defp codificar(estado) do
    estado
    |> codificar_valor()
    |> Jason.encode(pretty: true)
  rescue
    _error -> {:error, :error_persistencia}
  end

  defp codificar_valor(%_{} = struct) do
    modulo = struct.__struct__

    campos =
      struct
      |> Map.from_struct()
      |> Enum.reduce(%{}, fn {clave, valor}, acumulado ->
        Map.put(acumulado, Atom.to_string(clave), codificar_valor(valor))
      end)

    %{"__struct__" => Atom.to_string(modulo), "campos" => campos}
  end

  defp codificar_valor(map) when is_map(map) do
    if Enum.all?(Map.keys(map), &is_binary/1) and
         not Enum.any?(
           Map.keys(map),
           &(&1 in ["__struct__", "campos", "__atom__", "__tuple__", "__map__"])
         ) do
      Map.new(map, fn {clave, valor} -> {clave, codificar_valor(valor)} end)
    else
      pares =
        Enum.map(map, fn {clave, valor} ->
          [codificar_valor(clave), codificar_valor(valor)]
        end)

      %{"__map__" => pares}
    end
  end

  defp codificar_valor(list) when is_list(list), do: Enum.map(list, &codificar_valor/1)

  defp codificar_valor(tuple) when is_tuple(tuple),
    do: %{"__tuple__" => tuple |> Tuple.to_list() |> Enum.map(&codificar_valor/1)}

  defp codificar_valor(value) when is_atom(value) and value in [nil, true, false], do: value
  defp codificar_valor(value) when is_atom(value), do: %{"__atom__" => Atom.to_string(value)}
  defp codificar_valor(value) when is_binary(value) or is_number(value), do: value
  defp codificar_valor(_value), do: raise(ArgumentError, "tipo no serializable")

  defp decodificar_valor(%{"__atom__" => nombre}) do
    case atom_existente(nombre) do
      {:ok, atom} -> {:ok, atom}
      :error -> {:error, :atom_desconocido}
    end
  end

  defp decodificar_valor(%{"__tuple__" => elementos}) when is_list(elementos) do
    with {:ok, elementos} <- decodificar_lista(elementos) do
      {:ok, List.to_tuple(elementos)}
    end
  end

  defp decodificar_valor(%{"__map__" => pares}) when is_list(pares) do
    Enum.reduce_while(pares, {:ok, %{}}, fn
      [clave, valor], {:ok, acumulado} ->
        with {:ok, clave} <- decodificar_valor(clave),
             {:ok, valor} <- decodificar_valor(valor) do
          {:cont, {:ok, Map.put(acumulado, clave, valor)}}
        else
          _resultado -> {:halt, {:error, :snapshot_invalido}}
        end

      _par, _acumulado ->
        {:halt, {:error, :snapshot_invalido}}
    end)
  end

  defp decodificar_valor(%{"__struct__" => nombre, "campos" => campos})
       when is_binary(nombre) and is_map(campos) do
    with {:ok, modulo} <- modulo_permitido(nombre),
         true <- Code.ensure_loaded?(modulo),
         true <- function_exported?(modulo, :__struct__, 0),
         {:ok, campos} <- decodificar_campos(campos),
         {:ok, struct} <- construir_struct(modulo, campos) do
      {:ok, struct}
    else
      _resultado -> {:error, :struct_desconocido}
    end
  end

  defp decodificar_valor(list) when is_list(list), do: decodificar_lista(list)

  defp decodificar_valor(map) when is_map(map) do
    Enum.reduce_while(map, {:ok, %{}}, fn {clave, valor}, {:ok, acumulado} ->
      case decodificar_valor(valor) do
        {:ok, valor} -> {:cont, {:ok, Map.put(acumulado, clave, valor)}}
        {:error, razon} -> {:halt, {:error, razon}}
      end
    end)
  end

  defp decodificar_valor(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or is_nil(value),
       do: {:ok, value}

  defp decodificar_valor(_value), do: {:error, :snapshot_invalido}

  defp decodificar_lista(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acumulado} ->
      case decodificar_valor(value) do
        {:ok, valor} -> {:cont, {:ok, [valor | acumulado]}}
        {:error, razon} -> {:halt, {:error, razon}}
      end
    end)
    |> case do
      {:ok, valores} -> {:ok, Enum.reverse(valores)}
      error -> error
    end
  end

  defp modulo_permitido(nombre) do
    case Enum.find(@structs, &(Atom.to_string(&1) == nombre)) do
      nil -> {:error, :struct_desconocido}
      modulo -> {:ok, modulo}
    end
  end

  defp decodificar_campos(campos) do
    Enum.reduce_while(campos, {:ok, %{}}, fn {nombre, valor}, {:ok, acumulado} ->
      with {:ok, clave} <- atom_existente(nombre),
           {:ok, valor} <- decodificar_valor(valor) do
        {:cont, {:ok, Map.put(acumulado, clave, valor)}}
      else
        _resultado -> {:halt, {:error, :campo_desconocido}}
      end
    end)
  end

  defp construir_struct(modulo, campos) when is_map(campos) do
    plantilla = struct(modulo)
    permitidos = plantilla |> Map.keys() |> MapSet.new()

    campos =
      Enum.reduce_while(campos, {:ok, []}, fn
        {clave, valor}, {:ok, acumulado} when is_atom(clave) ->
          if MapSet.member?(permitidos, clave) do
            {:cont, {:ok, [{clave, valor} | acumulado]}}
          else
            {:halt, {:error, :campo_desconocido}}
          end

        _campo, _acumulado ->
          {:halt, {:error, :campo_desconocido}}
      end)

    case campos do
      {:ok, campos} -> {:ok, struct(modulo, campos)}
      error -> error
    end
  rescue
    _error -> {:error, :struct_desconocido}
  end

  defp atom_existente(nombre) when is_binary(nombre) do
    {:ok, String.to_existing_atom(nombre)}
  rescue
    ArgumentError -> :error
  end

  defp escribir_temporal(path, contenido) do
    sufijo = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    temporal = path <> ".#{sufijo}.tmp"

    case File.write(temporal, contenido, [:binary, :exclusive]) do
      :ok -> {:ok, temporal}
      {:error, _razon} -> {:error, :error_persistencia}
    end
  end

  defp reemplazar_snapshot(temporal, path) do
    case File.rename(temporal, path) do
      :ok ->
        :ok

      {:error, _razon} ->
        File.rm(temporal)
        {:error, :error_persistencia}
    end
  end
end
