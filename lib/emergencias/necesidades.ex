defmodule Emergencias.Necesidades do
  @moduledoc "Reglas puras para registrar, cambiar y consultar necesidades."

  alias Emergencias.Necesidad

  @tipos [
    :agua,
    :alimentos,
    :medicamentos,
    :primeros_auxilios,
    :refugio,
    :transporte,
    :rescate,
    :otra
  ]
  @prioridades [:critica, :alta, :media, :baja]
  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  @transiciones %{
    pendiente: [:asignada, :cancelada],
    asignada: [:en_atencion, :cancelada],
    en_atencion: [:atendida],
    atendida: [],
    cancelada: []
  }

  @doc "Registra una necesidad validando su zona, campos y prioridad."
  def registrar(necesidades, zonas, attrs)
      when is_map(necesidades) and is_map(zonas) and is_map(attrs) do
    necesidad = %Necesidad{
      id: valor(attrs, :id),
      tipo: valor(attrs, :tipo) |> normalizar_tipo(),
      descripcion: valor(attrs, :descripcion) |> normalizar_texto(),
      cantidad: valor(attrs, :cantidad) |> normalizar_cantidad(),
      prioridad: valor(attrs, :prioridad) |> normalizar_enum(@prioridades),
      zona_codigo: valor(attrs, :zona_codigo) |> normalizar_texto(),
      responsable_id: valor(attrs, :responsable_id) |> normalizar_texto()
    }

    cond do
      not texto_presente?(necesidad.id) or is_nil(necesidad.tipo) or
        not texto_presente?(necesidad.descripcion) or not texto_presente?(necesidad.zona_codigo) or
          not texto_presente?(necesidad.responsable_id) ->
        {:error, :datos_incompletos}

      not Map.has_key?(zonas, necesidad.zona_codigo) ->
        {:error, :zona_no_encontrada}

      not (is_integer(necesidad.cantidad) and necesidad.cantidad >= 0) ->
        {:error, :cantidad_invalida}

      is_nil(necesidad.prioridad) ->
        {:error, :prioridad_invalida}

      Map.has_key?(necesidades, necesidad.id) ->
        {:error, :id_duplicado}

      true ->
        {:ok, Map.put(necesidades, necesidad.id, necesidad)}
    end
  end

  @doc "Cambia el estado si existe una transición aprobada en el contrato."
  def cambiar_estado(necesidades, id, estado) when is_map(necesidades) do
    estado = normalizar_enum(estado, @estados)

    case Map.fetch(necesidades, id) do
      {:ok, %Necesidad{estado: estado_actual}} when estado_actual == estado ->
        if estado_actual in [:atendida, :cancelada],
          do: {:error, :ya_resuelto},
          else: {:error, :transicion_invalida}

      {:ok, %Necesidad{estado: anterior} = necesidad} ->
        if estado in Map.get(@transiciones, anterior, []) do
          {:ok, Map.put(necesidades, id, %{necesidad | estado: estado})}
        else
          {:error, :transicion_invalida}
        end

      :error ->
        {:error, :no_encontrado}
    end
  end

  @doc "Devuelve necesidades filtradas y ordenadas por prioridad y fecha de registro."
  def listar(necesidades, filtros \\ %{}, actividad \\ [])
      when is_map(necesidades) and is_map(filtros) and is_list(actividad) do
    with {:ok, filtros} <- normalizar_filtros(filtros) do
      fechas = fechas_de_registro(actividad)

      necesidades
      |> Map.values()
      |> Enum.filter(&coincide?(&1, filtros))
      |> Enum.sort_by(fn necesidad ->
        {prioridad_orden(necesidad.prioridad), fecha_orden(Map.get(fechas, necesidad.id)),
         necesidad.id}
      end)
      |> then(&{:ok, &1})
    end
  end

  @doc "Devuelve la cantidad solicitada que aún no está cubierta por asignaciones activas."
  def cantidad_pendiente(%Necesidad{cantidad: cantidad, id: necesidad_id}, asignaciones)
      when is_map(asignaciones) do
    asignaciones
    |> Map.values()
    |> Enum.filter(&(&1.necesidad_id == necesidad_id and &1.estado in [:asignada, :en_atencion]))
    |> Enum.reduce(0, &(&1.cantidad + &2))
    |> then(&max(cantidad - &1, 0))
  end

  @doc "Indica si una necesidad puede recibir otra asignación."
  def asignable?(%Necesidad{estado: estado}), do: estado in [:pendiente, :asignada]

  defp normalizar_filtros(filtros) do
    prioridad = valor(filtros, :prioridad) |> filtro_enum(@prioridades)
    estado = valor(filtros, :estado) |> filtro_enum(@estados)
    tipo = valor(filtros, :tipo) |> filtro_tipo()

    cond do
      prioridad == :invalido ->
        {:error, :prioridad_invalida}

      estado == :invalido ->
        {:error, :estado_invalido}

      tipo == :invalido ->
        {:error, :tipo_invalido}

      true ->
        {:ok,
         %{
           zona_codigo: valor(filtros, :zona_codigo) |> normalizar_texto(),
           prioridad: prioridad,
           estado: estado,
           tipo: tipo
         }}
    end
  end

  defp coincide?(necesidad, filtros) do
    (is_nil(filtros.zona_codigo) or necesidad.zona_codigo == filtros.zona_codigo) and
      (is_nil(filtros.prioridad) or necesidad.prioridad == filtros.prioridad) and
      (is_nil(filtros.estado) or necesidad.estado == filtros.estado) and
      (is_nil(filtros.tipo) or necesidad.tipo == filtros.tipo)
  end

  defp fechas_de_registro(actividad) do
    Enum.reduce(actividad, %{}, fn
      %Emergencias.RegistroActividad{accion: :registrar_necesidad, entidad_id: id, fecha: fecha},
      fechas ->
        Map.put_new(fechas, id, fecha)

      _registro, fechas ->
        fechas
    end)
  end

  defp fecha_orden(%DateTime{} = fecha), do: DateTime.to_unix(fecha, :microsecond)
  defp fecha_orden(_fecha), do: 0

  defp prioridad_orden(:critica), do: 0
  defp prioridad_orden(:alta), do: 1
  defp prioridad_orden(:media), do: 2
  defp prioridad_orden(:baja), do: 3
  defp prioridad_orden(_prioridad), do: 4

  defp filtro_enum(nil, _opciones), do: nil
  defp filtro_enum("", _opciones), do: nil
  defp filtro_enum(valor, opciones), do: normalizar_enum(valor, opciones) || :invalido

  defp filtro_tipo(nil), do: nil
  defp filtro_tipo(""), do: nil
  defp filtro_tipo(valor), do: normalizar_tipo(valor) || :invalido

  defp normalizar_tipo(valor) when is_atom(valor) and valor in @tipos, do: valor

  defp normalizar_tipo(valor) when is_binary(valor) do
    valor = valor |> String.trim() |> String.downcase()
    Enum.find(@tipos, &(Atom.to_string(&1) == valor))
  end

  defp normalizar_tipo(_valor), do: nil

  defp normalizar_enum(valor, opciones) when is_atom(valor) do
    if valor in opciones, do: valor, else: nil
  end

  defp normalizar_enum(valor, opciones) when is_binary(valor) do
    valor = String.trim(valor)
    Enum.find(opciones, &(Atom.to_string(&1) == valor))
  end

  defp normalizar_enum(_valor, _opciones), do: nil

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
  defp texto_presente?(valor), do: is_binary(valor) and String.trim(valor) != ""
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(valor), do: valor
end
