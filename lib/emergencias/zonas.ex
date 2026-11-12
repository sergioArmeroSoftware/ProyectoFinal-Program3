defmodule Emergencias.Zonas do
  @moduledoc "Operaciones puras para zonas, sectores y puntos de atención."
  alias Emergencias.{Codigos, PuntoAtencion, Sector, Zona}

  @doc "Agrega una zona con código único."
  def registrar(zonas, %Zona{} = zona) when is_map(zonas) do
    zona = %{
      zona
      | codigo: normalizar_texto(zona.codigo),
        nombre: normalizar_texto(zona.nombre)
    }

    cond do
      not texto_presente?(zona.codigo) or not texto_presente?(zona.nombre) ->
        {:error, :datos_incompletos}

      not Codigos.valido?(:zona, zona.codigo) ->
        {:error, :codigo_invalido}

      zona.nivel_afectacion not in [:baja, :media, :alta, :critica] ->
        {:error, :nivel_afectacion_invalido}

      not (is_integer(zona.personas_estimadas) and zona.personas_estimadas >= 0) ->
        {:error, :cantidad_invalida}

      Map.has_key?(zonas, zona.codigo) ->
        {:error, :id_duplicado}

      true ->
        {:ok, Map.put(zonas, zona.codigo, zona)}
    end
  end

  @doc "Agrega un sector a una zona existente."
  def agregar_sector(zonas, zona_codigo, %Sector{codigo: codigo} = sector) do
    sector = %{sector | codigo: normalizar_texto(codigo), nombre: normalizar_texto(sector.nombre)}
    codigo = sector.codigo

    actualizar_zona(zonas, normalizar_texto(zona_codigo), fn zona ->
      cond do
        not texto_presente?(codigo) or not texto_presente?(sector.nombre) ->
          {:error, :datos_incompletos}

        not Codigos.valido?(:sector, codigo) ->
          {:error, :codigo_invalido}

        buscar_sector(zona.sectores, codigo) ->
          {:error, :id_duplicado}

        true ->
          {:ok, %{zona | sectores: zona.sectores ++ [sector]}}
      end
    end)
  end

  @doc "Agrega un punto a un sector existente dentro de la zona."
  def agregar_punto(zonas, zona_codigo, sector_codigo, %PuntoAtencion{codigo: codigo} = punto) do
    punto = %{punto | codigo: normalizar_texto(codigo), nombre: normalizar_texto(punto.nombre)}

    actualizar_zona(zonas, normalizar_texto(zona_codigo), fn zona ->
      case actualizar_sector(zona.sectores, normalizar_texto(sector_codigo), fn sector ->
             cond do
               not texto_presente?(codigo) or not texto_presente?(punto.nombre) ->
                 {:error, :datos_incompletos}

               not Codigos.valido?(:punto_atencion, codigo) ->
                 {:error, :codigo_invalido}

               buscar_punto(zona.sectores, codigo) ->
                 {:error, :id_duplicado}

               not (is_integer(punto.personas_estimadas) and punto.personas_estimadas >= 0) ->
                 {:error, :cantidad_invalida}

               punto.estado not in [:activo, :inactivo, :saturado] ->
                 {:error, :estado_invalido}

               true ->
                 {:ok, %{sector | puntos: sector.puntos ++ [punto]}}
             end
           end) do
        {:ok, sectores} -> {:ok, %{zona | sectores: sectores}}
        error -> error
      end
    end)
  end

  @doc "Cambia el estado de un punto y devuelve el mapa actualizado de zonas."
  def cambiar_estado_punto(zonas, zona_codigo, sector_codigo, punto_codigo, estado)
      when estado in [:activo, :inactivo, :saturado] do
    actualizar_zona(zonas, normalizar_texto(zona_codigo), fn zona ->
      case actualizar_sector(zona.sectores, normalizar_texto(sector_codigo), fn sector ->
             case actualizar_punto(sector.puntos, normalizar_texto(punto_codigo), estado, []) do
               {:ok, puntos} -> {:ok, %{sector | puntos: puntos}}
               error -> error
             end
           end) do
        {:ok, sectores} -> {:ok, %{zona | sectores: sectores}}
        error -> error
      end
    end)
  end

  def cambiar_estado_punto(_zonas, _zona_codigo, _sector_codigo, _punto_codigo, _estado),
    do: {:error, :estado_invalido}

  @doc "Recorre recursivamente y cuenta los sectores de una zona."
  def contar_sectores(%Zona{sectores: sectores}), do: contar_lista(sectores)
  defp contar_lista([]), do: 0
  defp contar_lista([_ | resto]), do: 1 + contar_lista(resto)

  @doc "Recorre sectores y cuenta todos los puntos de una zona."
  def contar_puntos(%Zona{sectores: sectores}), do: contar_puntos_en_sectores(sectores)
  defp contar_puntos_en_sectores([]), do: 0

  defp contar_puntos_en_sectores([sector | resto]),
    do: contar_lista(sector.puntos) + contar_puntos_en_sectores(resto)

  @doc "Cuenta recursivamente los puntos que tienen el estado indicado."
  def contar_puntos_por_estado(%Zona{sectores: sectores}, estado),
    do: contar_estado(sectores, estado)

  defp contar_estado([], _estado), do: 0

  defp contar_estado([sector | resto], estado),
    do: contar_puntos_estado(sector.puntos, estado) + contar_estado(resto, estado)

  defp contar_puntos_estado([], _estado), do: 0

  defp contar_puntos_estado([%PuntoAtencion{estado: estado} | resto], estado),
    do: 1 + contar_puntos_estado(resto, estado)

  defp contar_puntos_estado([_punto | resto], estado), do: contar_puntos_estado(resto, estado)

  @doc "Busca recursivamente un punto por código en una lista de sectores."
  def buscar_punto(sectores, codigo),
    do: buscar_punto_en_sectores(sectores, normalizar_texto(codigo))

  defp buscar_punto_en_sectores([], _codigo), do: nil

  defp buscar_punto_en_sectores([sector | resto], codigo) do
    case buscar_punto_en_lista(sector.puntos, codigo) do
      nil -> buscar_punto_en_sectores(resto, codigo)
      punto -> punto
    end
  end

  defp buscar_punto_en_lista([], _codigo), do: nil
  defp buscar_punto_en_lista([%PuntoAtencion{codigo: codigo} = punto | _resto], codigo), do: punto
  defp buscar_punto_en_lista([_punto | resto], codigo), do: buscar_punto_en_lista(resto, codigo)

  defp actualizar_zona(zonas, codigo, funcion) do
    case Map.fetch(zonas, codigo) do
      {:ok, zona} ->
        case funcion.(zona) do
          {:ok, zona_actualizada} -> {:ok, Map.put(zonas, codigo, zona_actualizada)}
          error -> error
        end

      :error ->
        {:error, :no_encontrado}
    end
  end

  defp actualizar_sector(sectores, codigo, funcion),
    do: actualizar_sector(sectores, codigo, funcion, [])

  defp actualizar_sector([], _codigo, _funcion, _acumulados), do: {:error, :no_encontrado}

  defp actualizar_sector([%Sector{codigo: codigo} = sector | resto], codigo, funcion, acumulados) do
    case funcion.(sector) do
      {:ok, sector_actualizado} -> {:ok, Enum.reverse(acumulados, [sector_actualizado | resto])}
      error -> error
    end
  end

  defp actualizar_sector([sector | resto], codigo, funcion, acumulados),
    do: actualizar_sector(resto, codigo, funcion, [sector | acumulados])

  defp actualizar_punto([], _codigo, _estado, _acumulados), do: {:error, :no_encontrado}

  defp actualizar_punto(
         [%PuntoAtencion{codigo: codigo} = punto | resto],
         codigo,
         estado,
         acumulados
       ) do
    puntos = Enum.reverse(acumulados, [%{punto | estado: estado} | resto])
    {:ok, puntos}
  end

  defp actualizar_punto([punto | resto], codigo, estado, acumulados),
    do: actualizar_punto(resto, codigo, estado, [punto | acumulados])

  defp buscar_sector([], _codigo), do: nil
  defp buscar_sector([%Sector{codigo: codigo} = sector | _resto], codigo), do: sector
  defp buscar_sector([_sector | resto], codigo), do: buscar_sector(resto, codigo)

  defp texto_presente?(valor), do: is_binary(valor) and String.trim(valor) != ""
  defp normalizar_texto(valor) when is_binary(valor), do: String.trim(valor)
  defp normalizar_texto(_valor), do: nil
end
