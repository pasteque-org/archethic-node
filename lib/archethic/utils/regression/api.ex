defmodule Archethic.Utils.Regression.Api do
  @moduledoc """
  Collection of functions to work on the Apis
  """

  alias Archethic.Utils
  alias ArchethicClient.Crypto
  alias ArchethicClient.Graphql
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData

  require Logger

  @faucet_seed Application.compile_env(:archethic, [ArchethicWeb.Explorer.FaucetController, :seed])

  defstruct [
    :host,
    :port,
    protocol: :http
  ]

  @type t() :: %__MODULE__{
          host: String.t(),
          port: integer(),
          protocol: :http | :https
        }

  @doc """
  Send funds to the given seeds
  """
  @spec send_funds_to_seeds(amount_by_seed :: %{String.t() => integer()}) :: String.t()
  def send_funds_to_seeds(amount_by_seed) do
    amount_by_seed
    |> Map.new(fn {seed, amount} -> {Crypto.derive_address(seed, 0), amount} end)
    |> send_funds_to_addresses()
  end

  @doc """
  Send funds to the given hexadecimal addresses
  """
  @spec send_funds_to_addresses(amount_by_address :: %{String.t() => integer()}) :: String.t()
  def send_funds_to_addresses(amount_by_address) do
    funding_tx =
      amount_by_address
      |> Enum.reduce(%TransactionData{}, fn {address, amount}, acc ->
        TransactionData.add_uco_transfer(acc, address, Utils.to_bigint(amount))
      end)
      |> Transaction.build(:transfer, @faucet_seed)

    case ArchethicClient.send_transaction(funding_tx) do
      :ok ->
        funding_tx.address

      {:error, reason} ->
        raise "Funding transaction failed: #{Exception.message(reason)}"
    end
  end

  @doc """
  Get the current nonce public key
  """
  @spec get_storage_nonce_public_key() :: String.t()
  def get_storage_nonce_public_key do
    graphql_request = %Graphql{
      name: "sharedSecrets",
      args: [],
      fields: [:storageNoncePublicKey]
    }

    result = ArchethicClient.request!(graphql_request)
    Base.decode16!(result["storageNoncePublicKey"])
  end

  @doc """
  Get the last transaction of the chain
  """
  @spec get_last_transaction(address :: binary()) :: map()
  def get_last_transaction(address) do
    graphql_request = %Graphql{
      name: "lastTransaction",
      args: [address: Base.encode16(address)],
      fields: [
        :type,
        :address,
        {:data, [:content, :code]},
        {:validationStamp, [:timestamp]}
      ]
    }

    ArchethicClient.request!(graphql_request)
  end

  @doc """
  Get the inputs of transaction
  """
  @spec get_inputs(address :: binary()) :: list(map())
  def get_inputs(address) do
    address_hex = Base.encode16(address)

    graphql_request = %Graphql{
      name: "transactionInputs",
      args: [address: address_hex],
      fields: [:amount, :type, :from, :timestamp]
    }

    ArchethicClient.request!(graphql_request)
  end

  @doc """
  Get unspent outputs for a given address.
  """
  @spec get_unspent_outputs(address :: binary()) :: list(map())
  def get_unspent_outputs(address) do
    address_hex = Base.encode16(address)

    graphql_request = %Graphql{
      name: "chainUnspentOutputs",
      args: [address: address_hex],
      fields: [
        :amount,
        :type,
        :from,
        :timestamp,
        :tokenAddress,
        :tokenId,
        state: [:version, :data]
      ]
    }

    ArchethicClient.request!(graphql_request)
  end
end
