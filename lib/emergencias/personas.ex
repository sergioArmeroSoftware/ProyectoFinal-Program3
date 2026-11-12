defmodule Emergencias.Personas do
  @moduledoc "Reglas puras para registrar, consultar y cambiar estados de personas."
  alias Emergencias.{CambioEstadoPersona, PersonaAfectada}

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @doc "Registra una persona con ID único, zona existente y datos válidos."
  def registrar(personas, zonas, attrs)
      when is_map(personas) and is_map(zonas) and is_map(attrs) do
    persona = %PersonaAfectada{
      id: valor(attrs, :id) |> normalizar_texto(),
      nombre: valor(attrs, :nombre) |> normalizar_texto(),
      documento_referencia: valor(attrs, :documento_referencia) |> normalizar_texto(),
      edad: valor(attrs, :edad) |> normalizar_edad(),
      zona_codigo: valor(attrs, :zona_codigo) |> normalizar_texto(),
      estado: valor(attrs, :estado, :reportada) |> normalizar_estado()
    }

    cond do
      is_nil(persona.id) or is_nil(persona.nombre) or is_nil(persona.zona_codigo) ->
        {:error, :datos_incompletos}

      not Map.has_key?(zonas, persona.zona_codigo) ->
        {:error, :zona_no_encontrada}

      not (is_integer(persona.edad) and persona.edad >= 0) ->
        {:error, :cantidad_invalida}

      is_nil(persona.estado) ->
        {:error, :estado_invalido}

      Map.has_key?(personas, persona.id) ->
        {:error, :id_duplicado}

      true ->
        {:ok, Map.put(personas, persona.id, persona)}
    end
  end

  @doc "Obtiene una persona por ID o devuelve :no_encontrado."
  def obtener(personas, id) when is_map(personas) do
    case Map.fetch(personas, id) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, :no_encontrado}
    end
  end

  @doc "Busca por documento exacto; un documento vacío no produce coincidencias."
  def buscar_por_documento(personas, documento) when is_map(personas) do
    case normalizar_texto(documento) do
      nil ->
        {:error, :datos_incompletos}

      documento ->
        personas
        |> Map.values()
        |> Enum.filter(&(&1.documento_referencia == documento))
        |> Enum.sort_by(& &1.id)
        |> then(&{:ok, &1})
    end
  end

  @doc "Lista por ID, filtrando opcionalmente por zona y estado."
  def listar(personas, filtros \\ %{}) when is_map(personas) and is_map(filtros) do
    estado = valor(filtros, :estado)
    zona = valor(filtros, :zona_codigo) |> normalizar_texto()

    if estado not in [nil, ""] and is_nil(normalizar_estado(estado)) do
      {:error, :estado_invalido}
    else
      personas
      |> Map.values()
      |> Enum.filter(&(is_nil(zona) or &1.zona_codigo == zona))
      |> Enum.filter(&(estado in [nil, ""] or &1.estado == normalizar_estado(estado)))
      |> Enum.sort_by(& &1.id)
      |> then(&{:ok, &1})
    end
  end

  @doc "Actualiza persona e historial juntos. El contexto aporta id, fecha y usuario_id."
  def cambiar_estado(personas, historial, persona_id, estado, contexto)
      when is_map(personas) and is_list(historial) and is_map(contexto) do
    with {:ok, persona} <- obtener(personas, persona_id),
         :ok <- validar_transicion(persona.estado, normalizar_estado(estado)),
         :ok <- validar_contexto(historial, contexto) do
      cambio = %CambioEstadoPersona{
        id: valor(contexto, :id),
        persona_id: persona_id,
        estado_anterior: persona.estado,
        estado_nuevo: normalizar_estado(estado),
        fecha: valor(contexto, :fecha),
        usuario_id: valor(contexto, :usuario_id)
      }

      {:ok,
       %{
         personas: Map.put(personas, persona_id, %{persona | estado: cambio.estado_nuevo}),
         historial: historial ++ [cambio]
       }}
    end
  end

  @doc "Consulta los cambios de una persona, del más antiguo al más reciente."
  def historial(historial, persona_id) when is_list(historial) do
    historial
    |> Enum.filter(&(&1.persona_id == persona_id))
    |> Enum.sort_by(&{DateTime.to_unix(&1.fecha, :microsecond), &1.id})
    |> then(&{:ok, &1})
  end

  defp validar_transicion(_anterior, nil), do: {:error, :estado_invalido}
  defp validar_transicion(:reunificada, _nuevo), do: {:error, :ya_resuelto}
  defp validar_transicion(estado, estado), do: {:error, :transicion_invalida}

  defp validar_transicion(anterior, nuevo) when anterior in @estados and nuevo in @estados,
    do: :ok

  defp validar_transicion(_anterior, _nuevo), do: {:error, :transicion_invalida}

  defp validar_contexto(historial, contexto) do
    cond do
      is_nil(normalizar_texto(valor(contexto, :id))) or
        is_nil(normalizar_texto(valor(contexto, :usuario_id))) or
          not is_struct(valor(contexto, :fecha), DateTime) ->
        {:error, :datos_incompletos}

      Enum.any?(historial, &(&1.id == valor(contexto, :id))) ->
        {:error, :id_duplicado}

      true ->
        :ok
    end
  end

  defp normalizar_estado(valor) when valor in @estados, do: valor

  defp normalizar_estado(valor) when is_binary(valor),
    do: Enum.find(@estados, &(Atom.to_string(&1) == String.trim(valor)))

  defp normalizar_estado(_valor), do: nil
  defp normalizar_edad(valor) when is_integer(valor), do: valor

  defp normalizar_edad(valor) when is_binary(valor) do
    case Integer.parse(String.trim(valor)) do
      {edad, ""} -> edad
      _resultado -> nil
    end
  end

  defp normalizar_edad(_valor), do: nil

  defp valor(attrs, clave, default \\ nil),
    do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave), default))

  defp normalizar_texto(valor) when is_binary(valor), do: valor |> String.trim() |> empty_to_nil()
  defp normalizar_texto(_valor), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(valor), do: valor
end
