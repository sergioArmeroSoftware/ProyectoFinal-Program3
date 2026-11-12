defmodule Emergencias.Mascotas do
  @moduledoc "Reglas puras para registrar, consultar y cambiar estados de reportes de mascotas."
  alias Emergencias.ReporteMascota

  @tipos [:perdida, :encontrada]
  @estados [:activa, :posible_coincidencia, :resuelta]
  @transiciones %{
    activa: [:posible_coincidencia, :resuelta],
    posible_coincidencia: [:activa, :resuelta],
    resuelta: []
  }

  @doc "Registra con ID único y zona existente; el nombre, color y tamaño son opcionales."
  def registrar(reportes, zonas, attrs)
      when is_map(reportes) and is_map(zonas) and is_map(attrs) do
    reporte = %ReporteMascota{
      id: valor(attrs, :id) |> texto(),
      tipo_reporte: valor(attrs, :tipo_reporte) |> enum(@tipos),
      especie: valor(attrs, :especie) |> normalizar_texto(),
      nombre: valor(attrs, :nombre) |> texto(),
      caracteristicas: valor(attrs, :caracteristicas) |> texto(),
      color: valor(attrs, :color) |> texto(),
      tamano: valor(attrs, :tamano) |> texto(),
      zona_codigo: valor(attrs, :zona_codigo) |> texto(),
      contacto: valor(attrs, :contacto) |> texto()
    }

    cond do
      is_nil(reporte.id) or reporte.especie == "" or is_nil(reporte.caracteristicas) or
        is_nil(reporte.zona_codigo) or is_nil(reporte.contacto) ->
        {:error, :datos_incompletos}

      is_nil(reporte.tipo_reporte) ->
        {:error, :tipo_invalido}

      not Map.has_key?(zonas, reporte.zona_codigo) ->
        {:error, :zona_no_encontrada}

      Map.has_key?(reportes, reporte.id) ->
        {:error, :id_duplicado}

      true ->
        {:ok, Map.put(reportes, reporte.id, reporte)}
    end
  end

  @doc "Obtiene un reporte por ID."
  def obtener(reportes, id) when is_map(reportes) do
    case Map.fetch(reportes, id) do
      {:ok, reporte} -> {:ok, reporte}
      :error -> {:error, :no_encontrado}
    end
  end

  @doc "Lista por ID con filtros tipo_reporte, especie, zona_codigo y estado."
  def listar(reportes, filtros \\ %{}) when is_map(reportes) and is_map(filtros) do
    tipo = valor(filtros, :tipo_reporte)
    estado = valor(filtros, :estado)
    especie = valor(filtros, :especie) |> normalizar_texto()
    zona = valor(filtros, :zona_codigo) |> texto()

    cond do
      tipo not in [nil, ""] and is_nil(enum(tipo, @tipos)) ->
        {:error, :tipo_invalido}

      estado not in [nil, ""] and is_nil(enum(estado, @estados)) ->
        {:error, :estado_invalido}

      true ->
        reportes
        |> Map.values()
        |> Enum.filter(&(tipo in [nil, ""] or &1.tipo_reporte == enum(tipo, @tipos)))
        |> Enum.filter(&(estado in [nil, ""] or &1.estado == enum(estado, @estados)))
        |> Enum.filter(&(especie == "" or normalizar_texto(&1.especie) == especie))
        |> Enum.filter(&(is_nil(zona) or &1.zona_codigo == zona))
        |> Enum.sort_by(& &1.id)
        |> then(&{:ok, &1})
    end
  end

  @doc "Aplica una transición acordada sin reabrir reportes resueltos."
  def cambiar_estado(reportes, id, estado) when is_map(reportes) do
    nuevo = enum(estado, @estados)

    with {:ok, reporte} <- obtener(reportes, id) do
      cond do
        is_nil(nuevo) -> {:error, :estado_invalido}
        reporte.estado == :resuelta -> {:error, :ya_resuelto}
        nuevo not in Map.get(@transiciones, reporte.estado, []) -> {:error, :transicion_invalida}
        true -> {:ok, Map.put(reportes, id, %{reporte | estado: nuevo})}
      end
    end
  end

  @doc "Normaliza minúsculas, tildes y espacios para comparaciones deterministas."
  def normalizar_texto(valor) when is_binary(valor) do
    valor
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.split()
    |> Enum.join(" ")
  end

  def normalizar_texto(_valor), do: ""

  defp enum(valor, opciones) when is_atom(valor), do: if(valor in opciones, do: valor, else: nil)

  defp enum(valor, opciones) when is_binary(valor),
    do: Enum.find(opciones, &(Atom.to_string(&1) == String.trim(valor)))

  defp enum(_valor, _opciones), do: nil
  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))

  defp texto(valor) when is_binary(valor) do
    case String.trim(valor) do
      "" -> nil
      texto -> texto
    end
  end

  defp texto(_valor), do: nil
end
