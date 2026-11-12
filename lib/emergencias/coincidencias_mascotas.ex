defmodule Emergencias.CoincidenciasMascotas do
  @moduledoc "Similitud determinista y operaciones puras sobre parejas de reportes."
  alias Emergencias.{CoincidenciaMascota, Mascotas, ReporteMascota}

  @pesos %{especie: 30, color: 20, tamano: 15, caracteristicas: 20, zona_codigo: 10, nombre: 5}

  @doc "Compara pérdida y hallazgo: igualdad normalizada y Jaccard de palabras para características."
  def calcular_similitud(%ReporteMascota{} = perdida, %ReporteMascota{} = encontrada) do
    with :ok <- validar_pareja(perdida, encontrada) do
      desglose =
        Map.new(@pesos, fn {campo, peso} ->
          puntos =
            if campo == :caracteristicas,
              do:
                puntos_caracteristicas(perdida.caracteristicas, encontrada.caracteristicas, peso),
              else:
                if(iguales?(Map.get(perdida, campo), Map.get(encontrada, campo)),
                  do: peso,
                  else: 0
                )

          {campo, puntos}
        end)

      {:ok,
       %{puntaje: desglose |> Map.values() |> Enum.sum() |> Float.round(2), desglose: desglose}}
    end
  end

  @doc "Busca parejas compatibles sin mutar reportes; ordena por puntaje descendente e ID."
  def buscar(reportes, id) when is_map(reportes) do
    with {:ok, reporte} <- Mascotas.obtener(reportes, id),
         :ok <- validar_abierto(reporte) do
      reportes
      |> Map.values()
      |> Enum.flat_map(fn candidato ->
        {perdida, encontrada} =
          if reporte.tipo_reporte == :perdida,
            do: {reporte, candidato},
            else: {candidato, reporte}

        case calcular_similitud(perdida, encontrada) do
          {:ok, similitud} ->
            [
              Map.merge(similitud, %{
                reporte: candidato,
                reporte_perdida_id: perdida.id,
                reporte_encontrada_id: encontrada.id
              })
            ]

          {:error, _motivo} ->
            []
        end
      end)
      |> Enum.sort_by(&{-&1.puntaje, &1.reporte.id})
      |> then(&{:ok, &1})
    end
  end

  @doc "Registra una propuesta única y marca ambos reportes como posible coincidencia."
  def proponer(reportes, coincidencias, perdida_id, encontrada_id, contexto) do
    with {:ok, perdida} <- Mascotas.obtener(reportes, perdida_id),
         {:ok, encontrada} <- Mascotas.obtener(reportes, encontrada_id),
         {:ok, similitud} <- calcular_similitud(perdida, encontrada),
         nil <- buscar_pareja(coincidencias, perdida_id, encontrada_id),
         :ok <- validar_contexto(contexto, coincidencias, false) do
      coincidencia =
        construir_coincidencia(perdida_id, encontrada_id, similitud.puntaje, contexto)

      reportes = marcar_posible(reportes, perdida) |> marcar_posible(encontrada)

      {:ok,
       %{
         reportes: reportes,
         coincidencias: Map.put(coincidencias, coincidencia.id, coincidencia),
         coincidencia: coincidencia
       }}
    else
      %CoincidenciaMascota{} -> {:error, :id_duplicado}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc "Confirma y resuelve ambos reportes juntos; puede confirmar una pareja sin propuesta previa."
  def confirmar(reportes, coincidencias, perdida_id, encontrada_id, contexto) do
    propuesta = buscar_pareja(coincidencias, perdida_id, encontrada_id)

    with {:ok, perdida} <- Mascotas.obtener(reportes, perdida_id),
         {:ok, encontrada} <- Mascotas.obtener(reportes, encontrada_id),
         {:ok, similitud} <- calcular_similitud(perdida, encontrada),
         :ok <- validar_sin_confirmacion(coincidencias, perdida_id, encontrada_id),
         contexto <-
           if(is_nil(propuesta), do: contexto, else: Map.put(contexto, :id, propuesta.id)),
         :ok <-
           validar_contexto(
             contexto,
             if(is_nil(propuesta),
               do: coincidencias,
               else: Map.delete(coincidencias, propuesta.id)
             ),
             true
           ),
         {:ok, reportes} <- Mascotas.cambiar_estado(reportes, perdida_id, :resuelta),
         {:ok, reportes} <- Mascotas.cambiar_estado(reportes, encontrada_id, :resuelta) do
      coincidencia = %{
        construir_coincidencia(perdida_id, encontrada_id, similitud.puntaje, contexto)
        | estado: :confirmada,
          confirmada_por: contexto.usuario_id
      }

      {:ok,
       %{
         reportes: reportes,
         coincidencias: Map.put(coincidencias, coincidencia.id, coincidencia),
         coincidencia: coincidencia
       }}
    end
  end

  @doc "Lista coincidencias filtradas por estado o reporte_id, ordenadas por fecha e ID."
  def listar(coincidencias, filtros \\ %{}) when is_map(coincidencias) and is_map(filtros) do
    estado = valor(filtros, :estado)
    reporte_id = valor(filtros, :reporte_id)

    if estado not in [nil, "", :propuesta, :confirmada, "propuesta", "confirmada"] do
      {:error, :estado_invalido}
    else
      coincidencias
      |> Map.values()
      |> Enum.filter(&(estado in [nil, ""] or to_string(&1.estado) == to_string(estado)))
      |> Enum.filter(&(reporte_id in [nil, "", &1.reporte_perdida_id, &1.reporte_encontrada_id]))
      |> Enum.sort_by(&{DateTime.to_unix(&1.fecha, :microsecond), &1.id})
      |> then(&{:ok, &1})
    end
  end

  defp validar_pareja(
         %{tipo_reporte: :perdida} = perdida,
         %{tipo_reporte: :encontrada} = encontrada
       ) do
    with :ok <- validar_abierto(perdida), :ok <- validar_abierto(encontrada) do
      if iguales?(perdida.especie, encontrada.especie), do: :ok, else: {:error, :tipo_invalido}
    end
  end

  defp validar_pareja(_perdida, _encontrada), do: {:error, :tipo_invalido}
  defp validar_abierto(%{estado: estado}) when estado in [:activa, :posible_coincidencia], do: :ok
  defp validar_abierto(%{estado: :resuelta}), do: {:error, :ya_resuelto}
  defp validar_abierto(_reporte), do: {:error, :estado_invalido}

  defp iguales?(a, b) do
    a = Mascotas.normalizar_texto(a)
    a != "" and a == Mascotas.normalizar_texto(b)
  end

  defp puntos_caracteristicas(a, b, peso) do
    a = palabras(a)
    b = palabras(b)
    union = MapSet.union(a, b) |> MapSet.size()

    if union == 0,
      do: 0.0,
      else: Float.round(peso * MapSet.size(MapSet.intersection(a, b)) / union, 2)
  end

  defp palabras(texto) do
    texto
    |> Mascotas.normalizar_texto()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> Enum.reject(
      &(&1 in ["de", "del", "la", "el", "los", "las", "y", "con", "un", "una", "en"])
    )
    |> MapSet.new()
  end

  defp buscar_pareja(coincidencias, perdida_id, encontrada_id),
    do:
      Enum.find_value(coincidencias, fn {_id, c} ->
        if c.reporte_perdida_id == perdida_id and c.reporte_encontrada_id == encontrada_id, do: c
      end)

  defp validar_sin_confirmacion(coincidencias, perdida_id, encontrada_id) do
    if Enum.any?(coincidencias, fn {_id, c} ->
         c.estado == :confirmada and
           (c.reporte_perdida_id == perdida_id or c.reporte_encontrada_id == encontrada_id)
       end), do: {:error, :ya_resuelto}, else: :ok
  end

  defp validar_contexto(contexto, coincidencias, confirmar?) do
    cond do
      not is_binary(Map.get(contexto, :id)) or String.trim(contexto.id) == "" or
          not is_struct(Map.get(contexto, :fecha), DateTime) ->
        {:error, :datos_incompletos}

      confirmar? and
          (not is_binary(Map.get(contexto, :usuario_id)) or String.trim(contexto.usuario_id) == "") ->
        {:error, :datos_incompletos}

      Map.has_key?(coincidencias, contexto.id) ->
        {:error, :id_duplicado}

      true ->
        :ok
    end
  end

  defp construir_coincidencia(perdida_id, encontrada_id, puntaje, contexto),
    do: %CoincidenciaMascota{
      id: contexto.id,
      reporte_perdida_id: perdida_id,
      reporte_encontrada_id: encontrada_id,
      puntaje: puntaje,
      fecha: contexto.fecha
    }

  defp marcar_posible(reportes, %{estado: :activa} = reporte),
    do: Map.put(reportes, reporte.id, %{reporte | estado: :posible_coincidencia})

  defp marcar_posible(reportes, _reporte), do: reportes
  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
end
