defmodule EmergenciasWeb.Demo do
  @moduledoc "Adaptador temporal de interfaz; toda la información se recibe y devuelve por llamada."

  alias Emergencias.{Albergues, Codigos, Estado, Sesiones, Usuarios, Zonas}

  def conectar(%Estado{} = estado, attrs), do: Sesiones.conectar(estado, attrs)
  def desconectar(%Estado{} = estado, session_id), do: Sesiones.desconectar(estado, session_id)

  def roles, do: Usuarios.roles()

  def registrar_usuario(usuarios, attrs) do
    zona_codigo = attrs |> valor(:zona_principal) |> normalizar_codigo()

    cond do
      is_nil(zona_codigo) or zona_codigo == "" -> {:error, :zona_requerida}
      not Codigos.valido?(:zona, zona_codigo) -> {:error, :codigo_invalido}
      Map.has_key?(zonas_demo(), zona_codigo) -> Usuarios.registrar(usuarios, attrs)
      true -> {:error, :zona_no_encontrada}
    end
  end

  def valido_codigo?(tipo, valor), do: Codigos.valido?(tipo, valor)
  def formato_codigo(tipo), do: Codigos.formato(tipo)

  def zonas_demo do
    %{
      "Z-01" => %{codigo: "Z-01", nombre: "Centro"},
      "Z-02" => %{codigo: "Z-02", nombre: "Norte"}
    }
  end

  def asignar_rol(usuarios, actor, username, rol),
    do: Usuarios.asignar_rol_autorizado(usuarios, actor, username, rol)

  def desactivar_usuario(usuarios, username), do: Usuarios.desactivar(usuarios, username)
  def listar_usuarios(usuarios), do: usuarios |> Map.values() |> Enum.sort_by(& &1.username)

  def crear_zona(zonas, zona), do: Zonas.registrar(zonas, zona)

  def agregar_sector(zonas, zona_codigo, sector),
    do: Zonas.agregar_sector(zonas, zona_codigo, sector)

  def agregar_punto(zonas, zona_codigo, sector_codigo, punto),
    do: Zonas.agregar_punto(zonas, zona_codigo, sector_codigo, punto)

  def cambiar_estado_punto(zonas, zona_codigo, sector_codigo, punto_codigo, estado),
    do: Zonas.cambiar_estado_punto(zonas, zona_codigo, sector_codigo, punto_codigo, estado)

  def buscar_punto(sectores, codigo), do: Zonas.buscar_punto(sectores, codigo)
  def contar_sectores(zona), do: Zonas.contar_sectores(zona)
  def contar_puntos(zona), do: Zonas.contar_puntos(zona)
  def contar_puntos_por_estado(zona, estado), do: Zonas.contar_puntos_por_estado(zona, estado)
  def listar_zonas(zonas), do: zonas |> Map.values() |> Enum.sort_by(& &1.codigo)

  def registrar_albergue(albergues, zonas, attrs),
    do: Albergues.registrar(albergues, zonas, attrs)

  def registrar_ingreso(albergues, estancias, personas, codigo, persona_id, id, fecha),
    do: Albergues.registrar_ingreso(albergues, estancias, personas, codigo, persona_id, id, fecha)

  def registrar_salida(estancias, codigo, persona_id, fecha),
    do: Albergues.registrar_salida(estancias, codigo, persona_id, fecha)

  def disponibilidad(albergues, estancias, codigo),
    do: Albergues.disponibilidad(albergues, estancias, codigo)

  def estancias_activas(estancias, codigo), do: Albergues.estancias_activas(estancias, codigo)
  def listar_albergues(albergues), do: Albergues.listar(albergues)

  defp valor(attrs, clave), do: Map.get(attrs, clave, Map.get(attrs, Atom.to_string(clave)))
  defp normalizar_codigo(codigo) when is_binary(codigo), do: String.trim(codigo)
  defp normalizar_codigo(_codigo), do: nil
end
