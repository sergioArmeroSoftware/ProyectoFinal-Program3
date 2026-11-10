defmodule Emergencias.Albergues do
  @moduledoc "Cálculos de capacidad y ocupación a partir de estancias activas."
  alias Emergencias.{Albergue, EstanciaAlbergue}

  @doc "Registra un albergue cuando su zona existe y su capacidad es válida."
  def registrar(albergues, zonas, attrs)
      when is_map(albergues) and is_map(zonas) and is_map(attrs) do
    codigo = attrs |> valor(:codigo) |> normalizar_texto()
    nombre = attrs |> valor(:nombre) |> normalizar_texto()
    zona_codigo = attrs |> valor(:zona_codigo) |> normalizar_texto()
    capacidad = valor(attrs, :capacidad_maxima)

    cond do
      is_nil(codigo) or is_nil(nombre) or is_nil(zona_codigo) ->
        {:error, :datos_incompletos}

      not Map.has_key?(zonas, zona_codigo) ->
        {:error, :zona_no_encontrada}

      not (is_integer(capacidad) and capacidad >= 0) ->
        {:error, :capacidad_invalida}

      Map.has_key?(albergues, codigo) ->
        {:error, :id_duplicado}

      true ->
        albergue = %Albergue{
          codigo: codigo,
          nombre: nombre,
          zona_codigo: zona_codigo,
          capacidad_maxima: capacidad
        }

        {:ok, Map.put(albergues, codigo, albergue)}
    end
  end

  @doc "Lista albergues ordenados por código para presentación estable."
  def listar(albergues), do: albergues |> Map.values() |> Enum.sort_by(& &1.codigo)

  @doc "Calcula las plazas ocupadas en un albergue."
  def ocupacion(estancias, codigo) do
    estancias
    |> Map.values()
    |> Enum.count(&(&1.albergue_codigo == codigo and is_nil(&1.fecha_salida)))
  end

  @doc "Entrega capacidad, ocupación y plazas libres de un albergue."
  def disponibilidad(albergues, estancias, codigo) do
    with {:ok, albergue} <- fetch_albergue(albergues, codigo) do
      ocupadas = ocupacion(estancias, codigo)

      {:ok,
       %{
         albergue: albergue,
         capacidad: albergue.capacidad_maxima,
         ocupadas: ocupadas,
         disponibles: max(albergue.capacidad_maxima - ocupadas, 0)
       }}
    end
  end

  @doc "Valida si un ingreso cabe en la capacidad disponible."
  def validar_ingreso(%Albergue{capacidad_maxima: capacidad} = albergue, estancias)
      when is_integer(capacidad) and capacidad >= 0 do
    if ocupacion(estancias, albergue.codigo) < capacidad,
      do: :ok,
      else: {:error, :capacidad_insuficiente}
  end

  @doc "Crea una estancia activa después de validar la capacidad."
  def registrar_ingreso(albergues, estancias, codigo, persona_id, id, fecha_ingreso) do
    cond do
      Map.has_key?(estancias, id) ->
        {:error, :id_duplicado}

      Enum.any?(Map.values(estancias), &(&1.persona_id == persona_id and is_nil(&1.fecha_salida))) ->
        {:error, :persona_ya_albergada}

      true ->
        with {:ok, albergue} <- fetch_albergue(albergues, codigo),
             :ok <- validar_ingreso(albergue, estancias) do
          estancia = %EstanciaAlbergue{
            id: id,
            albergue_codigo: codigo,
            persona_id: persona_id,
            fecha_ingreso: fecha_ingreso
          }

          {:ok, Map.put(estancias, id, estancia)}
        end
    end
  end

  @doc "Registra el ingreso solo si la persona ya está en el mapa compartido de personas."
  def registrar_ingreso(albergues, estancias, personas, codigo, persona_id, id, fecha_ingreso) do
    if Map.has_key?(personas, persona_id) do
      registrar_ingreso(albergues, estancias, codigo, persona_id, id, fecha_ingreso)
    else
      {:error, :persona_no_encontrada}
    end
  end

  @doc "Cierra la estancia activa de una persona en el albergue indicado."
  def registrar_salida(estancias, codigo, persona_id, fecha_salida) do
    case Enum.find(estancias, fn {_id, estancia} ->
           estancia.albergue_codigo == codigo and estancia.persona_id == persona_id and
             is_nil(estancia.fecha_salida)
         end) do
      {id, estancia} ->
        {:ok, Map.put(estancias, id, %{estancia | fecha_salida: fecha_salida})}

      nil ->
        {:error, :estancia_activa_no_encontrada}
    end
  end

  @doc "Devuelve las estancias activas de un albergue ordenadas por fecha de ingreso."
  def estancias_activas(estancias, codigo) do
    estancias
    |> Map.values()
    |> Enum.filter(&(&1.albergue_codigo == codigo and is_nil(&1.fecha_salida)))
    |> Enum.sort_by(& &1.fecha_ingreso)
  end

  defp fetch_albergue(albergues, codigo) do
    case Map.fetch(albergues, codigo) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, :no_encontrado}
    end
  end

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
  defp normalizar_texto(valor) when is_binary(valor), do: valor |> String.trim() |> empty_to_nil()
  defp normalizar_texto(_valor), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(valor), do: valor
end
