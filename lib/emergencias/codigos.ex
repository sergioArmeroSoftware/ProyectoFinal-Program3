defmodule Emergencias.Codigos do
  @moduledoc "Valida formatos canónicos de identificadores del sistema."

  @formatos %{
    zona: ~r/\AZ-[0-9]{2}\z/,
    sector: ~r/\ASEC-[0-9]{2}\z/,
    punto_atencion: ~r/\APA-[0-9]{2}\z/,
    albergue: ~r/\AA-[0-9]{2}\z/,
    recurso: ~r/\AR-[0-9]{2}\z/
  }

  @doc "Comprueba si un valor respeta el formato asignado al tipo de código."
  def valido?(tipo, valor) when is_binary(valor) do
    case Map.fetch(@formatos, tipo) do
      {:ok, patron} -> Regex.match?(patron, String.trim(valor))
      :error -> false
    end
  end

  def valido?(_tipo, _valor), do: false

  @doc "Devuelve una explicación breve del formato esperado."
  def formato(:zona), do: "Z-01 (Z, guion y dos dígitos)"
  def formato(:sector), do: "SEC-01 (SEC, guion y dos dígitos)"
  def formato(:punto_atencion), do: "PA-01 (PA, guion y dos dígitos)"
  def formato(:albergue), do: "A-01 (A, guion y dos dígitos)"
  def formato(:recurso), do: "R-01 (R, guion y dos dígitos)"
  def formato(_tipo), do: "código no reconocido"
end
