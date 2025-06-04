defmodule ArchethicWeb.API.FunctionCallPayload do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset

  alias ArchethicWeb.API.Types.Address
  alias ArchethicWeb.API.Types.RecipientArgType

  embedded_schema do
    field(:contract, Address)
    field(:function, :string)
    field(:args, RecipientArgType)
    field(:resolve_last, :boolean)
  end

  def changeset(%{} = params) do
    %__MODULE__{}
    |> cast(params, [:contract, :function, :args, :resolve_last])
    |> validate_required([:contract, :function])
  end
end
