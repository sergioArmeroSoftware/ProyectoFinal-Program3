defmodule Emergencias.Sesiones do
  @moduledoc "Funciones puras que administran el ciclo de vida de sesiones."
  alias Emergencias.{Estado, Usuarios}

  @doc "Inicia sesión o registra como ciudadano una cuenta nueva y devuelve un identificador opaco."
  def conectar(%Estado{} = estado, attrs) when is_map(attrs) do
    username = attrs |> valor(:username) |> normalizar_usuario()

    case Map.fetch(estado.usuarios_por_username, username) do
      {:ok, _usuario} -> iniciar_sesion_existente(estado, attrs, username)
      :error -> registrar_y_conectar(estado, attrs)
    end
  end

  @doc "Elimina una sesión activa sin borrar el registro de actividad."
  def desconectar(%Estado{} = estado, session_id) do
    if Map.has_key?(estado.sesiones, session_id) do
      {:ok, %{estado | sesiones: Map.delete(estado.sesiones, session_id)}}
    else
      {:error, :no_encontrado}
    end
  end

  @doc "Obtiene el usuario de una sesión válida en forma pública y sin el hash."
  def usuario_de_sesion(%Estado{} = estado, session_id) do
    with {:ok, username} <- Map.fetch(estado.sesiones, session_id),
         {:ok, usuario} <- Map.fetch(estado.usuarios_por_username, username),
         true <- usuario.activo do
      {:ok, Usuarios.usuario_publico(usuario)}
    else
      _resultado -> {:error, :sesion_invalida}
    end
  end

  @doc "Comprueba si la sesión tiene permiso para ejecutar la operación solicitada."
  def autorizado?(%Estado{} = estado, session_id, operacion) do
    with {:ok, username} <- Map.fetch(estado.sesiones, session_id),
         %{} = usuario <- Map.get(estado.usuarios_por_username, username),
         true <- usuario.activo do
      Usuarios.permitido?(usuario.rol, operacion)
    else
      _resultado -> false
    end
  end

  @doc "Comprueba el permiso y el alcance territorial asociado con la sesión."
  def autorizado_en_zona?(%Estado{} = estado, session_id, operacion, zona_codigo) do
    with {:ok, username} <- Map.fetch(estado.sesiones, session_id),
         %{} = usuario <- Map.get(estado.usuarios_por_username, username),
         true <- usuario.activo,
         true <- Emergencias.Usuarios.permitido?(usuario.rol, operacion) do
      usuario.rol == :administrador or usuario.zona_principal == zona_codigo
    else
      _resultado -> false
    end
  end

  defp iniciar_sesion_existente(estado, attrs, username) do
    case Usuarios.autenticar(estado.usuarios_por_username, username, valor(attrs, :password)) do
      {:ok, usuario_publico} -> crear_sesion(estado, username, usuario_publico)
      error -> error
    end
  end

  defp registrar_y_conectar(estado, attrs) do
    with {:ok, usuarios} <- Usuarios.registrar(estado.usuarios_por_username, attrs),
         username when is_binary(username) <- valor(attrs, :username),
         username = String.trim(username),
         usuario when not is_nil(usuario) <- Map.get(usuarios, username) do
      estado = %{estado | usuarios_por_username: usuarios}
      crear_sesion(estado, username, Usuarios.usuario_publico(usuario))
    else
      nil -> {:error, :datos_incompletos}
      {:error, motivo} -> {:error, motivo}
      _respuesta -> {:error, :datos_incompletos}
    end
  end

  defp crear_sesion(estado, username, usuario_publico) do
    session_id = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    estado = %{estado | sesiones: Map.put(estado.sesiones, session_id, username)}
    {:ok, %{estado: estado, session_id: session_id, usuario: usuario_publico}}
  end

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))

  defp normalizar_usuario(username) when is_binary(username), do: String.trim(username)
  defp normalizar_usuario(_username), do: nil
end
