defmodule Emergencias.EstadoServidor do
  @moduledoc "Proceso OTP que por ahora conserva el estado inicial en memoria."
  use GenServer

  @doc "Inicia el coordinador local con un estado vacío."
  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      %Emergencias.Estado{},
      Keyword.put_new(opts, :name, __MODULE__)
    )
  end

  @impl true
  def init(estado), do: {:ok, estado}

  @impl true
  def handle_call(:ping, _from, estado), do: {:reply, :pong, estado}

  @impl true
  def handle_call(:obtener_estado, _from, estado), do: {:reply, {:ok, estado}, estado}
end
