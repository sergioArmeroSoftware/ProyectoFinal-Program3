defmodule Emergencias.API do
  @moduledoc "Fachada para peticiones entre la interfaz y el coordinador."

  @doc "Comprueba que el coordinador configurado responda."
  def ping do
    server_ref()
    |> GenServer.call(:ping, 2_000)
    |> then(&{:ok, &1})
  rescue
    _error -> {:error, :coordinador_no_disponible}
  catch
    :exit, _reason -> {:error, :coordinador_no_disponible}
  end

  @doc "Obtiene el estado compartido (uso interno mientras se construye el contrato)."
  def obtener_estado do
    case GenServer.call(server_ref(), :obtener_estado, 2_000) do
      {:ok, estado} -> {:ok, estado}
      _respuesta -> {:error, :respuesta_invalida}
    end
  catch
    :exit, _reason -> {:error, :coordinador_no_disponible}
  end

  @doc "Solicita alta de cuenta o autenticación de una existente."
  def conectar(attrs), do: call({:conectar, attrs})

  @doc "Solicita cerrar la sesión indicada."
  def desconectar(session_id), do: call({:desconectar, session_id})

  @doc "Envía una mutación de dominio al coordinador."
  def ejecutar(session_id, comando), do: call({:ejecutar, session_id, comando})

  @doc "Envía una consulta de dominio al coordinador."
  def consultar(session_id, consulta), do: call({:consultar, session_id, consulta})

  defp call(solicitud) do
    case GenServer.call(server_ref(), solicitud, 5_000) do
      :ok -> :ok
      {:ok, _resultado} = respuesta -> respuesta
      {:error, _motivo} = error -> error
      respuesta -> {:ok, respuesta}
    end
  rescue
    _error -> {:error, :coordinador_no_disponible}
  catch
    :exit, _reason -> {:error, :coordinador_no_disponible}
  end

  defp server_ref do
    case Application.get_env(:emergencias, :node_role, :all) do
      :web -> {Emergencias.EstadoServidor, Application.fetch_env!(:emergencias, :core_node)}
      _role -> Emergencias.EstadoServidor
    end
  end
end
