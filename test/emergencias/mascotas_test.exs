defmodule Emergencias.MascotasTest do
  use ExUnit.Case, async: true
  alias Emergencias.{Mascotas, Zona}

  setup do
    attrs = %{
      id: "R1",
      tipo_reporte: :perdida,
      especie: " Perro ",
      nombre: "Luna",
      caracteristicas: "Mancha blanca",
      color: "Negro",
      tamano: "Mediano",
      zona_codigo: "Z-01",
      contacto: "Familia"
    }

    zonas = %{"Z-01" => %Zona{codigo: "Z-01"}}
    {:ok, reportes} = Mascotas.registrar(%{}, zonas, attrs)
    %{attrs: attrs, zonas: zonas, reportes: reportes}
  end

  test "registra pérdidas y hallazgos activos con claves de texto", contexto do
    assert {:ok, perdida} = Mascotas.obtener(contexto.reportes, "R1")
    assert perdida.especie == "perro"
    assert perdida.estado == :activa

    attrs =
      Map.new(contexto.attrs, fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.put("id", "R2")
      |> Map.put("tipo_reporte", "encontrada")
      |> Map.put("estado", :resuelta)

    assert {:ok, reportes} = Mascotas.registrar(contexto.reportes, contexto.zonas, attrs)
    assert reportes["R2"].tipo_reporte == :encontrada
    assert reportes["R2"].estado == :activa
    assert {:error, :no_encontrado} = Mascotas.obtener(reportes, "otra")
  end

  test "rechaza duplicados, zona inexistente y datos inválidos", contexto do
    assert {:error, :id_duplicado} =
             Mascotas.registrar(contexto.reportes, contexto.zonas, contexto.attrs)

    assert {:error, :zona_no_encontrada} = Mascotas.registrar(%{}, %{}, contexto.attrs)

    assert {:error, :tipo_invalido} =
             Mascotas.registrar(%{}, contexto.zonas, %{contexto.attrs | tipo_reporte: "otra"})

    for campo <- [:id, :especie, :caracteristicas, :zona_codigo, :contacto],
        valor <- [nil, " ", 123] do
      assert {:error, :datos_incompletos} =
               Mascotas.registrar(%{}, contexto.zonas, Map.put(contexto.attrs, campo, valor))
    end
  end

  test "lista y combina filtros", contexto do
    assert {:ok, reportes} =
             Mascotas.registrar(contexto.reportes, contexto.zonas, %{
               contexto.attrs
               | id: "R2",
                 tipo_reporte: :encontrada,
                 especie: "Gato"
             })

    assert {:ok, [perdida]} =
             Mascotas.listar(reportes, %{
               "tipo_reporte" => "perdida",
               "especie" => "PÉRRO",
               "zona_codigo" => "Z-01",
               "estado" => "activa"
             })

    assert perdida.id == "R1"
    assert {:ok, []} = Mascotas.listar(reportes, %{zona_codigo: "Z-02"})
    assert {:ok, [_]} = Mascotas.listar(reportes, %{especie: "gato"})
    assert {:error, :tipo_invalido} = Mascotas.listar(reportes, %{tipo_reporte: "otra"})
    assert {:error, :estado_invalido} = Mascotas.listar(reportes, %{estado: "otro"})
  end

  test "respeta transiciones y conserva el mapa original", %{reportes: reportes} do
    assert {:ok, posibles} = Mascotas.cambiar_estado(reportes, "R1", :posible_coincidencia)
    assert reportes["R1"].estado == :activa
    assert {:ok, activos} = Mascotas.cambiar_estado(posibles, "R1", :activa)
    assert {:ok, resueltos} = Mascotas.cambiar_estado(activos, "R1", :resuelta)
    assert {:error, :ya_resuelto} = Mascotas.cambiar_estado(resueltos, "R1", :activa)
    assert {:error, :transicion_invalida} = Mascotas.cambiar_estado(reportes, "R1", :activa)
    assert {:error, :estado_invalido} = Mascotas.cambiar_estado(reportes, "R1", "otro")
    assert {:error, :no_encontrado} = Mascotas.cambiar_estado(reportes, "otro", :resuelta)
  end
end
