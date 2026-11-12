defmodule Emergencias.RecursosTest do
  use ExUnit.Case, async: true

  alias Emergencias.{Recursos, Zona}

  setup do
    zonas = %{"Z-01" => %Zona{codigo: "Z-01", nombre: "Centro"}}

    attrs = %{
      codigo: "R-01",
      nombre: "Agua potable",
      categoria: "Agua",
      cantidad_disponible: "20",
      unidad: "litros",
      ubicacion: "Centro de acopio",
      zona_codigo: "Z-01"
    }

    %{zonas: zonas, attrs: attrs}
  end

  test "registra con la nomenclatura R-guion-dos dígitos", c do
    assert {:ok, recursos} = Recursos.registrar(%{}, c.zonas, c.attrs)
    assert recursos["R-01"].nombre == "Agua potable"
  end

  test "rechaza códigos que no siguen la nomenclatura acordada", c do
    assert {:error, :codigo_invalido} =
             Recursos.registrar(%{}, c.zonas, %{c.attrs | codigo: "B-01"})
  end
end
