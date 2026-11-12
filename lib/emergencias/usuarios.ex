defmodule Emergencias.Usuarios do
  @moduledoc "Reglas de alta, permisos y administración básica de usuarios."
  alias Emergencias.{Codigos, Credenciales, RegistroActividad, Usuario}

  @roles [:ciudadano, :voluntario, :coordinador, :administrador]

  @permisos %{
    ciudadano: [:reportar_en_zona, :consultar_zona],
    voluntario: [
      :reportar_en_zona,
      :consultar_zona,
      :cambiar_estado_persona,
      :atender_mensaje,
      :gestionar_albergue
    ],
    coordinador: [
      :reportar_en_zona,
      :consultar_zona,
      :cambiar_estado_persona,
      :atender_mensaje,
      :gestionar_albergue,
      :asignar_recursos,
      :transferir_recursos,
      :proponer_coincidencia
    ],
    administrador: [
      :reportar_en_zona,
      :consultar_zona,
      :reportar_global,
      :consultar_global,
      :cambiar_estado_persona,
      :atender_mensaje,
      :gestionar_albergue,
      :asignar_recursos,
      :transferir_recursos,
      :confirmar_coincidencia,
      :crear_zonas,
      :gestionar_usuarios
    ]
  }

  @doc "Crea una cuenta nueva como ciudadano y rechaza nombres repetidos."
  def registrar(usuarios, attrs) when is_map(usuarios) and is_map(attrs) do
    with {:ok, usuario} <- construir_usuario(attrs),
         false <- Map.has_key?(usuarios, usuario.username) do
      {:ok, Map.put(usuarios, usuario.username, usuario)}
    else
      true -> {:error, :id_duplicado}
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Crea la cuenta administradora inicial únicamente cuando aún no hay usuarios."
  def provisionar_administrador(usuarios, attrs) when map_size(usuarios) == 0 do
    attrs = Map.put(attrs, :username, valor(attrs, :username))

    with {:ok, usuarios} <- registrar(usuarios, attrs),
         username when is_binary(username) <- attrs |> valor(:username) |> normalizar_texto(),
         {:ok, usuario} <- Map.fetch(usuarios, username) do
      {:ok, Map.put(usuarios, username, %{usuario | rol: :administrador})}
    else
      {:error, razon} -> {:error, razon}
      _respuesta -> {:error, :datos_incompletos}
    end
  end

  def provisionar_administrador(_usuarios, _attrs), do: {:error, :usuarios_ya_registrados}

  defp asignar_rol(usuarios, username, rol) when rol in @roles do
    case Map.fetch(usuarios, username) do
      {:ok, usuario} -> {:ok, Map.put(usuarios, username, %{usuario | rol: rol})}
      :error -> {:error, :no_encontrado}
    end
  end

  defp asignar_rol(_usuarios, _username, _rol), do: {:error, :rol_invalido}

  @doc "Cambia el rol solo si la persona solicitante es administradora y el rol es válido."
  def asignar_rol_autorizado(usuarios, solicitante, username, rol) do
    case Map.get(usuarios, solicitante) do
      %Usuario{rol: :administrador, activo: true} -> asignar_rol(usuarios, username, rol)
      %Usuario{} -> {:error, :no_autorizado}
      nil -> {:error, :no_autorizado}
    end
  end

  @doc "Autentica una cuenta activa y devuelve el usuario sin su hash."
  def autenticar(usuarios, username, password) do
    case Map.get(usuarios, username) do
      %Usuario{activo: true, password_hash: hash} = usuario ->
        if Credenciales.verificar(password, hash),
          do: {:ok, usuario_publico(usuario)},
          else: {:error, :credenciales_invalidas}

      _usuario ->
        {:error, :credenciales_invalidas}
    end
  end

  @doc "Desactiva una cuenta sin eliminar sus referencias históricas."
  def desactivar(usuarios, username) do
    case Map.fetch(usuarios, username) do
      {:ok, usuario} -> {:ok, Map.put(usuarios, username, %{usuario | activo: false})}
      :error -> {:error, :no_encontrado}
    end
  end

  @doc "Construye la representación de cuenta que se puede entregar a la interfaz."
  def usuario_publico(%Usuario{} = usuario),
    do: usuario |> Map.from_struct() |> Map.delete(:password_hash)

  @doc "Agrega una entrada al registro de auditoría más reciente."
  def registrar_actividad(actividad, username, accion, entidad_id, fecha) do
    registro = %RegistroActividad{
      id: :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false),
      username: username,
      accion: accion,
      entidad_id: entidad_id,
      fecha: fecha
    }

    [registro | actividad]
  end

  @doc "Responde si un rol puede ejecutar una operación de la matriz aprobada."
  def permitido?(rol, operacion), do: operacion in Map.get(@permisos, rol, [])

  @doc "Devuelve los roles reconocidos por la aplicación."
  def roles, do: @roles

  defp construir_usuario(attrs) do
    username = attrs |> valor(:username) |> normalizar_texto()
    nombre = attrs |> valor(:nombre_completo) |> normalizar_texto()
    password = valor(attrs, :password)
    zona = attrs |> valor(:zona_principal) |> normalizar_texto()

    cond do
      is_nil(username) or is_nil(nombre) or is_nil(zona) or not is_binary(password) ->
        {:error, :datos_incompletos}

      not Codigos.valido?(:zona, zona) ->
        {:error, :codigo_invalido}

      true ->
        with {:ok, password_hash} <- Credenciales.generar_hash(password) do
          {:ok,
           %Usuario{
             username: username,
             nombre_completo: nombre,
             password_hash: password_hash,
             zona_principal: zona
           }}
        end
    end
  end

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
  defp normalizar_texto(valor) when is_binary(valor), do: valor |> String.trim() |> empty_to_nil()
  defp normalizar_texto(_valor), do: nil
  defp empty_to_nil(""), do: nil
  defp empty_to_nil(valor), do: valor
end
