defmodule EmergenciasWeb.DemoEstado do
  @moduledoc "Sesiones y cuentas transitorias para el flujo visual de demostración."
  use GenServer

  alias Emergencias.{Estado, Sesiones, Usuarios}

  @doc "Inicia el almacén de demostración en memoria."
  def start_link(opts \\ []),
    do: GenServer.start_link(__MODULE__, :ok, Keyword.put_new(opts, :name, __MODULE__))

  @doc "Registra una cuenta ciudadana e inicia su sesión."
  def registrar(attrs), do: GenServer.call(__MODULE__, {:registrar, attrs})

  @doc "Inicia sesión en una cuenta existente."
  def ingresar(attrs), do: GenServer.call(__MODULE__, {:ingresar, attrs})

  @doc "Cierra una sesión activa."
  def salir(session_id), do: GenServer.call(__MODULE__, {:salir, session_id})

  @doc "Obtiene datos públicos del usuario asociado a la sesión."
  def usuario(session_id), do: GenServer.call(__MODULE__, {:usuario, session_id})

  @doc "Lista cuentas sin incluir sus hashes de contraseña."
  def listar_usuarios, do: GenServer.call(__MODULE__, :listar_usuarios)

  @doc "Crea una cuenta ciudadana si la sesión actual es administradora."
  def crear_usuario(session_id, attrs),
    do: GenServer.call(__MODULE__, {:crear_usuario, session_id, attrs})

  @doc "Asigna un rol si la sesión actual tiene permiso de administración."
  def asignar_rol(session_id, username, rol),
    do: GenServer.call(__MODULE__, {:asignar_rol, session_id, username, rol})

  @doc "Desactiva una cuenta si la sesión actual tiene permiso de administración."
  def desactivar_usuario(session_id, username),
    do: GenServer.call(__MODULE__, {:desactivar_usuario, session_id, username})

  @impl true
  def init(:ok), do: {:ok, estado_inicial()}

  @impl true
  def handle_call({:registrar, attrs}, _from, estado) do
    username = valor(attrs, :username) |> normalizar_texto()

    if Map.has_key?(estado.usuarios_por_username, username) do
      {:reply, {:error, :id_duplicado}, estado}
    else
      conectar_y_actualizar(estado, attrs)
    end
  end

  def handle_call({:ingresar, attrs}, _from, estado) do
    username = valor(attrs, :username) |> normalizar_texto()

    if Map.has_key?(estado.usuarios_por_username, username) do
      conectar_y_actualizar(estado, attrs)
    else
      {:reply, {:error, :credenciales_invalidas}, estado}
    end
  end

  def handle_call({:salir, session_id}, _from, estado) do
    case Sesiones.desconectar(estado, session_id) do
      {:ok, estado_actualizado} -> {:reply, :ok, estado_actualizado}
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:usuario, session_id}, _from, estado),
    do: {:reply, Sesiones.usuario_de_sesion(estado, session_id), estado}

  def handle_call(:listar_usuarios, _from, estado) do
    usuarios =
      estado.usuarios_por_username
      |> Map.values()
      |> Enum.map(&Usuarios.usuario_publico/1)
      |> Enum.sort_by(& &1.username)

    {:reply, {:ok, usuarios}, estado}
  end

  def handle_call({:crear_usuario, session_id, attrs}, _from, estado) do
    with {:ok, username_admin} <- username_autorizado(estado, session_id, :gestionar_usuarios),
         :ok <- validar_zona_existente(estado, attrs),
         {:ok, usuarios} <- Usuarios.registrar(estado.usuarios_por_username, attrs) do
      estado = %{estado | usuarios_por_username: usuarios}
      usuario = Map.fetch!(usuarios, normalizar_texto(valor(attrs, :username)))

      actividad =
        Usuarios.registrar_actividad(
          estado.actividad,
          username_admin,
          :crear_usuario,
          usuario.username,
          DateTime.utc_now()
        )

      estado = %{estado | actividad: actividad}
      {:reply, {:ok, Usuarios.usuario_publico(usuario)}, estado}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, estado}
    end
  end

  def handle_call({:asignar_rol, session_id, target, rol}, _from, estado) do
    with {:ok, actor} <- username_autorizado(estado, session_id, :gestionar_usuarios),
         {:ok, usuarios} <-
           Usuarios.asignar_rol_autorizado(estado.usuarios_por_username, actor, target, rol) do
      {:reply, :ok, %{estado | usuarios_por_username: usuarios}}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, estado}
    end
  end

  def handle_call({:desactivar_usuario, session_id, target}, _from, estado) do
    with {:ok, _actor} <- username_autorizado(estado, session_id, :gestionar_usuarios),
         {:ok, usuarios} <- Usuarios.desactivar(estado.usuarios_por_username, target) do
      {:reply, :ok, %{estado | usuarios_por_username: usuarios}}
    else
      {:error, motivo} -> {:reply, {:error, motivo}, estado}
    end
  end

  defp conectar_y_actualizar(estado, attrs) do
    case Sesiones.conectar(estado, attrs) do
      {:ok, %{estado: estado_actualizado, session_id: session_id, usuario: usuario}} ->
        {:reply, {:ok, %{session_id: session_id, usuario: usuario}}, estado_actualizado}

      {:error, motivo} ->
        {:reply, {:error, motivo}, estado}
    end
  end

  defp username_autorizado(estado, session_id, operacion) do
    with {:ok, username} <- Map.fetch(estado.sesiones, session_id),
         true <- Sesiones.autorizado?(estado, session_id, operacion) do
      {:ok, username}
    else
      _resultado -> {:error, :no_autorizado}
    end
  end

  defp validar_zona_existente(estado, attrs) do
    zona_codigo = attrs |> valor(:zona_principal) |> normalizar_texto()

    if Map.has_key?(estado.zonas_por_codigo, zona_codigo),
      do: :ok,
      else: {:error, :zona_no_encontrada}
  end

  defp estado_inicial do
    estado = %Estado{zonas_por_codigo: EmergenciasWeb.Demo.zonas_demo()}

    with true <- Application.get_env(:emergencias, :demo_admin_enabled, false),
         password when is_binary(password) <- System.get_env("EMERGENCIAS_DEMO_ADMIN_PASSWORD"),
         {:ok, usuarios} <-
           Usuarios.provisionar_administrador(estado.usuarios_por_username, %{
             username: "admin.demo",
             nombre_completo: "Administrador de demostración",
             zona_principal: "Z-01",
             password: password
           }) do
      %{estado | usuarios_por_username: usuarios}
    else
      _resultado -> estado
    end
  end

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
  defp normalizar_texto(valor) when is_binary(valor), do: String.trim(valor)
  defp normalizar_texto(_valor), do: nil
end
