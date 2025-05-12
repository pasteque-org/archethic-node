defmodule Archethic.Crypto.Ed25519 do
  @moduledoc false

  import Bitwise

  @p 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFED

  @doc """
  Generate an Ed25519 key pair
  """
  @spec generate_keypair(binary()) :: {binary(), binary()}
  def generate_keypair(seed) when is_binary(seed) and byte_size(seed) < 32 do
    seed = :crypto.hash(:sha256, seed)
    do_generate_keypair(seed)
  end

  def generate_keypair(seed) when is_binary(seed) and byte_size(seed) > 32 do
    do_generate_keypair(:binary.part(seed, 0, 32))
  end

  def generate_keypair(seed) when is_binary(seed) do
    do_generate_keypair(seed)
  end

  defp do_generate_keypair(seed) do
    :crypto.generate_key(:eddsa, :ed25519, seed)
  end

  @doc """
  Converts an Ed25519 private key to an X25519 private key.

  This function takes a 32-byte Ed25519 private key and converts it to a format
  suitable for use with X25519 (Curve25519) key exchange. The conversion follows
  the standard process of:

  1. Hashing the Ed25519 private key with SHA-512
  2. Taking the first 32 bytes of the hash
  3. Applying Curve25519 key clamping to the result

  The key clamping performs the following bit operations:
  - Clears the lower 3 bits of the first byte
  - Clears the highest bit of the last byte
  - Sets the second highest bit of the last byte

  ## Parameters
    - `ed25519_private_key`: A 32-byte binary representing the Ed25519 private key

  ## Returns
    A 32-byte binary representing the X25519 private key

  ## Examples
      iex> ed25519_key =
      ...>   Base.decode16!("F6FA87586DB70F6FDE9BEEE377E2E68F4678D71231969976266155172B1F6C0F")
      ...> 
      ...> Ed25519.convert_to_x25519_private_key(ed25519_key) |> Base.encode16()
      "C8CE0F2836A8D1D294E185E8A6E20B445192831DC6DD4139090FA7D5DE0F9F67"
  """
  @spec convert_to_x25519_private_key(ed25519_private_key :: binary()) :: binary()
  def convert_to_x25519_private_key(ed25519_private_key)
      when byte_size(ed25519_private_key) == 32 do
    :sha512
    |> :crypto.hash(ed25519_private_key)
    |> :binary.part(0, 32)
    |> clamp_curve25519_key()
  end

  # Curve25519 key clamping (constant-time bit operations)
  defp clamp_curve25519_key(<<first::8, middle::bytes-size(30), last::8>>) do
    clamped = <<first &&& 0b11111000>> <> middle <> <<(last &&& 0b00111111) ||| 0b01000000>>
    # Copy binary to reduce memory dump exposure
    :binary.copy(clamped)
  end

  @doc """
  Converts an Ed25519 public key to an X25519 public key.

  This function performs a mathematical transformation to convert a point on the Ed25519
  curve to a point on the X25519 (Curve25519) curve. The conversion follows the standard
  process of:

  1. Extracts the y-coordinate from the Ed25519 public key (clearing the sign bit)
  2. Computes the Montgomery u-coordinate using the formula: 
     `u = (1 + y) / (1 - y) mod p`
     where `p = 2^255 - 19` (the Curve25519 prime field order)
  3. Handles modular arithmetic with proper inversion using Fermat's Little Theorem
  4. Encodes the result as a little-endian 256-bit integer

  ## Parameters
    - `ed25519_public_key`: A 32-byte binary representing the Ed25519 public key

  ## Returns
    A 32-byte binary representing the X25519 public key

  ## Examples
      iex> ed25519_pub =
      ...>   Base.decode16!("D75A980182B10AB7D54BFED3C964073A0EE172F3DAA62325AF021A68F707511A")
      ...> 
      ...> Ed25519.convert_to_x25519_public_key(ed25519_pub) |> Base.encode16()
      "D85E07EC22B0AD881537C2F44D662D1A143CF830C57ACA4305D85C7A90F6B62E"
  """
  @spec convert_to_x25519_public_key(ed25519_public_key :: binary()) :: binary()
  def convert_to_x25519_public_key(ed25519_public_key)
      when byte_size(ed25519_public_key) == 32 do
    # Extract y-coordinate (clearing sign bit)
    <<y_bytes::binary-size(31), last_byte>> = ed25519_public_key
    y = :binary.decode_unsigned(y_bytes <> <<last_byte &&& 0x7F>>, :little)

    # Compute u = (1 + y) / (1 - y) mod p (using non-negative mod)
    numerator = Integer.mod(1 + y, @p)
    denominator = Integer.mod(1 - y, @p)
    inv_denominator = mod_pow(denominator, @p - 2, @p)
    u = Integer.mod(numerator * inv_denominator, @p)

    # Encode as X25519 key
    <<u::little-unsigned-integer-size(256)>>
  end

  # Fixed modular exponentiation with non-negative inputs
  defp mod_pow(base, exp, mod) when base >= 0 and mod > 0 do
    base_bin = :binary.encode_unsigned(base)
    exp_bin = :binary.encode_unsigned(exp)
    mod_bin = :binary.encode_unsigned(mod)

    base_bin |> :crypto.mod_pow(exp_bin, mod_bin) |> :binary.decode_unsigned()
  end

  @doc """
  Sign a message with the given Ed25519 private key
  """
  @spec sign(binary(), iodata()) :: binary()
  def sign(_key = <<private_key::binary-32>>, data) when is_binary(data) or is_list(data) do
    :crypto.sign(:eddsa, :sha512, data, [private_key, :ed25519])
  end

  @doc """
  Verify if a given Ed25519 public key matches the signature among with its data
  """
  @spec verify?(binary(), binary(), binary()) :: boolean()
  def verify?(<<public_key::binary-32>>, data, sig)
      when (is_binary(data) or is_list(data)) and is_binary(sig) do
    :crypto.verify(:eddsa, :sha512, data, sig, [public_key, :ed25519])
  end
end
