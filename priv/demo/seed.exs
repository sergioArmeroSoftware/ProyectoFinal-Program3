unless Mix.env() == :dev do
  Mix.raise("Los datos de demostración solo se pueden cargar en MIX_ENV=dev.")
end

cuentas = [
  {"demo.admin", "Administración de demostración", "AdminDemo2026!", :administrador},
  {"laura.coord", "Laura Coordinadora", "LauraDemo2026!", :coordinador},
  {"voluntario.demo", "Voluntario de demostración", "Voluntario2026!", :voluntario},
  {"ciudadano.demo", "Ciudadano de demostración", "Ciudadano2026!", :ciudadano}
]

[{admin_username, admin_nombre, admin_password, _rol} | _resto] = cuentas

System.put_env("EMERGENCIAS_ADMIN_USERNAME", admin_username)
System.put_env("EMERGENCIAS_ADMIN_PASSWORD", admin_password)
System.put_env("EMERGENCIAS_ADMIN_NOMBRE", admin_nombre)
System.put_env("EMERGENCIAS_ADMIN_ZONA", "Z-01")

case Application.ensure_all_started(:emergencias) do
  {:ok, _aplicaciones} -> :ok
  {:error, razon} -> Mix.raise("No se pudo iniciar el coordinador: #{inspect(razon)}")
end

{:ok, %{session_id: admin_session}} =
  Emergencias.API.conectar(%{username: admin_username, password: admin_password})

defmodule Emergencias.DemoSeed do
  def ejecutar!(session_id, comando, ok_extra \\ []) do
    case Emergencias.API.ejecutar(session_id, comando) do
      {:ok, _resultado} -> :ok
      {:error, motivo} ->
        if motivo in ok_extra,
          do: :ok,
          else: Mix.raise("Falló #{inspect(comando)}: #{inspect(motivo)}")
    end
  end
end

Emergencias.DemoSeed.ejecutar!(admin_session, {
  :registrar_zona,
  %{codigo: "Z-01", nombre: "Centro", nivel_afectacion: :critica, personas_estimadas: 120}
}, [:id_duplicado])

Emergencias.DemoSeed.ejecutar!(
  admin_session,
  {:registrar_sector, "Z-01", %{codigo: "SEC-01", nombre: "Sector 3"}},
  [:id_duplicado]
)

Emergencias.DemoSeed.ejecutar!(
  admin_session,
  {:registrar_punto_atencion, "Z-01", "SEC-01",
   %{codigo: "PA-01", nombre: "Puesto de salud", personas_estimadas: 30, estado: :activo}},
  [:id_duplicado]
)

Enum.each(cuentas, fn {username, nombre, password, rol} ->
  if username != admin_username do
    Emergencias.DemoSeed.ejecutar!(admin_session, {
      :registrar_usuario,
      %{
        username: username,
        nombre_completo: nombre,
        password: password,
        zona_principal: "Z-01"
      }
    }, [:id_duplicado])

    Emergencias.DemoSeed.ejecutar!(admin_session, {:asignar_rol, username, rol})
  end
end)

:ok = Emergencias.API.desconectar(admin_session)

IO.puts("Datos demo listos en data/estado.json. Zona: Z-01 · Centro; sector SEC-01; punto PA-01.")
IO.puts("Cuentas y contraseñas: consulta la sección 'Datos de demostración' del README.")
