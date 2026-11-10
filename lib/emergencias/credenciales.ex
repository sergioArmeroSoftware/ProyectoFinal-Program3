defmodule Emergencias.Credenciales do
  @moduledoc "Generación y verificación de hashes de contraseñas con PBKDF2-HMAC-SHA256."

  @iteraciones 600_000
  @longitud_hash 32
  @longitud_salt 16

  @doc "Deriva un hash con salt aleatorio; nunca devuelve ni conserva la contraseña original."
  def generar_hash(password) when is_binary(password) and byte_size(password) >= 8 do
    salt = :crypto.strong_rand_bytes(@longitud_salt)
    derived_key = derive(password, salt, @iteraciones)

    [
      "pbkdf2_sha256",
      Integer.to_string(@iteraciones),
      Base.encode64(salt),
      Base.encode64(derived_key)
    ]
    |> Enum.join("$")
    |> then(&{:ok, &1})
  end

  def generar_hash(_password), do: {:error, :contrasena_invalida}

  @doc "Compara una contraseña con su hash usando comparación de tiempo constante."
  def verificar(password, encoded_hash) when is_binary(password) and is_binary(encoded_hash) do
    with ["pbkdf2_sha256", iteraciones, salt_encoded, hash_encoded] <-
           String.split(encoded_hash, "$"),
         {iteraciones, ""} <- Integer.parse(iteraciones),
         true <- iteraciones >= 100_000 and iteraciones <= 2_000_000,
         {:ok, salt} <- Base.decode64(salt_encoded),
         {:ok, expected} <- Base.decode64(hash_encoded),
         true <- byte_size(salt) == @longitud_salt and byte_size(expected) == @longitud_hash do
      actual = derive(password, salt, iteraciones)
      :crypto.hash_equals(actual, expected)
    else
      _resultado -> false
    end
  end

  def verificar(_password, _encoded_hash), do: false

  defp derive(password, salt, iteraciones),
    do: :crypto.pbkdf2_hmac(:sha256, password, salt, iteraciones, @longitud_hash)
end
