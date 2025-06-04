defmodule Archethic.Contracts.Interpreter.Legacy.UtilsInterpreter do
  @moduledoc false

  alias Archethic.Contracts.Interpreter.Legacy.Library
  alias Archethic.Contracts.Interpreter.Legacy.TransactionStatements
  alias Archethic.Crypto

  @library_functions_names :functions
                           |> Library.__info__()
                           |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @library_functions_names_atoms :functions
                                 |> Library.__info__()
                                 |> Map.new(&{Atom.to_string(elem(&1, 0)), elem(&1, 0)})

  @transaction_statements_functions_names :functions
                                          |> TransactionStatements.__info__()
                                          |> Enum.map(&Atom.to_string(elem(&1, 0)))

  @transaction_statements_functions_names_atoms :functions
                                                |> TransactionStatements.__info__()
                                                |> Map.new(
                                                  &{Atom.to_string(elem(&1, 0)), elem(&1, 0)}
                                                )

  @supported_hash Archethic.Crypto.list_supported_hash_functions(:string)

  @transaction_fields [
    "address",
    "type",
    "timestamp",
    "previous_signature",
    "previous_public_key",
    "origin_signature",
    "content",
    "keys",
    "code",
    "uco_ledger",
    "token_ledger",
    "uco_transfers",
    "token_transfers",
    "authorized_public_keys",
    "secrets",
    "recipients"
  ]

  @spec transaction_fields() :: list(String.t())
  def transaction_fields, do: @transaction_fields

  @spec prewalk(Macro.t(), any()) :: {Macro.t(), any()}
  def prewalk(:atom = node, acc), do: {node, acc}
  def prewalk({:atom, key} = node, acc) when is_binary(key), do: {node, acc}

  def prewalk({{:atom, key}, _, nil} = node, {:ok, _} = acc) when is_binary(key), do: {node, acc}

  def prewalk(node, acc) when is_list(node), do: {node, acc}

  # Whitelist operators
  def prewalk({:+, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:-, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:/, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:*, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:>, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:<, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:>=, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:<=, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:|>, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:==, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  # Whitelist the use of doted statement
  def prewalk({{:., _, [{_, _, _}, _]}, _, []} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root,
      do: {node, acc}

  def prewalk({:if, _, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk({:else, _} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk([do: _, else: _] = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk(:else = node, {:ok, %{scope: scope}} = acc) when scope != :root, do: {node, acc}

  def prewalk({:and, _, _} = node, {:ok, _} = acc), do: {node, acc}
  def prewalk({:or, _, _} = node, {:ok, _} = acc), do: {node, acc}

  # Whitelist the in operation
  def prewalk({:in, _, [_, _]} = node, {:ok, _} = acc), do: {node, acc}

  # Whitelist maps
  def prewalk({:%{}, _, fields} = node, {:ok, _} = acc) when is_list(fields), do: {node, acc}

  def prewalk({key, _val} = node, acc) when is_binary(key) do
    {node, acc}
  end

  # Whitelist the multiline
  def prewalk({{:__block__, _, _}} = node, {:ok, _} = acc) do
    {node, acc}
  end

  def prewalk({:__block__, _, _} = node, {:ok, _} = acc) do
    {node, acc}
  end

  # Whitelist interpolation of strings
  def prewalk(
        {:<<>>, _, [{:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, {:binary, _, nil}]}, _]} =
          node,
        acc
      ) do
    {node, acc}
  end

  def prewalk({:<<>>, _, [_, {:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]}]} = node, acc) do
    {node, acc}
  end

  def prewalk({:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]} = node, acc) do
    {node, acc}
  end

  def prewalk({{:., _, [Kernel, :to_string]}, _, _} = node, acc) do
    {node, acc}
  end

  def prewalk({:., _, [Kernel, :to_string]} = node, acc) do
    {node, acc}
  end

  def prewalk(Kernel = node, acc), do: {node, acc}
  def prewalk(:to_string = node, acc), do: {node, acc}
  def prewalk({:binary, _, nil} = node, acc), do: {node, acc}

  # Whitelist generics
  def prewalk(true, {:ok, _} = acc), do: {true, acc}
  def prewalk(false, {:ok, _} = acc), do: {false, acc}
  def prewalk(number, {:ok, _} = acc) when is_number(number), do: {number, acc}
  def prewalk(string, {:ok, _} = acc) when is_binary(string), do: {string, acc}
  def prewalk([do: _] = node, {:ok, _} = acc), do: {node, acc}
  def prewalk({:do, _} = node, {:ok, _} = acc), do: {node, acc}
  def prewalk(:do = node, {:ok, _} = acc), do: {node, acc}

  # Whitelist the use of list
  def prewalk([{{:atom, _}, _, nil} | _] = node, {:ok, %{scope: scope}} = acc)
      when scope != :root do
    {node, acc}
  end

  # Whitelist access to map field
  def prewalk({{:., _, [Access, :get]}, _, _} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root do
    {node, acc}
  end

  def prewalk({:., _, [Access, :get]} = node, {:ok, %{scope: scope}} = acc) when scope != :root,
    do: {node, acc}

  def prewalk(Access = node, acc), do: {node, acc}
  def prewalk(:get = node, acc), do: {node, acc}

  # Whitelist the usage of transaction fields in references: "transaction/contract/previous/next"
  def prewalk(
        {:., _, [{{:atom, transaction_ref}, _, nil}, {:atom, transaction_field}]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root and transaction_ref in ["next", "previous", "transaction", "contract"] and
             transaction_field in @transaction_fields do
    {node, acc}
  end

  def prewalk(
        {{:atom, _}, {{:., _, [{{:atom, transaction_ref}, _, nil}, {:atom, type}]}, _, _}} = node,
        acc
      )
      when transaction_ref in ["next", "previous", "transaction", "contract"] and
             type in @transaction_fields do
    {node, acc}
  end

  # Whitelist the size/1 function
  def prewalk({{:atom, "size"}, _, [_data]} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root do
    {node, acc}
  end

  # Whitelist the hash/1 function
  def prewalk({{:atom, "hash"}, _, [_data]} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root,
      do: {node, acc}

  # Whitelist the hash/2 function
  def prewalk({{:atom, "hash"}, _, [_data, algo]} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root and algo in @supported_hash,
      do: {node, acc}

  # Whitelist the regex_match?/2 function
  def prewalk(
        {{:atom, "regex_match?"}, _, [_input, _search]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the regex_extract/2 function
  def prewalk(
        {{:atom, "regex_extract"}, _, [_input, _search]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the json_path_extract/2 function
  def prewalk(
        {{:atom, "json_path_extract"}, _, [_input, _search]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the json_path_match?/2 function
  def prewalk(
        {{:atom, "json_path_match?"}, _, [_input, _search]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root,
      do: {node, acc}

  # Whitelist the get_genesis_address/1 function
  def prewalk(
        {{:atom, "get_genesis_address"}, _, [_address]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the get_first_address/1 function
  def prewalk(
        {{:atom, "get_first_transaction_address"}, _, [_address]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the get_genesis_public_key/1 function
  def prewalk(
        {{:atom, "get_genesis_public_key"}, _, [_address]} = node,
        {:ok, %{scope: scope}} = acc
      )
      when scope != :root do
    {node, acc}
  end

  # Whitelist the get_token_id/1 function
  def prewalk({{:atom, "get_token_id"}, _, [_address]} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root do
    {node, acc}
  end

  # Whitelist the timestamp/0 function in condition
  def prewalk({{:atom, "timestamp"}, _, _} = node, {:ok, %{scope: scope}} = acc)
      when scope != :root do
    {node, acc}
  end

  # Blacklist everything else
  def prewalk(node, _acc) do
    throw({:error, node})
  end

  @spec postwalk(Macro.t(), any()) :: {Macro.t(), any()}
  def postwalk({{:atom, fun}, _, _} = node, {:ok, %{scope: {:function, _, scope}} = context})
      when fun in @library_functions_names or fun in @transaction_statements_functions_names do
    {node, {:ok, %{context | scope: scope}}}
  end

  def postwalk(
        {{:., meta1, [Access, :get]}, meta2,
         [{{:., meta3, [{subject, meta4, nil}, {:atom, field}]}, meta5, []}, {:atom, key}]},
        {:ok, _} = acc
      ) do
    {
      {{:., meta1, [Access, :get]}, meta2,
       [
         {{:., meta3, [{subject, meta4, nil}, String.to_existing_atom(field)]}, meta5, []},
         Base.decode16!(key, case: :mixed)
       ]},
      acc
    }
  end

  # Convert map key to binary
  def postwalk({:%{}, meta, params}, {:ok, _} = acc) do
    encoded_params =
      Enum.map(params, fn
        {{:atom, key}, value} when is_binary(key) ->
          case Base.decode16(key, case: :mixed) do
            {:ok, bin} ->
              {bin, value}

            :error ->
              {key, value}
          end

        {key, value} ->
          {key, value}
      end)

    {{:%{}, meta, encoded_params}, acc}
  end

  def postwalk(node, acc) when is_binary(node) do
    if String.printable?(node) do
      # uniform hexadecimal to all uppercase
      case Base.decode16(node, case: :mixed) do
        {:ok, hex} ->
          {Base.encode16(hex), acc}

        _ ->
          {node, acc}
      end
    else
      {node, acc}
    end
  end

  def postwalk(node, acc), do: {node, acc}

  @doc """
  Inject context variables and functions by transforming the ast
  """
  @spec inject_bindings_and_functions(Macro.t(), list()) :: Macro.t()
  def inject_bindings_and_functions(quoted_code, opts) when is_list(opts) do
    bindings = Keyword.get(opts, :bindings, %{})
    subject = Keyword.get(opts, :subject)

    {ast, _} =
      Macro.postwalk(
        quoted_code,
        %{
          bindings: bindings,
          library_functions: @library_functions_names,
          transaction_statements_functions: @transaction_statements_functions_names,
          subject: subject
        },
        &do_postwalk_execution/2
      )

    ast
  end

  @doc """
  Decode an hexadecimal binary or no-op
  """
  @spec maybe_decode_hex(binary()) :: binary()
  def maybe_decode_hex(bin) do
    if String.match?(bin, ~r/^[[:xdigit:]]+$/) do
      case Base.decode16(bin, case: :mixed) do
        {:ok, bin} -> bin
        :error -> bin
      end
    else
      bin
    end
  end

  defp do_postwalk_execution({:=, metadata, [var_name, content]}, acc) do
    put_ast =
      {{:., metadata, [{:__aliases__, metadata, [:Map]}, :put]}, metadata,
       [{:scope, metadata, nil}, var_name, content]}

    {
      {:=, metadata, [{:scope, metadata, nil}, put_ast]},
      put_in(acc, [:bindings, var_name], content)
    }
  end

  defp do_postwalk_execution({{:atom, atom}, metadata, args} = _node, acc)
       when atom in @library_functions_names do
    fun = Map.get(@library_functions_names_atoms, atom)

    {{{:., metadata, [{:__aliases__, [alias: Library], [:Library]}, fun]}, metadata, args}, acc}
  end

  defp do_postwalk_execution({{:atom, atom}, metadata, args} = _node, acc)
       when atom in @transaction_statements_functions_names do
    args =
      Enum.map(args, fn arg ->
        {ast, _} = Macro.postwalk(arg, acc, &do_postwalk_execution/2)
        ast
      end)

    fun = Map.get(@transaction_statements_functions_names_atoms, atom)

    ast = {
      {:., metadata,
       [
         {:__aliases__, [alias: TransactionStatements], [:TransactionStatements]},
         fun
       ]},
      metadata,
      [{:&, metadata, [1]} | args]
    }

    update_ast =
      {:update_in, metadata,
       [
         {:scope, metadata, nil},
         ["next_transaction"],
         {:&, metadata,
          [
            ast
          ]}
       ]}

    {
      {:__block__, [],
       [
         {:=, metadata, [{:scope, metadata, nil}, update_ast]},

         # Remove warnings about unused scope by calling Function.identity(scope)
         {{:., [], [{:__aliases__, [alias: false], [:Function]}, :identity]}, [],
          [{:scope, [], nil}]}
       ]},
      acc
    }
  end

  defp do_postwalk_execution(
         {{:atom, atom}, metadata, _args} = _node,
         %{bindings: bindings, subject: subject} = acc
       ) do
    if Map.has_key?(bindings, atom) do
      search =
        case subject do
          nil ->
            [atom]

          subject ->
            # Do not use the subject when using reserved keyword
            if atom in ["contract", "transaction", "next", "previous"] do
              [atom]
            else
              [subject, atom]
            end
        end

      {
        {:get_in, metadata, [{:scope, metadata, nil}, search]},
        acc
      }
    else
      {atom, acc}
    end
  end

  defp do_postwalk_execution({:., metadata, [parent, {{:atom, field}}]}, acc) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, [parent, field]]},
      acc
    }
  end

  defp do_postwalk_execution(
         {:., _, [{:get_in, metadata, [{:scope, _, nil}, access]}, {:atom, field}]},
         acc
       ) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, Enum.concat(access, [field])]},
      acc
    }
  end

  defp do_postwalk_execution(
         {:., metadata,
          [{:get_in, metadata, [{:scope, metadata, nil}, [parent]]}, {:atom, child}]},
         acc
       ) do
    {{:get_in, metadata, [{:scope, metadata, nil}, [parent, child]]}, acc}
  end

  defp do_postwalk_execution({{:atom, atom}, val}, acc) do
    {ast, _} = Macro.postwalk(val, acc, &do_postwalk_execution/2)
    {{atom, ast}, acc}
  end

  defp do_postwalk_execution({{:get_in, metadata, [{:scope, metadata, nil}, access]}, _, []}, acc) do
    {
      {:get_in, metadata, [{:scope, metadata, nil}, access]},
      acc
    }
  end

  defp do_postwalk_execution({:==, _, [{left, _, args_l}, {right, _, args_r}]}, acc) do
    {{:==, [], [{left, [], args_l}, {right, [], args_r}]}, acc}
  end

  defp do_postwalk_execution({:==, _, [{left, _, args}, right]}, acc) do
    {{:==, [], [{left, [], args}, right]}, acc}
  end

  defp do_postwalk_execution({node, _, _}, acc) when is_binary(node) do
    {node, acc}
  end

  defp do_postwalk_execution(node, acc), do: {node, acc}

  @doc """
  Gets an valid address as true binary from string term or from true binary <<>>.
  Multiple branching required, ecto type impl adopted. May use ecto itself.String
  are binary encode terms, and so are true binary.To differentiate between the two,
  we check if the string is printable.
  """
  def get_address(address, context) when is_binary(address) do
    address =
      if String.printable?(address) do
        case Base.decode16(address, case: :mixed) do
          {:ok, addr_bin} ->
            addr_bin

          _ ->
            raise "Invalid address in #{inspect(context)}"
        end
      else
        address
      end

    if Crypto.valid_address?(address) do
      address
    else
      raise "Invalid address in #{inspect(context)}"
    end
  end

  def get_address(_address, context), do: raise("Invalid address in #{inspect(context)}")

  def get_public_key(public_key, context) do
    public_key =
      if String.printable?(public_key) do
        case Base.decode16(public_key, case: :mixed) do
          {:ok, key_bin} ->
            key_bin

          _ ->
            raise "Invalid public key in #{inspect(context)}"
        end
      else
        public_key
      end

    if Crypto.valid_public_key?(public_key) do
      public_key
    else
      raise "Invalid public key in #{inspect(context)}"
    end
  end
end
