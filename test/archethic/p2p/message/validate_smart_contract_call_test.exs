defmodule Archethic.P2P.Message.ValidateSmartContractCallTest do
  use ArchethicCase

  import ArchethicCase
  import Mox

  alias Archethic.ContractFactory
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.Mining.Fee
  alias Archethic.P2P
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.SmartContractCallValidation
  alias Archethic.P2P.Message.UnspentOutputList
  alias Archethic.P2P.Message.ValidateSmartContractCall
  alias Archethic.P2P.Node
  alias Archethic.Reward.MemTables.RewardTokens
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger
  alias Archethic.TransactionChain.TransactionData.Recipient
  alias Archethic.TransactionChain.TransactionData.UCOLedger
  alias Archethic.TransactionChain.TransactionData.UCOLedger.Transfer
  alias Archethic.TransactionFactory
  alias Archethic.Utils

  doctest ValidateSmartContractCall

  describe "serialize/deserialize" do
    test "should work with unnamed action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address()},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        timestamp: DateTime.utc_now(:millisecond)
      }

      assert {^msg, <<>>} =
               msg
               |> ValidateSmartContractCall.serialize()
               |> ValidateSmartContractCall.deserialize()
    end

    test "should work with named action" do
      msg = %ValidateSmartContractCall{
        recipient: %Recipient{address: random_address(), action: "do_it", args: %{}},
        transaction: Archethic.TransactionFactory.create_valid_transaction(),
        timestamp: DateTime.utc_now(:millisecond)
      }

      assert {^msg, <<>>} =
               msg
               |> ValidateSmartContractCall.serialize()
               |> ValidateSmartContractCall.deserialize()
    end
  end

  describe "process/2" do
    setup do
      P2P.add_and_connect_node(%Node{
        ip: {127, 0, 0, 1},
        port: 3005,
        first_public_key: :crypto.strong_rand_bytes(32),
        last_public_key: :crypto.strong_rand_bytes(32),
        available?: true,
        authorized?: true,
        authorization_date: DateTime.add(DateTime.utc_now(), -1000),
        geo_patch: "AAA"
      })

      :ok
    end

    test "should validate smart contract call and return valid message" do
      tx =
        ContractFactory.create_valid_contract_tx(
          ~s"""
          @version 1

          condition triggered_by: transaction, as: [
            timestamp: transaction.timestamp > 0
          ]

          actions triggered_by: transaction do
            Contract.set_content "hello"
          end
          """,
          seed: "contract_without_named_action_with_valid_message"
        )

      expect(
        MockDB,
        :get_transaction,
        fn "@SC1_for_contract_without_named_action_with_valid_message", _, _ ->
          {:ok, tx}
        end
      )

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      expect(MockClient, :send_message, fn _, %GetUnspentOutputs{}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: [
             %UnspentOutput{
               from: random_address(),
               amount: Utils.to_bigint(3),
               type: :UCO,
               timestamp: DateTime.utc_now()
             }
           ]
         }}
      end)

      assert %SmartContractCallValidation{status: :ok} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{
                     address: "@SC1_for_contract_without_named_action_with_valid_message"
                   },
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should return a timeout" do
      tx =
        ContractFactory.create_valid_contract_tx(~s"""
        @version 1

        condition triggered_by: transaction do
          true
        end
        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
        """)

      expect(MockDB, :get_transaction, fn _, _, _ ->
        # timeout is set to 50ms
        Process.sleep(1_000)
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      assert %SmartContractCallValidation{status: {:error, :timeout}} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: random_address()},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 random_public_key()
               )
    end

    test "should validate smart contract call with named action and return valid message" do
      tx =
        ContractFactory.create_valid_contract_tx(
          ~s"""
          @version 1

          condition triggered_by: transaction, on: upgrade(), as: []
          actions triggered_by: transaction, on: upgrade() do
            Contract.set_code transaction.content
          end
          """,
          seed: "contract_with_named_action_and_valid_message"
        )

      expect(MockDB, :get_transaction, fn "@SC1_for_contract_with_named_action_and_valid_message",
                                          _,
                                          _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      expect(MockClient, :send_message, fn _, %GetUnspentOutputs{}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: [
             %UnspentOutput{
               from: random_address(),
               amount: Utils.to_bigint(3),
               type: :UCO,
               timestamp: DateTime.utc_now()
             }
           ]
         }}
      end)

      assert %SmartContractCallValidation{status: :ok} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{
                     address: "@SC1_for_contract_with_named_action_and_valid_message",
                     action: "upgrade",
                     args: %{}
                   },
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should return fee of generated transaction" do
      code = ~s"""
      @version 1

      condition triggered_by: transaction, as: [
        timestamp: transaction.timestamp > 0
      ]

      actions triggered_by: transaction do
        Contract.set_content "hello"
      end
      """

      tx = ContractFactory.create_valid_contract_tx(code, seed: "contract_with_test_for_fee")

      expect(MockDB, :get_transaction, fn "@SC1_for_contract_with_test_for_fee", _, _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      expected_fee =
        code
        |> ContractFactory.create_valid_contract_tx(
          content: "hello",
          seed: "contract_with_test_for_fee"
        )
        |> Fee.calculate(nil, 0.07, DateTime.utc_now(), nil, 0, current_protocol_version())

      expect(MockClient, :send_message, fn _, %GetUnspentOutputs{}, _ ->
        {:ok,
         %UnspentOutputList{
           unspent_outputs: [
             %UnspentOutput{
               from: random_address(),
               amount: Utils.to_bigint(3),
               type: :UCO,
               timestamp: DateTime.utc_now()
             }
           ]
         }}
      end)

      assert %SmartContractCallValidation{status: :ok, fee: ^expected_fee} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: "@SC1_for_contract_with_test_for_fee"},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should NOT validate smart contract that does not have a transaction trigger" do
      tx =
        ContractFactory.create_valid_contract_tx(
          ~s"""
          @version 1

          actions triggered_by: datetime, at: 1687874880 do
            Contract.set_content 42
          end
          """,
          seed: "contract_without_trigger_transaction"
        )

      expect(MockDB, :get_transaction, fn "@SC1_for_contract_without_trigger_transaction", _, _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      failure = %Failure{error: :missing_condition, user_friendly_error: "Missing condition"}

      assert %SmartContractCallValidation{status: {:error, :invalid_execution, ^failure}, fee: 0} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: "@SC1_for_contract_without_trigger_transaction"},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should validate smart contract call and return invalid message" do
      tx =
        ContractFactory.create_valid_contract_tx(
          ~s"""
          @version 1

          condition triggered_by: transaction, as: [
            content: "hola"
          ]

          actions triggered_by: transaction do
            Contract.set_content "hello"
          end
          """,
          seed: "contract_with_invalid_message"
        )

      expect(MockDB, :get_transaction, fn "@SC1_for_contract_with_invalid_message", _, _ ->
        {:ok, tx}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hi")

      assert %SmartContractCallValidation{status: {:error, :invalid_condition, "content"}, fee: 0} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: "@SC1_for_contract_with_invalid_message"},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should return insufficient_funds if contract has not enough funds " do
      tx =
        %Transaction{address: contract_address} =
        ContractFactory.create_valid_contract_tx(
          ~s"""
          @version 1

          condition triggered_by: transaction, as: []

          actions triggered_by: transaction do
            amount = Map.get(transaction.uco_transfers, contract.address)
            Contract.add_uco_transfer to: transaction.address, amount: amount + 5
          end
          """,
          seed: random_seed()
        )

      contract_genesis_address = Transaction.previous_address(tx)

      v_utxo = %UnspentOutput{
        from: random_address(),
        amount: Utils.to_bigint(3),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      utxo = %UnspentOutput{
        from: random_address(),
        amount: Utils.to_bigint(5),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      recipient = %Recipient{address: contract_genesis_address}

      incoming_tx =
        TransactionFactory.create_valid_transaction([utxo],
          ledger: %Ledger{
            uco: %UCOLedger{transfers: [%Transfer{to: contract_address, amount: 4}]}
          },
          recipients: [recipient]
        )

      expect(MockClient, :send_message, fn _,
                                           %GetUnspentOutputs{address: ^contract_genesis_address},
                                           _ ->
        {:ok, %UnspentOutputList{unspent_outputs: [v_utxo]}}
      end)

      MockDB
      |> expect(:get_last_chain_address, fn ^contract_genesis_address ->
        {contract_address, DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn ^contract_address, _, _ ->
        {:ok, tx}
      end)

      assert %SmartContractCallValidation{status: {:error, :insufficient_funds}, fee: 0} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: recipient,
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should return :ok if contract has enough funds " do
      tx =
        %Transaction{address: contract_address} =
        ContractFactory.create_valid_contract_tx(
          ~s"""
          @version 1

          condition triggered_by: transaction, as: []

          actions triggered_by: transaction do
            amount = Map.get(transaction.uco_transfers, contract.address)
            Contract.add_uco_transfer to: transaction.address, amount: amount + 1
          end
          """,
          seed: random_seed()
        )

      contract_genesis_address = Transaction.previous_address(tx)

      utxo = %UnspentOutput{
        from: random_address(),
        amount: Utils.to_bigint(3),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      input = %UnspentOutput{
        from: random_address(),
        amount: Utils.to_bigint(5),
        type: :UCO,
        timestamp: DateTime.utc_now()
      }

      recipient = %Recipient{address: contract_genesis_address}

      incoming_tx =
        TransactionFactory.create_valid_transaction([input],
          ledger: %Ledger{
            uco: %UCOLedger{transfers: [%Transfer{to: contract_address, amount: 4}]}
          },
          recipients: [recipient]
        )

      expect(MockClient, :send_message, fn _,
                                           %GetUnspentOutputs{address: ^contract_genesis_address},
                                           _ ->
        {:ok, %UnspentOutputList{unspent_outputs: [utxo]}}
      end)

      MockDB
      |> expect(:get_last_chain_address, fn ^contract_genesis_address ->
        {contract_address, DateTime.utc_now()}
      end)
      |> expect(:get_transaction, fn ^contract_address, _, _ ->
        {:ok, tx}
      end)

      assert %SmartContractCallValidation{status: :ok, fee: _} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: recipient,
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 random_public_key()
               )
    end

    test "should return custom message when throw in condition" do
      tx =
        ContractFactory.create_valid_contract_tx(~s"""
        @version 1

        condition triggered_by: transaction do
          throw code: 1234, message: "Custom message", data: [key: "custom data"]
        end

        actions triggered_by: transaction do
          Contract.set_content "hello"
        end
        """)

      expect(MockDB, :get_transaction, fn "@SC1", _, _ -> {:ok, tx} end)
      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hi")

      message = "Custom message - L4"

      data = %{
        "code" => 1234,
        "message" => "Custom message",
        "data" => %{"key" => "custom data"}
      }

      assert %SmartContractCallValidation{
               status:
                 {:error, :invalid_execution,
                  %Failure{user_friendly_error: ^message, error: :contract_throw, data: ^data}},
               fee: 0
             } =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: "@SC1"},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should return custom message when throw in action" do
      tx =
        ContractFactory.create_valid_contract_tx(~s"""
        @version 1

        condition triggered_by: transaction do
          true
        end

        actions triggered_by: transaction do
          throw code: 1234, message: "Custom message", data: [key: "custom data"]
        end
        """)

      expect(MockDB, :get_transaction, fn "@SC1", _, _ -> {:ok, tx} end)
      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hi")

      message = "Custom message - L8"

      data = %{
        "code" => 1234,
        "message" => "Custom message",
        "data" => %{"key" => "custom data"}
      }

      assert %SmartContractCallValidation{
               status:
                 {:error, :invalid_execution,
                  %Failure{user_friendly_error: ^message, error: :contract_throw, data: ^data}},
               fee: 0
             } =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: "@SC1"},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 :crypto.strong_rand_bytes(32)
               )
    end

    test "should filter the utxos coming from calls" do
      contract_tx =
        ContractFactory.create_valid_contract_tx(~s"""
        @version 1
        condition triggered_by: transaction, as: [
          content: contract.balance.uco == 3.0
        ]
        actions triggered_by: transaction do
          Contract.set_content "ok"
        end
        """)

      contract_address = contract_tx.address
      call_address = random_address()
      now = DateTime.utc_now()

      expect(MockDB, :get_transaction, fn
        ^contract_address, _, _ -> {:ok, contract_tx}
      end)

      expect(MockClient, :send_message, fn
        _, %GetUnspentOutputs{address: ^contract_address}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %UnspentOutput{
                 from: random_address(),
                 type: :UCO,
                 amount: Utils.to_bigint(3),
                 timestamp: now
               },
               %UnspentOutput{from: call_address, type: :call, timestamp: now},
               %UnspentOutput{amount: 100_000_000, from: call_address, type: :UCO, timestamp: now}
             ],
             more?: false,
             offset: nil
           }}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([], content: "hola")

      assert %SmartContractCallValidation{status: :ok} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: contract_address},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 random_public_key()
               )
    end

    test "should be able to transfer assets received from calls" do
      start_supervised!(RewardTokens)

      token_address = random_address()

      contract_tx =
        ContractFactory.create_valid_contract_tx(~s"""
        @version 1
        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          Contract.add_token_transfer to: "#{Base.encode16(random_address())}", amount: 5, token_address: "#{Base.encode16(token_address)}"
        end
        """)

      incoming_tx =
        TransactionFactory.create_valid_transaction([],
          ledger: %TransactionData.Ledger{
            token: %TransactionData.TokenLedger{
              transfers: [
                %TransactionData.TokenLedger.Transfer{
                  to: contract_tx.address,
                  amount: Utils.to_bigint(5),
                  token_address: token_address
                }
              ]
            }
          }
        )

      contract_address = contract_tx.address
      now = DateTime.utc_now()

      expect(MockDB, :get_transaction, fn
        ^contract_address, _, _ -> {:ok, contract_tx}
      end)

      expect(MockClient, :send_message, fn
        _, %GetUnspentOutputs{address: ^contract_address}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %UnspentOutput{
                 from: random_address(),
                 type: :UCO,
                 amount: Utils.to_bigint(3),
                 timestamp: now
               }
             ],
             more?: false,
             offset: nil
           }}
      end)

      assert %SmartContractCallValidation{status: :ok} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: contract_address},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 random_public_key()
               )
    end

    test "should be able to transfer assets minted" do
      start_supervised!(RewardTokens)

      contract_tx =
        ContractFactory.create_valid_contract_tx(~s"""
        @version 1
        condition triggered_by: transaction, as: []

        actions triggered_by: transaction do
          Contract.set_type("token")
          token_definition = Json.to_string(
            [
              aeip: [8, 18, 19],
              supply: Math.trunc(100 * 100_000_000),
              type: "fungible",
              symbol: "TK",
              name: "TOKEN_NAME",
              recipients: [
                [to: "#{Base.encode16(random_address())}", amount: Math.trunc(100 * 100_000_000)]
              ]

            ]
          )
          Contract.set_content(token_definition)
        end
        """)

      contract_address = contract_tx.address
      now = DateTime.utc_now()

      expect(MockDB, :get_transaction, fn
        ^contract_address, _, _ -> {:ok, contract_tx}
      end)

      expect(MockClient, :send_message, fn
        _, %GetUnspentOutputs{address: ^contract_address}, _ ->
          {:ok,
           %UnspentOutputList{
             unspent_outputs: [
               %UnspentOutput{
                 from: random_address(),
                 type: :UCO,
                 amount: Utils.to_bigint(3),
                 timestamp: now
               }
             ],
             more?: false,
             offset: nil
           }}
      end)

      incoming_tx = TransactionFactory.create_valid_transaction([])

      assert %SmartContractCallValidation{status: :ok} =
               ValidateSmartContractCall.process(
                 %ValidateSmartContractCall{
                   recipient: %Recipient{address: contract_address},
                   transaction: incoming_tx,
                   timestamp: DateTime.utc_now()
                 },
                 random_public_key()
               )
    end
  end
end
