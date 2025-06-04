defmodule Archethic.Utils.Regression.Playbook.UCO do
  @moduledoc """
  Regression playbook for verifying UCO transfer functionality.

  This playbook executes scenarios involving:
  - Valid UCO transfers between addresses.
  - Attempted UCO transfers with insufficient funds.
  It checks balances and chain state to ensure the UCO ledger behaves as expected.
  """

  use Archethic.Utils.Regression.Playbook

  alias ArchethicClient.Crypto
  alias ArchethicClient.RequestHelper
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData

  require Logger

  @unit_uco 100_000_000
  # Get the pre-configured faucet seed at compile time
  @faucet_seed Application.compile_env!(:archethic, [
                 ArchethicWeb.Explorer.FaucetController,
                 :seed
               ])

  @doc """
  Runs the UCO playbook scenarios against a randomly selected node from the list.

  Initializes the necessary WebSocket client (if still used) and determines the target base URL,
  then executes the transfer tests.

  """
  def play!(_nodes, _opts) do
    Logger.info("Play UCO transactions")
    run_transfers()
  end

  defp run_transfers do
    invalid_transfer()
    single_recipient_transfer()
  end

  @doc false
  # Tests a simple, valid UCO transfer scenario:
  # 1. Funds a recipient address.
  # 2. Transfers a portion of those funds from the recipient to a new address.
  # 3. Verifies the balances of both addresses after the transfer.
  defp single_recipient_transfer do
    recipient_seed = "recipient_1"

    recipient_address = Crypto.derive_address(recipient_seed, 0)
    recipient_address_hex = Base.encode16(recipient_address)

    {:ok, %{"uco" => prev_balance}} = ArchethicClient.get_balance(recipient_address_hex)

    # Build funding transaction data
    funding_tx =
      %TransactionData{}
      |> TransactionData.add_uco_transfer(recipient_address, trunc(10 * @unit_uco))
      |> Transaction.build(:transfer, @faucet_seed)

    case ArchethicClient.send_transaction(funding_tx) do
      :ok -> :ok
      {:error, reason} -> raise "Funding transaction failed: #{Exception.message(reason)}"
    end

    # Get new balance
    {:ok, %{"uco" => new_balance}} = ArchethicClient.get_balance(recipient_address_hex)

    true =
      new_balance -
        prev_balance == trunc(@unit_uco * 10)

    Logger.info("#{recipient_address_hex} received 10 UCO")

    new_recipient_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    new_recipient_address_hex = Base.encode16(new_recipient_address)

    Logger.info("#{recipient_address_hex} is sending 5 UCO to #{new_recipient_address_hex}")

    # Build transfer transaction data
    transfer_tx =
      %TransactionData{}
      |> TransactionData.add_uco_transfer(new_recipient_address, trunc(5 * @unit_uco))
      |> Transaction.build(:transfer, recipient_seed)

    case ArchethicClient.send_transaction(transfer_tx) do
      :ok -> :ok
      {:error, reason} -> raise "Funding transaction failed: #{Exception.message(reason)}"
    end

    Logger.info("Transaction #{Base.encode16(transfer_tx.address)} submitted")

    [%{"uco" => new_recipient_balance}, %{"uco" => recipient_balance2}] =
      ArchethicClient.batch_requests!([
        RequestHelper.get_balance(new_recipient_address_hex),
        RequestHelper.get_balance(recipient_address_hex)
      ])

    # Ensure the second recipient received the 5.0 UCO
    true = 5 * @unit_uco == new_recipient_balance
    Logger.info("#{new_recipient_address_hex} received 5.0 UCO")

    # Ensure the first recipient amount have decreased
    # 5.0 - transaction fee
    true = recipient_balance2 <= new_balance - 5 * @unit_uco
    Logger.info("#{new_recipient_address_hex} now got #{recipient_balance2 / @unit_uco} UCO")
  end

  @doc false
  # Tests an invalid UCO transfer scenario:
  # 1. Attempts to send UCO from a new, unfunded address.
  # 2. Verifies that the recipient address balance remains 0.
  # 3. Verifies that the sender address chain index remains 0 (no transaction was created).
  defp invalid_transfer do
    from_seed = :crypto.strong_rand_bytes(32)
    recipient_address = <<0::8, 0::8, :crypto.strong_rand_bytes(32)::binary>>
    recipient_address_hex = Base.encode16(recipient_address)

    # Build invalid transaction data
    invalid_tx_data =
      %TransactionData{}
      |> TransactionData.add_uco_transfer(recipient_address, trunc(10 * @unit_uco))
      |> Transaction.build(:transfer, from_seed)

    case ArchethicClient.send_transaction(invalid_tx_data) do
      :ok -> :ok
      {:error, reason} -> {:error, Exception.message(reason)}
    end

    Process.sleep(1000)

    # Verify recipient balance is still 0
    {:ok, %{"uco" => new_uco_balance}} = ArchethicClient.get_balance(recipient_address_hex)

    0 = new_uco_balance
    0 = ArchethicClient.get_chain_index!(recipient_address_hex)

    Logger.info("Transaction with insufficient funds is rejected")
  end
end
