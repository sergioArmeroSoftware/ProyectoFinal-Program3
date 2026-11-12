defmodule Emergencias.Mensajes do
  @moduledoc "Reglas puras para crear, consultar y entregar mensajes familiares."
  alias Emergencias.MensajeFamiliar

  @doc "Crea un mensaje pendiente; el coordinador aporta id y fecha en attrs."
  def crear(mensajes, personas, persona_id, attrs)
      when is_map(mensajes) and is_map(personas) and is_map(attrs) do
    mensaje = %MensajeFamiliar{
      id: valor(attrs, :id) |> normalizar_texto(),
      persona_id: persona_id,
      fecha: valor(attrs, :fecha),
      remitente: valor(attrs, :remitente) |> normalizar_texto(),
      destinatario: valor(attrs, :destinatario) |> normalizar_texto(),
      contenido: valor(attrs, :contenido) |> normalizar_texto()
    }

    cond do
      not Map.has_key?(personas, persona_id) ->
        {:error, :no_encontrado}

      is_nil(mensaje.id) or is_nil(mensaje.remitente) or is_nil(mensaje.destinatario) or
        is_nil(mensaje.contenido) or not is_struct(mensaje.fecha, DateTime) ->
        {:error, :datos_incompletos}

      Map.has_key?(mensajes, mensaje.id) ->
        {:error, :id_duplicado}

      true ->
        {:ok, Map.put(mensajes, mensaje.id, mensaje)}
    end
  end

  @doc "Obtiene un mensaje por ID o devuelve :no_encontrado."
  def obtener(mensajes, id) when is_map(mensajes) do
    case Map.fetch(mensajes, id) do
      {:ok, mensaje} -> {:ok, mensaje}
      :error -> {:error, :no_encontrado}
    end
  end

  @doc "Lista por fecha e ID, filtrando por persona y estado; el coordinador restringe la zona."
  def listar(mensajes, filtros \\ %{}) when is_map(mensajes) and is_map(filtros) do
    estado = valor(filtros, :estado)
    persona_id = valor(filtros, :persona_id) |> normalizar_texto()

    if estado not in [nil, "", :pendiente, :entregado, "pendiente", "entregado"] do
      {:error, :estado_invalido}
    else
      mensajes
      |> Map.values()
      |> Enum.filter(&(is_nil(persona_id) or &1.persona_id == persona_id))
      |> Enum.filter(&(estado in [nil, ""] or to_string(&1.estado) == to_string(estado)))
      |> Enum.sort_by(&{DateTime.to_unix(&1.fecha, :microsecond), &1.id})
      |> then(&{:ok, &1})
    end
  end

  @doc "Entrega un mensaje pendiente; repetir la entrega devuelve :ya_resuelto."
  def marcar_entregado(mensajes, id) when is_map(mensajes) do
    case obtener(mensajes, id) do
      {:ok, %MensajeFamiliar{estado: :pendiente} = mensaje} ->
        {:ok, Map.put(mensajes, id, %{mensaje | estado: :entregado})}

      {:ok, %MensajeFamiliar{estado: :entregado}} ->
        {:error, :ya_resuelto}

      {:ok, _mensaje} ->
        {:error, :transicion_invalida}

      {:error, motivo} ->
        {:error, motivo}
    end
  end

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
  defp normalizar_texto(valor) when is_binary(valor), do: valor |> String.trim() |> empty_to_nil()
  defp normalizar_texto(_valor), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(valor), do: valor
end
