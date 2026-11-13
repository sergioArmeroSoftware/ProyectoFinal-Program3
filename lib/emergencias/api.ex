defmodule Emergencias.API do
  @moduledoc "Fachada para peticiones entre la interfaz y el coordinador."

  @doc "Comprueba que el coordinador configurado responda."
  def ping do
    case call_genserver(:ping, 2_000) do
      :pong -> {:ok, :pong}
      {:error, motivo} -> {:error, motivo}
      respuesta -> {:ok, respuesta}
    end
  end

  @doc "Obtiene el estado compartido (uso interno mientras se construye el contrato)."
  def obtener_estado do
    case call_genserver(:obtener_estado, 2_000) do
      {:ok, estado} -> {:ok, estado}
      {:error, motivo} -> {:error, motivo}
      _respuesta -> {:error, :respuesta_invalida}
    end
  end

  @doc "Solicita alta de cuenta o autenticación de una existente."
  def conectar(attrs), do: call({:conectar, attrs})

  @doc "Solicita cerrar la sesión indicada."
  def desconectar(session_id), do: call({:desconectar, session_id})

  @doc "Envía una mutación de dominio al coordinador."
  def ejecutar(session_id, comando), do: call({:ejecutar, session_id, comando})

  @doc "Envía una consulta de dominio al coordinador."
  def consultar(session_id, consulta), do: call({:consultar, session_id, consulta})

  @doc "Lista códigos y nombres de zonas para el formulario público de registro."
  def zonas_para_registro, do: call(:zonas_publicas)

  defp call(solicitud) do
    case call_genserver(solicitud, 5_000) do
      :ok -> :ok
      {:ok, _resultado} = respuesta -> respuesta
      {:error, _motivo} = error -> error
      respuesta -> {:ok, respuesta}
    end
  end

  defp call_genserver(solicitud, timeout) do
    with {:ok, server} <- server_ref() do
      GenServer.call(server, solicitud, timeout)
    end
  rescue
    _error -> {:error, :coordinador_no_disponible}
  catch
    :exit, _reason -> {:error, :coordinador_no_disponible}
  end

  defp server_ref do
    case Application.get_env(:emergencias, :node_role, :all) do
      :web ->
        case Application.get_env(:emergencias, :core_node) do
          core_node when is_atom(core_node) ->
            if Node.connect(core_node),
              do: {:ok, {Emergencias.EstadoServidor, core_node}},
              else: {:error, :coordinador_no_disponible}

          _configuracion ->
            {:error, :coordinador_no_disponible}
        end

      _role ->
        {:ok, Emergencias.EstadoServidor}
    end
  end
end
