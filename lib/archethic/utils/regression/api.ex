defmodule Archethic.Utils.Regression.Api do
  @moduledoc """
  Collection of functions to work on the Apis
  """

  require Logger
  alias ArchethicClient
  alias ArchethicClient.Crypto

  alias ArchethicClient.TransactionData
  alias ArchethicClient.Transaction
  alias ArchethicClient.TransactionData.Ledger
  alias ArchethicClient.TransactionData.Ledger.UCOLedger

  alias Archethic.Utils
  alias ArchethicClient.Graphql

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
  @spec send_funds_to_seeds(%{String.t() => integer()}) :: String.t()
  def send_funds_to_seeds(amount_by_seed) do
    amount_by_address =
      amount_by_seed
      |> Enum.map(fn {seed, amount} ->
        {Crypto.derive_address(seed, 0, curve: :ed25519), amount}
      end)
      |> Enum.into(%{})

    send_funds_to_addresses(amount_by_address)
  end

  @doc """
  Send funds to the given hexadecimal addresses
  """
  @spec send_funds_to_addresses(%{String.t() => integer()}) :: String.t()
  def send_funds_to_addresses(amount_by_address) do
    transfers =
      Enum.map(amount_by_address, fn {address, amount} ->
        %UCOLedger.Transfer{
          to: address,
          amount: Utils.to_bigint(amount)
        }
      end)

    funding_tx =
      %TransactionData{
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: transfers
          }
        }
      }
      |> Transaction.build(:transfer, @faucet_seed)

    ArchethicClient.send_transaction(funding_tx)
    funding_tx.address
  end

  @doc """
  Get the current nonce public key
  """
  @spec get_storage_nonce_public_key(list()) :: {:ok, String.t()} | {:error, term()}
  def get_storage_nonce_public_key(opts \\ []) do
    graphql_request = %Graphql{
      name: "sharedSecrets",
      args: [],
      fields: [:storageNoncePublicKey]
    }

    case ArchethicClient.request(graphql_request, opts) do
      {:ok,
       %{
         "storageNoncePublicKey" => storage_nonce_public_key
       }} ->
        {:ok, Base.decode16!(storage_nonce_public_key)}

      {:error, reason} ->
        {:error, reason}

      other ->
        # Handle unexpected successful responses that don't match the expected structure
        {:error, {:unexpected_response, other}}
    end
  end

  @doc """
  Get the last transaction of the chain
  """
  @spec get_last_transaction(binary(), list()) :: map()
  def get_last_transaction(address, opts \\ []) do
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

    ArchethicClient.request!(graphql_request, opts)
  end

  @doc """
  Get the UCO balance of the chain
  """
  @spec get_uco_balance(binary(), list()) :: {:ok, integer()} | {:error, term()}
  def get_uco_balance(address, opts \\ []) do
    address_hex = Base.encode16(address)

    graphql_request = %Graphql{
      name: "balance",
      args: [address: address_hex],
      fields: [:uco]
    }

    case ArchethicClient.request(graphql_request, opts) do
      {:ok, %{"uco" => uco_value}} ->
        {:ok, uco_value}

      {:error, reason} ->
        {:error, reason}

      # Catch-all for other {:ok, ...} responses
      unexpected_success ->
        {:error, {:unexpected_response, unexpected_success}}
    end
  end

  @doc """
  Get the inputs of transaction
  """
  @spec get_inputs(binary(), list()) :: {:ok, list(map())} | {:error, term()}
  def get_inputs(address, opts \\ []) do
    address_hex = Base.encode16(address)

    graphql_request = %Graphql{
      name: "transactionInputs",
      args: [address: address_hex],
      fields: [:amount, :type, :from, :timestamp]
    }

    case ArchethicClient.request(graphql_request, opts) do
      {:ok, inputs_list} when is_list(inputs_list) ->
        {:ok, inputs_list}

      {:error, reason} ->
        {:error, reason}

      # Catch-all for other {:ok, ...} responses
      unexpected_success ->
        {:error, {:unexpected_response, unexpected_success}}
    end
  end

  @doc """
  Get unspent outputs for a given address.
  """
  @spec get_unspent_outputs(binary(), list()) :: list(map())
  def get_unspent_outputs(address, opts \\ []) do
    address_hex = Base.encode16(address)

    graphql_request = %Graphql{
      name: "chainUnspentOutputs",
      args: [address: address_hex],
      fields: [:amount, :type, :from, :timestamp, :state, :tokenAddress, :tokenId]
    }

    ArchethicClient.request!(graphql_request, opts)
  end
end
