defmodule Emergencias.MensajeFamiliar do
  @moduledoc "Mensaje familiar asociado a una persona afectada."
  defstruct id: nil,
            persona_id: nil,
            fecha: nil,
            remitente: nil,
            destinatario: nil,
            contenido: nil,
            estado: :pendiente
end
