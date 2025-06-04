defmodule Archethic.Contracts.Wasm.IO do
  @moduledoc """
  Query some data of the blockchain from the SC
  """
  use Knigge, otp_app: :archethic, default: __MODULE__.JSONRPCImpl

  alias Archethic.Contracts.Wasm.Result

  defmodule Request do
    @moduledoc false

    @type t :: %{
            method: String.t(),
            params: term()
          }
    defstruct [:method, :params]
  end

  @callback request(request :: Request.t(), opts :: Keyword.t()) :: Result.t()
end
