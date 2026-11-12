defmodule Emergencias.CoincidenciasMascotasTest do
  use ExUnit.Case, async: true
  alias Emergencias.{CoincidenciasMascotas, ReporteMascota}

  setup do
    perdida = %ReporteMascota{
      id: "P",
      tipo_reporte: :perdida,
      especie: "perro",
      color: "negro",
      tamano: "mediano",
      zona_codigo: "Z-01",
      nombre: "Luna",
      caracteristicas: "mancha blanca"
    }

    encontrada = %{perdida | id: "E", tipo_reporte: :encontrada}

    %{
      perdida: perdida,
      encontrada: encontrada,
      reportes: %{"P" => perdida, "E" => encontrada},
      contexto: %{id: "C1", fecha: ~U[2026-01-01 00:00:00Z], usuario_id: "coord"}
    }
  end

  test "puntaje máximo y normalización con desglose exacto", c do
    encontrada = %{
      c.encontrada
      | especie: " PÉRRO ",
        color: " NÉGRO ",
        tamano: " MÉDIANO ",
        zona_codigo: " Z-01 ",
        nombre: " LÚNA ",
        caracteristicas: "BLÁNCA,  con mancha mancha"
    }

    assert {:ok, %{puntaje: 100.0, desglose: desglose}} =
             CoincidenciasMascotas.calcular_similitud(c.perdida, encontrada)

    assert desglose == %{
             especie: 30,
             color: 20,
             tamano: 15,
             caracteristicas: 20.0,
             zona_codigo: 10,
             nombre: 5
           }

    assert {:ok, %{puntaje: 100.0}} =
             CoincidenciasMascotas.calcular_similitud(c.perdida, encontrada)
  end

  test "Jaccard usa palabras distintas y no redistribuye vacíos", c do
    encontrada = %{c.encontrada | caracteristicas: "mancha negra"}

    assert {:ok, %{puntaje: 86.67, desglose: %{caracteristicas: 6.67}}} =
             CoincidenciasMascotas.calcular_similitud(c.perdida, encontrada)

    perdida = %{
      c.perdida
      | color: nil,
        tamano: "",
        nombre: " ",
        zona_codigo: nil,
        caracteristicas: "de la y"
    }

    encontrada = %{
      c.encontrada
      | color: "",
        tamano: nil,
        nombre: nil,
        zona_codigo: "",
        caracteristicas: "con el"
    }

    assert {:ok, %{puntaje: 30.0, desglose: desglose}} =
             CoincidenciasMascotas.calcular_similitud(perdida, encontrada)

    assert desglose.caracteristicas == 0
    assert desglose.nombre == 0
  end

  test "rechaza tipos y especies incompatibles y reportes resueltos", c do
    assert {:error, :tipo_invalido} =
             CoincidenciasMascotas.calcular_similitud(c.perdida, c.perdida)

    assert {:error, :tipo_invalido} =
             CoincidenciasMascotas.calcular_similitud(c.encontrada, c.perdida)

    assert {:error, :tipo_invalido} =
             CoincidenciasMascotas.calcular_similitud(c.perdida, %{c.encontrada | especie: "gato"})

    assert {:error, :tipo_invalido} =
             CoincidenciasMascotas.calcular_similitud(%{c.perdida | especie: ""}, %{
               c.encontrada
               | especie: ""
             })

    assert {:error, :ya_resuelto} =
             CoincidenciasMascotas.calcular_similitud(c.perdida, %{
               c.encontrada
               | estado: :resuelta
             })
  end

  test "ordena con desempate estable, busca en ambos sentidos y excluye resueltos", c do
    reportes =
      c.reportes
      |> Map.put("A", %{c.encontrada | id: "A"})
      |> Map.put("B", %{c.encontrada | id: "B", color: "blanco"})
      |> Map.put("X", %{c.encontrada | id: "X", estado: :resuelta})

    assert {:ok, resultados} = CoincidenciasMascotas.buscar(reportes, "P")
    assert Enum.map(resultados, & &1.reporte.id) == ["A", "E", "B"]
    assert reportes["P"].estado == :activa
    assert {:ok, [resultado]} = CoincidenciasMascotas.buscar(reportes, "E")
    assert resultado.reporte.id == "P"
    assert {:error, :ya_resuelto} = CoincidenciasMascotas.buscar(reportes, "X")
    assert {:error, :no_encontrado} = CoincidenciasMascotas.buscar(reportes, "otro")
  end

  test "propone una vez sin resolver y confirma conservando el ID", c do
    assert {:ok, propuesta} =
             CoincidenciasMascotas.proponer(c.reportes, %{}, "P", "E", c.contexto)

    assert propuesta.coincidencia.estado == :propuesta
    assert propuesta.coincidencia.confirmada_por == nil
    assert propuesta.reportes["P"].estado == :posible_coincidencia
    assert propuesta.reportes["E"].estado == :posible_coincidencia
    assert c.reportes["P"].estado == :activa

    assert {:error, :id_duplicado} =
             CoincidenciasMascotas.proponer(
               propuesta.reportes,
               propuesta.coincidencias,
               "P",
               "E",
               %{c.contexto | id: "C2"}
             )

    contexto = %{c.contexto | id: "nuevo", fecha: ~U[2026-01-02 00:00:00Z]}

    assert {:ok, confirmada} =
             CoincidenciasMascotas.confirmar(
               propuesta.reportes,
               propuesta.coincidencias,
               "P",
               "E",
               contexto
             )

    assert confirmada.coincidencia.id == "C1"
    assert confirmada.coincidencia.fecha == contexto.fecha
    assert confirmada.coincidencia.confirmada_por == "coord"
    assert confirmada.reportes["P"].estado == :resuelta
    assert confirmada.reportes["E"].estado == :resuelta

    assert {:error, :ya_resuelto} =
             CoincidenciasMascotas.confirmar(
               confirmada.reportes,
               confirmada.coincidencias,
               "P",
               "E",
               contexto
             )
  end

  test "valida contexto, IDs, referencias y confirmaciones contradictorias", c do
    assert {:error, :datos_incompletos} =
             CoincidenciasMascotas.proponer(c.reportes, %{}, "P", "E", %{})

    assert {:error, :datos_incompletos} =
             CoincidenciasMascotas.confirmar(
               c.reportes,
               %{},
               "P",
               "E",
               Map.delete(c.contexto, :usuario_id)
             )

    assert {:error, :no_encontrado} =
             CoincidenciasMascotas.confirmar(c.reportes, %{}, "otro", "E", c.contexto)

    assert {:ok, confirmada} =
             CoincidenciasMascotas.confirmar(c.reportes, %{}, "P", "E", c.contexto)

    # Incluso ante reportes inconsistentes reabiertos, una confirmación previa bloquea otra pareja.
    reportes = Map.put(c.reportes, "E2", %{c.encontrada | id: "E2"})

    assert {:error, :ya_resuelto} =
             CoincidenciasMascotas.confirmar(reportes, confirmada.coincidencias, "P", "E2", %{
               c.contexto
               | id: "C2"
             })

    assert {:error, :id_duplicado} =
             CoincidenciasMascotas.proponer(
               reportes,
               confirmada.coincidencias,
               "P",
               "E2",
               c.contexto
             )
  end

  test "consulta coincidencias por estado y reporte", c do
    assert {:ok, resultado} =
             CoincidenciasMascotas.proponer(c.reportes, %{}, "P", "E", c.contexto)

    assert {:ok, [_]} =
             CoincidenciasMascotas.listar(resultado.coincidencias, %{
               "estado" => "propuesta",
               "reporte_id" => "E"
             })

    assert {:ok, []} =
             CoincidenciasMascotas.listar(resultado.coincidencias, %{estado: :confirmada})

    assert {:ok, []} =
             CoincidenciasMascotas.listar(resultado.coincidencias, %{reporte_id: "otro"})

    assert {:error, :estado_invalido} =
             CoincidenciasMascotas.listar(resultado.coincidencias, %{estado: "otro"})
  end
end
