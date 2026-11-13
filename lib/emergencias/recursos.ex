defmodule Emergencias.Recursos do
  @moduledoc "Reglas puras para inventario, asignaciones, devoluciones y transferencias."

  alias Emergencias.Recurso
  alias Emergencias.Codigos

  @doc "Registra inventario en una zona y ubicación existentes."
  def registrar(recursos, zonas, attrs)
      when is_map(recursos) and is_map(zonas) and is_map(attrs) do
    recurso = %Recurso{
      codigo: valor(attrs, :codigo) |> normalizar_texto(),
      nombre: valor(attrs, :nombre) |> normalizar_texto(),
      categoria: valor(attrs, :categoria) |> normalizar_texto(),
      cantidad_disponible: valor(attrs, :cantidad_disponible) |> normalizar_cantidad(),
      unidad: valor(attrs, :unidad) |> normalizar_texto(),
      ubicacion: valor(attrs, :ubicacion) |> normalizar_texto(),
      zona_codigo: valor(attrs, :zona_codigo) |> normalizar_texto()
    }

    cond do
      not texto_presente?(recurso.codigo) or not texto_presente?(recurso.nombre) or
        not texto_presente?(recurso.categoria) or not texto_presente?(recurso.unidad) or
        not texto_presente?(recurso.ubicacion) or not texto_presente?(recurso.zona_codigo) ->
        {:error, :datos_incompletos}

      not (is_integer(recurso.cantidad_disponible) and recurso.cantidad_disponible >= 0) ->
        {:error, :cantidad_invalida}

      not Codigos.valido?(:recurso, recurso.codigo) ->
        {:error, :codigo_invalido}

      not Map.has_key?(zonas, recurso.zona_codigo) ->
        {:error, :zona_no_encontrada}

      Map.has_key?(recursos, recurso.codigo) ->
        {:error, :id_duplicado}

      true ->
        {:ok, Map.put(recursos, recurso.codigo, recurso)}
    end
  end

  @doc "Descuenta una cantidad positiva solo si el inventario alcanza."
  def descontar(recursos, codigo, cantidad) when is_map(recursos) do
    with {:ok, cantidad} <- cantidad_positiva(cantidad),
         {:ok, %Recurso{} = recurso} <- Map.fetch(recursos, codigo),
         true <- recurso.cantidad_disponible >= cantidad do
      {:ok,
       Map.put(recursos, codigo, %{
         recurso
         | cantidad_disponible: recurso.cantidad_disponible - cantidad
       })}
    else
      :error -> {:error, :no_encontrado}
      false -> {:error, :stock_insuficiente}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc "Devuelve una cantidad positiva al inventario de un recurso existente."
  def ingresar(recursos, codigo, cantidad) when is_map(recursos) do
    with {:ok, cantidad} <- cantidad_positiva(cantidad),
         {:ok, %Recurso{} = recurso} <- Map.fetch(recursos, codigo) do
      {:ok,
       Map.put(recursos, codigo, %{
         recurso
         | cantidad_disponible: recurso.cantidad_disponible + cantidad
       })}
    else
      :error -> {:error, :no_encontrado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc "Transfiere inventario entre ubicaciones; separa el lote si el movimiento es parcial."
  def transferir(recursos, codigo, origen, destino, cantidad, codigo_destino)
      when is_map(recursos) do
    with {:ok, cantidad} <- cantidad_positiva(cantidad),
         {:ok, %Recurso{} = recurso} <- Map.fetch(recursos, codigo),
         :ok <- validar_ubicaciones(recurso, origen, destino),
         true <- recurso.cantidad_disponible >= cantidad,
         {:ok, recursos, transferido} <-
           mover_lote(recursos, recurso, destino, cantidad, codigo_destino) do
      {:ok, recursos, transferido}
    else
      :error -> {:error, :no_encontrado}
      false -> {:error, :stock_insuficiente}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc "Lista recursos filtrados por categoría, zona, ubicación o existencia crítica."
  def listar(recursos, filtros \\ %{}, criticos? \\ false)
      when is_map(recursos) and is_map(filtros) do
    filtros = %{
      categoria: valor(filtros, :categoria) |> normalizar_texto(),
      zona_codigo: valor(filtros, :zona_codigo) |> normalizar_texto(),
      ubicacion: valor(filtros, :ubicacion) |> normalizar_texto(),
      codigo: valor(filtros, :codigo) |> normalizar_texto()
    }

    recursos
    |> Map.values()
    |> Enum.filter(fn recurso ->
      (is_nil(filtros.categoria) or
         normalizar_busqueda(recurso.categoria) == normalizar_busqueda(filtros.categoria)) and
        (is_nil(filtros.zona_codigo) or recurso.zona_codigo == filtros.zona_codigo) and
        (is_nil(filtros.ubicacion) or
           normalizar_busqueda(recurso.ubicacion) == normalizar_busqueda(filtros.ubicacion)) and
        (is_nil(filtros.codigo) or recurso.codigo == filtros.codigo) and
        (not criticos? or recurso.cantidad_disponible == 0)
    end)
    |> Enum.sort_by(& &1.codigo)
    |> then(&{:ok, &1})
  end

  @doc "Lista movimientos por recurso o zona, del más reciente al más antiguo."
  def movimientos(movimientos, recursos, filtros \\ %{})
      when is_map(movimientos) and is_map(recursos) and is_map(filtros) do
    codigo = valor(filtros, :recurso_codigo) |> normalizar_texto()
    zona_codigo = valor(filtros, :zona_codigo) |> normalizar_texto()

    movimientos
    |> Map.values()
    |> Enum.filter(fn movimiento ->
      recurso = Map.get(recursos, movimiento.recurso_codigo)

      (is_nil(codigo) or movimiento.recurso_codigo == codigo) and
        (is_nil(zona_codigo) or (not is_nil(recurso) and recurso.zona_codigo == zona_codigo))
    end)
    |> Enum.sort_by(fn movimiento -> {fecha_orden(movimiento.fecha), movimiento.id} end, :desc)
    |> then(&{:ok, &1})
  end

  defp mover_lote(recursos, recurso, destino, cantidad, _codigo_destino)
       when recurso.cantidad_disponible == cantidad do
    transferido = %{recurso | ubicacion: destino}
    {:ok, Map.put(recursos, recurso.codigo, transferido), transferido}
  end

  defp mover_lote(recursos, recurso, destino, cantidad, codigo_destino) do
    cond do
      not texto_presente?(codigo_destino) ->
        {:error, :datos_incompletos}

      Map.has_key?(recursos, codigo_destino) ->
        {:error, :id_duplicado}

      true ->
        origen_actualizado = %{
          recurso
          | cantidad_disponible: recurso.cantidad_disponible - cantidad
        }

        transferido = %{
          recurso
          | codigo: codigo_destino,
            cantidad_disponible: cantidad,
            ubicacion: destino
        }

        recursos =
          recursos
          |> Map.put(recurso.codigo, origen_actualizado)
          |> Map.put(codigo_destino, transferido)

        {:ok, recursos, transferido}
    end
  end

  defp validar_ubicaciones(%Recurso{ubicacion: ubicacion}, origen, destino) do
    origen = normalizar_texto(origen)
    destino = normalizar_texto(destino)

    cond do
      is_nil(origen) or is_nil(destino) -> {:error, :datos_incompletos}
      ubicacion != origen -> {:error, :origen_invalido}
      origen == destino -> {:error, :destino_invalido}
      true -> :ok
    end
  end

  defp cantidad_positiva(cantidad) do
    cantidad = normalizar_cantidad(cantidad)

    if is_integer(cantidad) and cantidad > 0,
      do: {:ok, cantidad},
      else: {:error, :cantidad_invalida}
  end

  defp fecha_orden(%DateTime{} = fecha), do: DateTime.to_unix(fecha, :microsecond)
  defp fecha_orden(_fecha), do: 0

  defp normalizar_cantidad(valor) when is_integer(valor), do: valor

  defp normalizar_cantidad(valor) when is_binary(valor) do
    case Integer.parse(String.trim(valor)) do
      {cantidad, ""} -> cantidad
      _resultado -> nil
    end
  end

  defp normalizar_cantidad(_valor), do: nil

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
  defp normalizar_texto(valor) when is_binary(valor), do: valor |> String.trim() |> empty_to_nil()
  defp normalizar_texto(_valor), do: nil
  defp normalizar_busqueda(nil), do: nil
  defp normalizar_busqueda(valor), do: valor |> String.downcase() |> String.trim()
  defp texto_presente?(valor), do: is_binary(valor) and String.trim(valor) != ""
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(valor), do: valor
end
