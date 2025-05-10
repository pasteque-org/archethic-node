defmodule Archethic.TransactionChain.DBLedger do
  @moduledoc """
  Manage DB for transaction's chain
  """

  alias Archethic.TransactionChain.TransactionInput

  use Knigge, otp_app: :archethic, default: __MODULE__.FileImpl

  @callback write_inputs(binary(), list(TransactionInput.t())) :: :ok
  @callback stream_inputs(binary()) :: Enumerable.t() | list(TransactionInput.t())
end
