defmodule Emergencias.MensajesTest do
  use ExUnit.Case, async: true
  alias Emergencias.{MensajeFamiliar, Mensajes, PersonaAfectada}

  setup do
    attrs = %{
      id: "M1",
      fecha: ~U[2026-01-01 00:00:00Z],
      remitente: " Ana ",
      destinatario: " Luis ",
      contenido: " Estoy bien "
    }

    personas = %{"P1" => %PersonaAfectada{id: "P1"}, "P2" => %PersonaAfectada{id: "P2"}}
    {:ok, mensajes} = Mensajes.crear(%{}, personas, "P1", attrs)
    %{attrs: attrs, personas: personas, mensajes: mensajes}
  end

  test "crea un mensaje pendiente y normaliza textos", %{mensajes: mensajes} do
    assert {:ok, mensaje} = Mensajes.obtener(mensajes, "M1")

    assert %MensajeFamiliar{
             persona_id: "P1",
             estado: :pendiente,
             remitente: "Ana",
             destinatario: "Luis",
             contenido: "Estoy bien"
           } = mensaje

    assert {:error, :no_encontrado} = Mensajes.obtener(mensajes, "otro")
  end

  test "valida campos, persona e identificadores", contexto do
    for campo <- [:id, :remitente, :destinatario, :contenido], valor <- [nil, " ", 123] do
      assert {:error, :datos_incompletos} =
               Mensajes.crear(%{}, contexto.personas, "P1", Map.put(contexto.attrs, campo, valor))
    end

    assert {:error, :datos_incompletos} =
             Mensajes.crear(%{}, contexto.personas, "P1", %{contexto.attrs | fecha: nil})

    assert {:error, :no_encontrado} =
             Mensajes.crear(%{}, contexto.personas, "otra", contexto.attrs)

    assert {:error, :id_duplicado} =
             Mensajes.crear(contexto.mensajes, contexto.personas, "P1", contexto.attrs)

    assert {:ok, mensajes} =
             Mensajes.crear(
               %{},
               contexto.personas,
               "P1",
               Map.put(contexto.attrs, :estado, :entregado)
             )

    assert mensajes["M1"].estado == :pendiente
  end

  test "filtra por persona y estado, ordenando por fecha e ID", contexto do
    attrs = contexto.attrs |> Map.put(:id, "M2") |> Map.put(:fecha, ~U[2025-01-01 00:00:00Z])
    assert {:ok, mensajes} = Mensajes.crear(contexto.mensajes, contexto.personas, "P2", attrs)
    assert {:ok, mensajes} = Mensajes.marcar_entregado(mensajes, "M2")
    assert {:ok, [primero, segundo]} = Mensajes.listar(mensajes)
    assert {primero.id, segundo.id} == {"M2", "M1"}

    assert {:ok, [^segundo]} =
             Mensajes.listar(mensajes, %{"persona_id" => "P1", "estado" => "pendiente"})

    assert {:ok, [^primero]} = Mensajes.listar(mensajes, %{estado: :entregado})
    assert {:ok, []} = Mensajes.listar(mensajes, %{persona_id: "otra"})
    assert {:error, :estado_invalido} = Mensajes.listar(mensajes, %{estado: "otro"})
  end

  test "entrega una sola vez sin mutar el mapa original", %{mensajes: mensajes} do
    assert {:ok, entregados} = Mensajes.marcar_entregado(mensajes, "M1")
    assert mensajes["M1"].estado == :pendiente
    assert entregados["M1"].estado == :entregado
    assert {:error, :ya_resuelto} = Mensajes.marcar_entregado(entregados, "M1")
    assert {:error, :no_encontrado} = Mensajes.marcar_entregado(mensajes, "otro")
    invalidos = Map.put(mensajes, "M1", %{mensajes["M1"] | estado: :invalido})
    assert {:error, :transicion_invalida} = Mensajes.marcar_entregado(invalidos, "M1")
  end
end
