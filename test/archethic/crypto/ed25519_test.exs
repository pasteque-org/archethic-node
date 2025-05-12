defmodule Archethic.Crypto.Ed25519Test do
  use ExUnit.Case, async: true

  alias Archethic.Crypto.Ed25519

  doctest Ed25519

  test "generate_keypair/2 should produce a deterministic keypair" do
    assert Ed25519.generate_keypair("myseed") == Ed25519.generate_keypair("myseed")
  end

  test "sign/3 should produce the same signature" do
    {_, pv} = Ed25519.generate_keypair("myseed")
    assert Ed25519.sign(pv, "hello") == Ed25519.sign(pv, "hello")
  end

  test "verify?/4 should return true when the signature is valid" do
    {pub, pv} = Ed25519.generate_keypair("myseed")
    sig = Ed25519.sign(pv, "hello")
    assert Ed25519.verify?(pub, "hello", sig)
  end

  test "convert_public_key_to_x25519/1 should convert a ed25519 public into a x25519 public key" do
    seed =
      <<71, 35, 126, 230, 163, 84, 90, 215, 215, 23, 244, 30, 11, 130, 234, 119, 150, 24, 203,
        125, 60, 53, 109, 214, 11, 225, 110, 226, 168, 103, 64, 90>>

    {pub, _pv} = :crypto.generate_key(:eddsa, :ed25519, seed)

    assert <<115, 197, 215, 64, 38, 160, 186, 251, 140, 192, 237, 237, 57, 133, 110, 153, 40, 154,
             251, 163, 56, 34, 41, 243, 234, 148, 121, 108, 19, 249, 56,
             50>> == Ed25519.convert_to_x25519_public_key(pub)
  end

  test "convert_secret_key_to_x25519/1 should convert a ed25519 secret key into a x25519 secret key" do
    seed =
      <<71, 35, 126, 230, 163, 84, 90, 215, 215, 23, 244, 30, 11, 130, 234, 119, 150, 24, 203,
        125, 60, 53, 109, 214, 11, 225, 110, 226, 168, 103, 64, 90>>

    {_pub, pv} = :crypto.generate_key(:eddsa, :ed25519, seed)

    assert <<176, 78, 71, 108, 224, 218, 228, 207, 89, 64, 134, 19, 85, 52, 113, 140, 69, 93, 223,
             19, 218, 167, 7, 203, 250, 161, 201, 249, 228, 162, 20,
             81>> = Ed25519.convert_to_x25519_private_key(pv)
  end
end
