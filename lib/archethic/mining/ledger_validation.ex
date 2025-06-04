defmodule Archethic.Mining.LedgerValidation do
  @moduledoc """
  Calculate ledger operations requested by the transaction
  """

  alias Archethic.Contracts.Contract.Context, as: ContractContext
  alias Archethic.Contracts.Contract.State
  alias Archethic.Crypto
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  alias Archethic.TransactionChain.TransactionData

  @unit_uco 100_000_000

  defstruct state: :init,
            transaction_movements: [],
            unspent_outputs: [],
            fee: 0,
            consumed_inputs: [],
            inputs: [],
            minted_utxos: [],
            sufficient_funds?: false,
            balances: %{uco: 0, token: %{}},
            amount_to_spend: %{uco: 0, token: %{}}

  @typedoc """
  LedgerValidation should execute functions in a specific order.
  To avoid miss order, state is updated to ensure order is respected
  State is updated following
  - :init
  - :filtered_inputs
  - :utxos_minted
  - :sufficient_funds_validated
  - :inputs_consumed
  - :movements_resolved
  """
  @type state() ::
          :init
          | :filtered_inputs
          | :utxos_minted
          | :sufficient_funds_validated
          | :inputs_consumed
          | :movements_resolved

  @typedoc """
  - Transaction movements: represents the pending transaction ledger movements
  - Unspent outputs: represents the new unspent outputs
  - fee: represents the transaction fee
  - Consumed inputs: represents the list of inputs consumed to produce the unspent outputs
  """
  @type t() :: %__MODULE__{
          state: state(),
          transaction_movements: list(TransactionMovement.t()),
          unspent_outputs: list(UnspentOutput.t()),
          fee: non_neg_integer(),
          consumed_inputs: list(UnspentOutput.t()),
          inputs: list(UnspentOutput.t()),
          minted_utxos: list(UnspentOutput.t()),
          sufficient_funds?: boolean(),
          balances: %{uco: non_neg_integer(), token: map()},
          amount_to_spend: %{uco: non_neg_integer(), token: map()}
        }

  @burning_address <<0::8, 0::8, 0::256>>

  @doc """
  Return the address used for the burning
  """
  @spec burning_address() :: Crypto.versioned_hash()
  def burning_address, do: @burning_address

  @doc """
  Filter inputs that can be used in this transaction
  """
  @spec filter_usable_inputs(
          ops :: t(),
          inputs :: list(UnspentOutput.t()),
          contract_context :: ContractContext.t() | nil
        ) :: t()
  def filter_usable_inputs(%__MODULE__{state: :init} = ops, inputs, nil),
    do: next_state(%{ops | inputs: inputs})

  def filter_usable_inputs(%__MODULE__{state: :init} = ops, inputs, contract_context) do
    next_state(%{ops | inputs: ContractContext.ledger_inputs(contract_context, inputs)})
  end

  @doc """
  Build some ledger operations from a specific transaction
  """
  @spec mint_token_utxos(
          ops :: t(),
          tx :: Transaction.t(),
          validation_time :: DateTime.t()
        ) :: t()
  def mint_token_utxos(
        %__MODULE__{state: :filtered_inputs} = ops,
        %Transaction{address: address, type: type, data: %TransactionData{content: content}},
        timestamp
      )
      when type in [:token, :mint_rewards] and not is_nil(timestamp) do
    new_ops =
      case JSON.decode(content) do
        {:ok, json} ->
          %{ops | minted_utxos: create_token_utxos(json, address, timestamp)}

        _ ->
          ops
      end

    next_state(new_ops)
  end

  def mint_token_utxos(%__MODULE__{state: :filtered_inputs} = ops, _, _), do: next_state(ops)

  defp create_token_utxos(
         %{"token_reference" => token_ref, "supply" => supply},
         address,
         timestamp
       )
       when is_binary(token_ref) and is_integer(supply) do
    case Base.decode16(token_ref, case: :mixed) do
      {:ok, token_address} ->
        [
          %UnspentOutput{
            from: address,
            amount: supply,
            type: {:token, token_address, 0},
            timestamp: timestamp
          }
        ]

      _ ->
        []
    end
  end

  defp create_token_utxos(%{"type" => "fungible", "supply" => supply}, address, timestamp) do
    [
      %UnspentOutput{
        from: address,
        amount: supply,
        type: {:token, address, 0},
        timestamp: timestamp
      }
    ]
  end

  defp create_token_utxos(
         %{"type" => "non-fungible", "supply" => supply, "collection" => collection},
         address,
         timestamp
       ) do
    if length(collection) == supply / @unit_uco do
      collection
      |> Enum.with_index()
      |> Enum.map(fn {item_properties, index} ->
        token_id = Map.get(item_properties, "id", index + 1)

        %UnspentOutput{
          from: address,
          amount: 1 * @unit_uco,
          type: {:token, address, token_id},
          timestamp: timestamp
        }
      end)
    else
      []
    end
  end

  defp create_token_utxos(%{"type" => "non-fungible", "supply" => @unit_uco}, address, timestamp) do
    [
      %UnspentOutput{
        from: address,
        amount: 1 * @unit_uco,
        type: {:token, address, 1},
        timestamp: timestamp
      }
    ]
  end

  defp create_token_utxos(_, _, _), do: []

  @doc """
  Build the resolved view of the movement, with the resolved address
  and convert MUCO movement to UCO movement

  **MUST** be done after sufficient_funds? and consume_inputs
  """
  @spec build_resolved_movements(
          ops :: t(),
          resolved_addresses :: %{Crypto.prepended_hash() => Crypto.prepended_hash()},
          tx_type :: Transaction.transaction_type()
        ) :: t()
  def build_resolved_movements(
        %__MODULE__{state: :inputs_consumed, transaction_movements: movements} = ops,
        resolved_addresses,
        tx_type
      ) do
    resolved_movements =
      movements
      |> TransactionMovement.resolve_addresses(resolved_addresses)
      |> Enum.map(&TransactionMovement.maybe_convert_reward(&1, tx_type))
      |> TransactionMovement.aggregate()

    next_state(%{ops | transaction_movements: resolved_movements})
  end

  @doc """
  Determine if the transaction has enough funds for it's movements
  """
  @spec validate_sufficient_funds(ops :: t(), list(TransactionMovement.t())) :: t()
  def validate_sufficient_funds(
        %__MODULE__{state: :utxos_minted, fee: fee, inputs: inputs, minted_utxos: minted_utxos} =
          ops,
        movements
      ) do
    balances =
      %{uco: uco_balance, token: tokens_balance} = ledger_balances(inputs ++ minted_utxos)

    amount_to_spend =
      %{uco: uco_to_spend, token: tokens_to_spend} = total_to_spend(fee, movements)

    next_state(%{
      ops
      | sufficient_funds?:
          sufficient_funds?(uco_balance, uco_to_spend, tokens_balance, tokens_to_spend),
        balances: balances,
        amount_to_spend: amount_to_spend,
        transaction_movements: movements
    })
  end

  defp total_to_spend(fee, movements) do
    Enum.reduce(movements, %{uco: fee, token: %{}}, fn
      %TransactionMovement{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %TransactionMovement{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end

  defp ledger_balances(utxos) do
    Enum.reduce(utxos, %{uco: 0, token: %{}}, fn
      %UnspentOutput{type: :UCO, amount: amount}, acc ->
        Map.update!(acc, :uco, &(&1 + amount))

      %UnspentOutput{type: {:token, token_address, token_id}, amount: amount}, acc ->
        update_in(acc, [:token, Access.key({token_address, token_id}, 0)], &(&1 + amount))

      _, acc ->
        acc
    end)
  end

  defp sufficient_funds?(uco_balance, uco_to_spend, tokens_balance, tokens_to_spend) do
    uco_balance >= uco_to_spend and sufficient_tokens?(tokens_balance, tokens_to_spend)
  end

  defp sufficient_tokens?(%{} = tokens_received, %{} = token_to_spend)
       when map_size(tokens_received) == 0 and map_size(token_to_spend) > 0,
       do: false

  defp sufficient_tokens?(_tokens_received, tokens_to_spend) when map_size(tokens_to_spend) == 0,
    do: true

  defp sufficient_tokens?(tokens_received, tokens_to_spend) do
    Enum.all?(tokens_to_spend, fn {token_key, amount_to_spend} ->
      case Map.get(tokens_received, token_key) do
        nil ->
          false

        recv_amount ->
          recv_amount >= amount_to_spend
      end
    end)
  end

  @doc """
  Convert Mining LedgerOperations to ValidationStamp LedgerOperations
  """
  @spec to_ledger_operations(ops :: t()) :: LedgerOperations.t()
  def to_ledger_operations(%__MODULE__{
        state: :movements_resolved,
        transaction_movements: movements,
        unspent_outputs: utxos,
        fee: fee,
        consumed_inputs: consumed_inputs
      }) do
    %LedgerOperations{
      transaction_movements: movements,
      unspent_outputs: utxos,
      fee: fee,
      consumed_inputs: consumed_inputs
    }
  end

  @doc """
  Use the necessary inputs to satisfy the uco amount to spend
  The remaining unspent outputs will go to the change address
  Also return a boolean indicating if there was sufficient funds
  """
  @spec consume_inputs(
          ops :: t(),
          change_address :: binary(),
          timestamp :: DateTime.t(),
          encoded_state :: State.encoded() | nil,
          contract_context :: ContractContext.t() | nil
        ) :: t()
  def consume_inputs(
        ops,
        change_address,
        timestamp,
        encoded_state \\ nil,
        contract_context \\ nil
      )

  def consume_inputs(
        %__MODULE__{state: :sufficient_funds_validated, sufficient_funds?: false} = ops,
        _,
        _,
        _,
        _
      ),
      do: next_state(ops)

  def consume_inputs(
        %__MODULE__{
          state: :sufficient_funds_validated,
          inputs: inputs,
          minted_utxos: minted_utxos,
          balances: %{uco: uco_balance, token: tokens_balance},
          amount_to_spend: %{uco: uco_to_spend, token: tokens_to_spend}
        } = ops,
        change_address,
        %DateTime{} = timestamp,
        encoded_state,
        contract_context
      ) do
    # Since AEIP-19 we can consume from minted tokens
    # Sort inputs, to have consistent results across all nodes
    consolidated_inputs =
      minted_utxos
      |> Enum.map(fn utxo ->
        # As the minted tokens are used internally during transaction's validation
        # and doesn't not exists outside, we use the burning address
        # to identify inputs coming from the token's minting.
        %{utxo | from: burning_address()}
      end)
      |> Enum.concat(inputs)
      |> Enum.sort({:asc, UnspentOutput})

    consumed_utxos =
      get_inputs_to_consume(
        consolidated_inputs,
        uco_to_spend,
        tokens_to_spend,
        uco_balance,
        tokens_balance,
        contract_context
      )

    new_unspent_outputs =
      tokens_to_spend
      |> tokens_utxos(
        consumed_utxos,
        minted_utxos,
        change_address,
        timestamp
      )
      |> add_uco_utxo(consumed_utxos, uco_to_spend, change_address, timestamp)
      |> Enum.filter(&(&1.amount > 0))
      |> add_state_utxo(encoded_state, change_address, timestamp)

    next_state(%{ops | unspent_outputs: new_unspent_outputs, consumed_inputs: consumed_utxos})
  end

  defp tokens_utxos(tokens_to_spend, consumed_utxos, tokens_to_mint, change_address, timestamp) do
    tokens_minted_not_consumed =
      Enum.reject(tokens_to_mint, fn %UnspentOutput{type: {:token, token_address, token_id}} ->
        Map.has_key?(tokens_to_spend, {token_address, token_id})
      end)

    consumed_utxos
    |> Enum.group_by(& &1.type)
    |> Enum.filter(&match?({{:token, _, _}, _}, &1))
    |> Enum.reduce([], fn {{:token, token_address, token_id} = type, utxos}, acc ->
      amount_to_spend = Map.get(tokens_to_spend, {token_address, token_id}, 0)
      consumed_amount = Enum.sum_by(utxos, & &1.amount)
      remaining_amount = consumed_amount - amount_to_spend

      if remaining_amount > 0 do
        new_utxo = %UnspentOutput{
          from: change_address,
          amount: remaining_amount,
          type: type,
          timestamp: timestamp
        }

        [new_utxo | acc]
      else
        acc
      end
    end)
    |> Enum.concat(tokens_minted_not_consumed)
  end

  defp get_inputs_to_consume(
         inputs,
         uco_to_spend,
         tokens_to_spend,
         uco_balance,
         tokens_balance,
         contract_context
       ) do
    inputs
    # We group by type to count them and determine if we need to consume the inputs
    |> Enum.group_by(& &1.type)
    |> Enum.flat_map(fn
      {:UCO, inputs} ->
        get_uco_to_consume(inputs, uco_to_spend, uco_balance)

      {{:token, token_address, token_id}, inputs} ->
        key = {token_address, token_id}
        get_token_to_consume(inputs, key, tokens_to_spend, tokens_balance)

      {:state, state_utxos} ->
        state_utxos

      {:call, inputs} ->
        get_call_to_consume(inputs, contract_context)
    end)
  end

  defp get_uco_to_consume(inputs, uco_to_spend, uco_balance) when uco_to_spend > 0,
    do: optimize_inputs_to_consume(inputs, uco_to_spend, uco_balance)

  # The consolidation happens when there are at least more than one UTXO of the same type
  # This reduces the storage size on both genesis's inputs and further transactions
  defp get_uco_to_consume(inputs, _, _) when length(inputs) > 1, do: inputs
  defp get_uco_to_consume(_, _, _), do: []

  defp get_token_to_consume(inputs, key, tokens_to_spend, tokens_balance)
       when is_map_key(tokens_to_spend, key) do
    amount_to_spend = Map.get(tokens_to_spend, key)
    token_balance = Map.get(tokens_balance, key)
    optimize_inputs_to_consume(inputs, amount_to_spend, token_balance)
  end

  defp get_token_to_consume(inputs, _, _, _) when length(inputs) > 1, do: inputs
  defp get_token_to_consume(_, _, _, _), do: []

  defp get_call_to_consume(inputs, %ContractContext{trigger: {:transaction, address, _}}) do
    inputs
    |> Enum.find(&(&1.from == address))
    |> then(fn
      nil -> []
      contract_call_input -> [contract_call_input]
    end)
  end

  defp get_call_to_consume(_, _), do: []

  defp optimize_inputs_to_consume(inputs, _, _) when length(inputs) == 1, do: inputs

  defp optimize_inputs_to_consume(inputs, amount_to_spend, balance_amount)
       when balance_amount == amount_to_spend,
       do: inputs

  defp optimize_inputs_to_consume(inputs, amount_to_spend, balance_amount) do
    # Search if we can consume all inputs except one. This will avoid doing consolidation
    remaining_amount = balance_amount - amount_to_spend

    case Enum.find(inputs, &(&1.amount == remaining_amount)) do
      nil -> inputs
      input -> Enum.reject(inputs, &(&1 == input))
    end
  end

  defp add_uco_utxo(utxos, consumed_utxos, uco_to_spend, change_address, timestamp) do
    consumed_amount =
      consumed_utxos |> Enum.filter(&(&1.type == :UCO)) |> Enum.sum_by(& &1.amount)

    remaining_amount = consumed_amount - uco_to_spend

    if remaining_amount > 0 do
      new_utxo = %UnspentOutput{
        from: change_address,
        amount: remaining_amount,
        type: :UCO,
        timestamp: timestamp
      }

      [new_utxo | utxos]
    else
      utxos
    end
  end

  defp add_state_utxo(utxos, nil, _change_address, _timestamp), do: utxos

  defp add_state_utxo(utxos, encoded_state, change_address, timestamp) do
    new_utxo = %UnspentOutput{
      type: :state,
      encoded_payload: encoded_state,
      timestamp: timestamp,
      from: change_address
    }

    [new_utxo | utxos]
  end

  defp next_state(%__MODULE__{state: :init} = ops), do: %{ops | state: :filtered_inputs}

  defp next_state(%__MODULE__{state: :filtered_inputs} = ops), do: %{ops | state: :utxos_minted}

  defp next_state(%__MODULE__{state: :utxos_minted} = ops),
    do: %{ops | state: :sufficient_funds_validated}

  defp next_state(%__MODULE__{state: :sufficient_funds_validated} = ops),
    do: %{ops | state: :inputs_consumed}

  defp next_state(%__MODULE__{state: :inputs_consumed} = ops),
    do: %{ops | state: :movements_resolved}
end
