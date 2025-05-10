defmodule Archethic.UTXO.DBLedger do
  @moduledoc false

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  use Knigge, otp_app: :archethic, default: __MODULE__.FileImpl

  @callback append(binary(), UnspentOutput.t()) :: :ok
  @callback append_list(binary(), list(UnspentOutput.t())) :: :ok
  @callback flush(binary(), list(UnspentOutput)) :: :ok
  @callback stream(binary()) :: list(UnspentOutput) | Enumerable.t()
  @callback list_genesis_addresses() :: list(binary())
end
