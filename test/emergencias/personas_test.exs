defmodule Emergencias.PersonasTest do
  use ExUnit.Case, async: true
  alias Emergencias.{Personas, Zona}

  setup do
    attrs = %{id: "P1", nombre: "Ana", documento_referencia: "123", edad: 20, zona_codigo: "Z-01"}
    {:ok, personas} = Personas.registrar(%{}, %{"Z-01" => %Zona{codigo: "Z-01"}}, attrs)
    %{attrs: attrs, personas: personas, zonas: %{"Z-01" => %Zona{codigo: "Z-01"}}}
  end

  test "registra, busca y filtra personas", %{personas: personas} do
    assert {:ok, persona} = Personas.obtener(personas, "P1")
    assert persona.estado == :reportada
    assert {:ok, [^persona]} = Personas.buscar_por_documento(personas, " 123 ")
    assert {:ok, []} = Personas.buscar_por_documento(personas, "otro")
    assert {:error, :datos_incompletos} = Personas.buscar_por_documento(personas, " ")

    assert {:ok, [^persona]} =
             Personas.listar(personas, %{"zona_codigo" => "Z-01", "estado" => "reportada"})

    assert {:ok, []} = Personas.listar(personas, %{zona_codigo: "Z-02"})
    assert {:error, :estado_invalido} = Personas.listar(personas, %{estado: "inexistente"})
    assert {:error, :no_encontrado} = Personas.obtener(personas, "otro")
  end

  test "rechaza duplicados y datos inválidos", %{personas: personas, zonas: zonas, attrs: attrs} do
    assert {:error, :id_duplicado} = Personas.registrar(personas, zonas, attrs)
    assert {:error, :datos_incompletos} = Personas.registrar(%{}, zonas, %{attrs | nombre: " "})
    assert {:error, :zona_no_encontrada} = Personas.registrar(%{}, %{}, attrs)

    for edad <- [-1, "abc", nil] do
      assert {:error, :cantidad_invalida} = Personas.registrar(%{}, zonas, %{attrs | edad: edad})
    end

    assert {:error, :estado_invalido} =
             Personas.registrar(%{}, zonas, Map.put(attrs, :estado, "otro"))
  end

  test "actualiza persona e historial sin modificar los originales", %{personas: personas} do
    contexto = %{id: "C1", usuario_id: "operador", fecha: ~U[2026-01-01 00:00:00Z]}
    assert {:ok, resultado} = Personas.cambiar_estado(personas, [], "P1", "localizada", contexto)
    assert personas["P1"].estado == :reportada
    assert resultado.personas["P1"].estado == :localizada
    assert {:ok, [cambio]} = Personas.historial(resultado.historial, "P1")
    assert cambio.estado_anterior == :reportada
    assert cambio.estado_nuevo == :localizada
    assert cambio.usuario_id == "operador"

    assert {:error, :id_duplicado} =
             Personas.cambiar_estado(
               resultado.personas,
               resultado.historial,
               "P1",
               :trasladada,
               contexto
             )

    assert {:error, :transicion_invalida} =
             Personas.cambiar_estado(personas, [], "P1", :reportada, contexto)

    assert {:error, :estado_invalido} =
             Personas.cambiar_estado(personas, [], "P1", "otro", contexto)

    assert {:error, :datos_incompletos} =
             Personas.cambiar_estado(personas, [], "P1", :localizada, %{})

    assert {:ok, final} = Personas.cambiar_estado(personas, [], "P1", :reunificada, contexto)

    assert {:error, :ya_resuelto} =
             Personas.cambiar_estado(final.personas, final.historial, "P1", :localizada, contexto)
  end

  test "admite los estados acordados y ordena el historial por fecha", %{personas: personas} do
    resultado =
      [:sin_informacion, :localizada, :trasladada, :en_albergue, :reunificada]
      |> Enum.with_index(1)
      |> Enum.reduce(%{personas: personas, historial: []}, fn {estado, indice}, acumulado ->
        contexto = %{
          id: "C#{indice}",
          usuario_id: "operador",
          fecha: DateTime.add(~U[2026-01-01 00:00:00Z], indice)
        }

        assert {:ok, siguiente} =
                 Personas.cambiar_estado(
                   acumulado.personas,
                   acumulado.historial,
                   "P1",
                   estado,
                   contexto
                 )

        siguiente
      end)

    assert {:ok, cambios} = Personas.historial(Enum.reverse(resultado.historial), "P1")

    assert Enum.map(cambios, & &1.estado_nuevo) ==
             [:sin_informacion, :localizada, :trasladada, :en_albergue, :reunificada]

    assert {:ok, []} = Personas.historial(cambios, "otra")
  end
end
