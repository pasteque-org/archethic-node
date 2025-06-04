defmodule Archethic.Contracts.Interpreter.Legacy.LibraryTest do
  use ArchethicCase

  import Mox

  alias Archethic.Contracts.Interpreter.Legacy.Library
  alias Archethic.P2P
  alias Archethic.P2P.Message.FirstTransactionAddress
  alias Archethic.P2P.Message.GetFirstTransactionAddress
  alias Archethic.P2P.Node
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionFactory
  alias Archethic.Utils

  doctest Library

  describe "get_token_id\1" do
    test "should return token_id given the address of the transaction" do
      content =
        JSON.encode!(%{
          supply: 300_000_000,
          name: "MyToken",
          type: "non-fungible",
          symbol: "MTK",
          properties: %{
            global: "property"
          },
          collection: [
            %{image: "link", value: "link"},
            %{image: "link", value: "link"},
            %{image: "link", value: "link"}
          ]
        })

      tx =
        %Transaction{address: token_address} =
        TransactionFactory.create_valid_transaction([], content: content, type: :token, index: 24)

      stub(MockDB, :get_transaction, fn ^token_address, _, _ -> {:ok, tx} end)
      {:ok, %{id: token_id}} = Utils.get_token_properties(tx)

      assert token_id == Library.get_token_id(tx.address)
    end
  end

  test "get_first_transaction_address/1" do
    P2P.add_and_connect_node(%Node{
      ip: {127, 0, 0, 1},
      port: 3000,
      first_public_key: "key1",
      last_public_key: "key1",
      network_patch: "AAA",
      geo_patch: "AAA",
      available?: true,
      authorized?: true,
      authorization_date: DateTime.utc_now()
    })

    addr1 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::bitstring>>
    addr2 = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::bitstring>>

    expect(MockClient, :send_message, fn
      _, %GetFirstTransactionAddress{address: ^addr1}, _ ->
        {:ok, %FirstTransactionAddress{address: addr2, timestamp: DateTime.utc_now()}}
    end)

    assert Base.encode16(addr2) == Library.get_first_transaction_address(Base.encode16(addr1))
  end
end
