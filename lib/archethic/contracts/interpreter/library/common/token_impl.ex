defmodule Archethic.Contracts.Interpreter.Library.Common.TokenImpl do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library.Common.Token

  use Archethic.Tag

  alias Archethic.Contracts.Interpreter.Legacy

  @tag [:io]
  @impl Archethic.Contracts.Interpreter.Library.Common.Token
  defdelegate fetch_id_from_address(address),
    to: Legacy.Library,
    as: :get_token_id
end
