defmodule Archethic.P2P.NodeConfigTest do
  use ExUnit.Case

  import ArchethicCase

  alias Archethic.Crypto
  alias Archethic.P2P.Node
  alias Archethic.P2P.NodeConfig

  describe "from_node/1" do
    test "should create a node config from a node" do
      first_public_key = random_public_key()
      reward_address = random_address()
      origin_public_key = random_public_key()
      mining_public_key = :bls |> Crypto.generate_random_keypair() |> elem(0)

      node = %Node{
        first_public_key: first_public_key,
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        transport: :tcp,
        reward_address: reward_address,
        origin_public_key: origin_public_key,
        mining_public_key: mining_public_key,
        geo_patch: "AAA"
      }

      assert %NodeConfig{
               ip: {127, 0, 0, 1},
               port: 3000,
               http_port: 4000,
               transport: :tcp,
               reward_address: ^reward_address,
               origin_public_key: ^origin_public_key,
               mining_public_key: ^mining_public_key,
               geo_patch: "AAA"
             } = NodeConfig.from_node(node)
    end
  end

  describe "different?/2" do
    test "should return true when configs are different" do
      config1 = %NodeConfig{
        first_public_key: random_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        transport: :tcp,
        reward_address: random_address(),
        origin_public_key: random_public_key(),
        origin_certificate: :crypto.strong_rand_bytes(32),
        mining_public_key: random_public_key(),
        geo_patch: "AAA",
        geo_patch_update: DateTime.utc_now(:second)
      }

      config2 = %NodeConfig{
        first_public_key: random_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        transport: :tcp,
        reward_address: random_address(),
        origin_public_key: random_public_key(),
        origin_certificate: :crypto.strong_rand_bytes(32),
        mining_public_key: random_public_key(),
        geo_patch: "BBB",
        geo_patch_update: DateTime.utc_now(:second)
      }

      assert NodeConfig.different?(config1, config2)
    end

    test "should return false when configs are the same (ignoring certificates)" do
      config = %NodeConfig{
        first_public_key: random_public_key(),
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        transport: :tcp,
        reward_address: random_address(),
        origin_public_key: random_public_key(),
        origin_certificate: :crypto.strong_rand_bytes(32),
        mining_public_key: :bls |> Crypto.generate_random_keypair() |> elem(0),
        geo_patch: "AAA",
        geo_patch_update: DateTime.utc_now(:second)
      }

      same_config = %{
        config
        | origin_certificate: :crypto.strong_rand_bytes(32),
          geo_patch_update: :second |> DateTime.utc_now() |> DateTime.add(-2)
      }

      refute NodeConfig.different?(config, same_config)
    end
  end

  describe "serialize/1 and deserialize/1" do
    test "should serialize and deserialize a node config" do
      config = %NodeConfig{
        first_public_key: nil,
        ip: {127, 0, 0, 1},
        port: 3000,
        http_port: 4000,
        transport: :tcp,
        reward_address: random_address(),
        origin_public_key: random_public_key(),
        origin_certificate: :crypto.strong_rand_bytes(32),
        mining_public_key: random_public_key(),
        geo_patch: "AAA",
        geo_patch_update: DateTime.utc_now(:second)
      }

      assert {config, <<>>} == config |> NodeConfig.serialize() |> NodeConfig.deserialize()
    end

    test "should return error when binary is invalid" do
      assert :error = NodeConfig.deserialize(<<>>)
      assert :error = NodeConfig.deserialize(<<1, 2, 3>>)
    end
  end
end
