defmodule Archethic.P2P.Message.GetFirstTransactionAddressTest do
  @moduledoc false
  use ExUnit.Case
  use ArchethicCase

  import Mox

  alias Archethic.P2P.Message
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.P2P.Message.GetFirstTransactionAddress

  doctest GetFirstTransactionAddress

  test "Process" do
    MockDB
    |> stub(:get_genesis_address, fn
      "not_existing_address" ->
        "not_existing_address"

      "address10" ->
        "address0"
    end)
    |> stub(:list_chain_addresses, fn
      "not_existing_address" ->
        []

      "address0" ->
        [
          {"address1", DateTime.add(DateTime.utc_now(), -2000)},
          {"addr2", DateTime.add(DateTime.utc_now(), -1000)},
          {"addr3", DateTime.add(DateTime.utc_now(), -500)}
        ]
    end)

    assert %FirstTransactionAddress{address: "address1"} =
             GetFirstTransactionAddress.process(
               %GetFirstTransactionAddress{address: "address10"},
               ArchethicCase.random_public_key()
             )
  end

  test "encode decode" do
    msg = %GetFirstTransactionAddress{address: <<0::272>>}

    assert msg ==
             msg
             |> Message.encode()
             |> Message.decode()
             |> elem(0)
  end
end
