defmodule Archethic.Contracts.Interpreter.CommonInterpreter do
  @moduledoc """
  The prewalk and postwalk functions receive an `acc` for convenience.
  They should see it as an opaque variable and just forward it.

  This way we can use this interpreter inside other interpreters, and each deal with the acc how they want to.
  """

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.FunctionKeys
  alias Archethic.Contracts.Interpreter.Library
  alias Archethic.Contracts.Interpreter.Library.ErrorContractThrow
  alias Archethic.Contracts.Interpreter.Scope

  # ----------------------------------------------------------------------
  #                                _ _
  #   _ __  _ __ _____      ____ _| | | __
  #  | '_ \| '__/ _ \ \ /\ / / _` | | |/ /
  #  | |_) | | |  __/\ V  V | (_| | |   <
  #  | .__/|_|  \___| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # the atom marker (set by sanitize_code)
  def prewalk(:atom, acc), do: {:atom, acc}

  # expressions
  def prewalk({:+, _, _} = node, acc), do: {node, acc}
  def prewalk({:-, _, _} = node, acc), do: {node, acc}
  def prewalk({:/, _, _} = node, acc), do: {node, acc}
  def prewalk({:*, _, _} = node, acc), do: {node, acc}
  def prewalk({:>, _, _} = node, acc), do: {node, acc}
  def prewalk({:<, _, _} = node, acc), do: {node, acc}
  def prewalk({:>=, _, _} = node, acc), do: {node, acc}
  def prewalk({:<=, _, _} = node, acc), do: {node, acc}
  def prewalk({:|>, _, _} = node, acc), do: {node, acc}
  def prewalk({:==, _, _} = node, acc), do: {node, acc}
  def prewalk({:!=, _, _} = node, acc), do: {node, acc}
  def prewalk({:++, _, _} = node, acc), do: {node, acc}
  def prewalk({:!, _, _} = node, acc), do: {node, acc}
  def prewalk({:&&, _, _} = node, acc), do: {node, acc}
  def prewalk({:||, _, _} = node, acc), do: {node, acc}

  # ranges
  def prewalk({:.., _, _} = node, acc), do: {node, acc}

  # enter block == new scope
  def prewalk({:__block__, meta, expressions} = _node, acc) do
    # create the child scope in parent scope
    create_scope_ast =
      quote do
        Scope.create()
      end

    {
      {:__block__, meta, [create_scope_ast | expressions]},
      acc
    }
  end

  # blocks
  def prewalk({:do, _} = node, acc), do: {node, acc}
  def prewalk(:do = node, acc), do: {node, acc}

  # literals
  # it is fine allowing atoms since the users can't create them (this avoid whitelisting functions/modules we use in the prewalk)
  def prewalk(node, acc) when is_atom(node), do: {node, acc}
  def prewalk(node, acc) when is_boolean(node), do: {node, acc}
  def prewalk(node, acc) when is_number(node), do: {node, acc}
  def prewalk(node, acc) when is_binary(node), do: {node, acc}

  # converts all keywords to maps
  def prewalk(node, acc) when is_list(node) do
    if AST.is_keyword_list?(node) do
      new_node = AST.keyword_to_map(node)

      {new_node, acc}
    else
      {node, acc}
    end
  end

  # pairs (used in maps)
  def prewalk({key, _} = node, acc) when is_binary(key), do: {node, acc}

  # maps (required because we create maps for each scope in the ActionInterpreter's prewalk)
  def prewalk({:%{}, _, _} = node, acc), do: {node, acc}

  # variables
  def prewalk({{:atom, var_name}, _, nil} = node, acc) when is_binary(var_name), do: {node, acc}
  def prewalk({:atom, var_name} = node, acc) when is_binary(var_name), do: {node, acc}

  def prewalk({{:., _, [{:__aliases__, _, [atom]}, _]}, _, _} = node, acc) when is_atom(atom),
    do: {node, acc}

  def prewalk({:., _, [{:__aliases__, _, _}, _]} = node, acc), do: {node, acc}
  def prewalk({:__aliases__, _, [atom: _module_name]} = node, acc), do: {node, acc}

  # internal modules (Process/Scope/Kernel)
  def prewalk({:__aliases__, _, [atom]} = node, acc) when is_atom(atom), do: {node, acc}

  # internal functions
  def prewalk({:put_in, _, _} = node, acc), do: {node, acc}
  def prewalk({:get_in, _, _} = node, acc), do: {node, acc}
  def prewalk({:update_in, _, _} = node, acc), do: {node, acc}

  # if
  def prewalk({:if, meta, [predicate, do_else_keyword]} = _node, acc) do
    # wrap the do/else blocks
    do_else_keyword =
      Enum.map(do_else_keyword, fn {key, value} ->
        {key, AST.wrap_in_block(value)}
      end)

    new_node = {:if, meta, [predicate, do_else_keyword]}
    {new_node, acc}
  end

  # else (no wrap needed since it's done in the if)
  def prewalk({:else, _} = node, acc), do: {node, acc}
  def prewalk(:else = node, acc), do: {node, acc}

  # string interpolation
  def prewalk({{:., _, [Kernel, :to_string]}, _, _} = node, acc), do: {node, acc}
  def prewalk({:., _, [Kernel, :to_string]} = node, acc), do: {node, acc}
  def prewalk({:binary, _, nil} = node, acc), do: {node, acc}
  def prewalk({:<<>>, _, _} = node, acc), do: {node, acc}
  def prewalk({:"::", _, [{{:., _, [Kernel, :to_string]}, _, _}, _]} = node, acc), do: {node, acc}

  # forbid "if" as an expression
  def prewalk({:=, _, [_, {:if, _, _}]} = node, _acc) do
    throw({:error, node, "Forbidden to use if as an expression."})
  end

  # forbid "for" as an expression
  def prewalk({:=, _, [{{:atom, _}, _, nil}, {{:atom, "for"}, _, _}]} = node, _acc) do
    throw({:error, node, "Forbidden to use for as an expression."})
  end

  # whitelist assignation & write them to scope
  # this is done in the prewalk because it must be done before the "variable are read from scope" step
  def prewalk({:=, meta, [{{:atom, var_name}, _, nil}, value]} = _node, acc) do
    value = try_unquote(value)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Scope.write_cascade(unquote(var_name), unquote(value))
      end

    {
      new_node,
      acc
    }
  end

  # Dot access non-nested (x.y)
  def prewalk({{:., meta, [{{:atom, map_name}, _, nil}, {:atom, key_name}]}, _, _} = _node, acc) do
    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Scope.read(unquote(map_name), unquote(key_name))
      end

    {new_node, acc}
  end

  # Dot access non-nested (x.y)
  def prewalk(
        {:{}, [:escape],
         [:., meta, [{:{}, [:escape], [{:atom, map_name}, _, nil]}, {:atom, key_name}]]} = _node,
        acc
      ) do
    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Scope.read(unquote(map_name), unquote(key_name))
      end

    {new_node, acc}
  end

  # Dot access nested (x.y.z)
  # or Module.function().z
  def prewalk({{:., meta, [first_arg, {:atom, key_name}]}, _, []}, acc) do
    first_arg = try_unquote(first_arg)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Map.get(unquote(first_arg), unquote(key_name))
      end

    {new_node, acc}
  end

  # Map access non-nested (x[y])
  def prewalk(
        {{:., meta, [Access, :get]}, _, [{{:atom, map_name}, _, nil}, accessor]} = _node,
        acc
      ) do
    # accessor can be a variable, a function call, a dot access, a string
    accessor = try_unquote(accessor)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Scope.read(unquote(map_name), unquote(accessor))
      end

    {new_node, acc}
  end

  # Map access nested (x[y][z])
  def prewalk({{:., meta, [Access, :get]}, _, [first_arg, accessor]} = _node, acc) do
    first_arg = try_unquote(first_arg)
    accessor = try_unquote(accessor)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Map.get(unquote(first_arg), unquote(accessor))
      end

    {new_node, acc}
  end

  # for var in list
  def prewalk(
        {{:atom, "for"}, meta, [{:in, _, [{{:atom, var_name}, _, nil}, list]}, [do: block]]} =
          _node,
        acc
      ) do
    ast =
      {{:atom, "for"}, meta,
       [
         # we change the "var in list" to "var: list" (which will be automatically converted to %{var => list})
         # to avoid the "var" interpreted as a variable (which would have been converted to get_in/2)
         [{{:atom, var_name}, list}],
         # wrap in a block to be able to pattern match it to create a scope
         [do: AST.wrap_in_block(block)]
       ]}

    {ast, acc}
  end

  # log (not documented, only useful for developer debugging)
  # TODO: should be implemented in a module Logger (only available if config allows it)
  # will soon be updated to log into the playground console
  def prewalk({{:atom, "log"}, meta, [data]} = _node, acc) do
    data = try_unquote(data)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        arg = [unquote(data)]
        apply(IO, :inspect, args)
      end

    {new_node, acc}
  end

  # throw
  def prewalk({{:atom, "throw"}, _meta, [args]} = node, acc) when is_list(args) do
    args = Map.new(args)
    {code, args} = Map.pop(args, {:atom, "code"})
    {message, args} = Map.pop(args, {:atom, "message"})
    {_data, args} = Map.pop(args, {:atom, "data"})

    if map_size(args) > 0 do
      invalid_keys = args |> Map.keys() |> Enum.map_join(",", &elem(&1, 1))
      throw({:error, node, "Invalid throw params: #{invalid_keys}"})
    end

    if code == nil, do: throw({:error, node, "Throw must have a code"})
    if not is_integer(code), do: throw({:error, node, "Throw code must be an integer"})
    if message == nil, do: throw({:error, node, "Throw must have a message"})
    if not is_binary(message), do: throw({:error, node, "Throw message must be a string"})

    {node, acc}
  end

  # function call, should be placed after "for" prewalk
  def prewalk({{:atom, function_name}, _, args} = node, %{functions: functions} = acc)
      when is_list(args) do
    arity = length(args)

    if FunctionKeys.exist?(functions, function_name, arity) do
      {node, acc}
    else
      throw({:error, node, "The function #{function_name}/#{arity} does not exist"})
    end
  end

  def prewalk({:{}, [:escape], [new_node, meta, value]} = _node, acc) do
    {{new_node, meta, value}, acc}
  end

  # blacklist rest
  def prewalk(node, _acc), do: throw({:error, node, "unexpected term"})

  # ----------------------------------------------------------------------
  #                   _                 _ _
  #   _ __   ___  ___| |___      ____ _| | | __
  #  | '_ \ / _ \/ __| __\ \ /\ / / _` | | |/ /
  #  | |_) | (_) \__ | |_ \ V  V | (_| | |   <
  #  | .__/ \___/|___/\__| \_/\_/ \__,_|_|_|\_\
  #  |_|
  # ----------------------------------------------------------------------
  # exit block == set parent scope
  # we need to return user's last expression and not the result of Scope.leave_scope()
  # ps: there is no meta in a :__block__
  def postwalk({:__block__, [], expressions} = _node, acc) do
    {last_expression, expressions} = List.pop_at(expressions, -1)

    last_expression = try_unquote(last_expression)

    {:__block__, [], new_expressions} =
      quote do
        result = unquote(last_expression)
        Scope.leave_scope()
        result
      end

    {{:__block__, [], expressions ++ new_expressions}, acc}
  end

  # Module function call
  def postwalk(
        {{:., meta, [{:__aliases__, _, [atom: module_name]}, {:atom, function_name}]}, _, args} =
          node,
        acc
      ) do
    # Module and function has already been verified
    module = Library.get_module!(module_name)
    function = String.to_existing_atom(function_name)

    # check the type of the args
    if !module.check_types(function, args) do
      throw({:error, node, "invalid function arguments"})
    end

    args = try_unquote(args)

    new_node =
      if Library.function_tagged_with?(module_name, function_name, :write_contract) do
        quote line: Keyword.fetch!(meta, :line) do
          # mark the next_tx as dirty
          Scope.update_global([:next_transaction_changed], fn _ -> true end)

          # call the function with the next_transaction as the 1st argument
          # and update it in the scope
          Scope.update_global([:next_transaction], fn tx ->
            apply(unquote(module), unquote(function), [tx | unquote(args)])
          end)
        end
      else
        meta_with_alias = Keyword.put(meta, :alias, module)

        {{:., meta, [{:__aliases__, meta_with_alias, [module]}, function]}, meta, args}
      end

    {new_node, acc}
  end

  # variable are read from scope
  def postwalk({{:atom, var_name}, meta, nil} = _node, acc) do
    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Scope.read(unquote(var_name))
      end

    {new_node, acc}
  end

  # for var in list
  def postwalk({{:atom, "for"}, meta, [{:%{}, _, [{var_name, list}]}, [do: block]]} = _node, acc) do
    # FIXME: here acc is already the parent acc, it is not the acc of the do block
    # FIXME: this means that our `var_name` will live in the parent scope
    # FIXME: it works (since we can read from parent) but it will override the parent binding if there's one

    # transform the for-loop into Enum.each
    # and create a variable in the scope
    block = try_unquote(block)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Enum.each(unquote(list), fn x ->
          Scope.write_at(unquote(var_name), x)

          unquote(block)
        end)
      end

    {new_node, acc}
  end

  def postwalk({{:atom, "throw"}, meta, [{:%{}, _, args}]}, acc) when is_list(args) do
    args = Map.new(args)
    code = Map.get(args, "code")
    message = Map.get(args, "message")
    data = Map.get(args, "data")

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        raise ErrorContractThrow,
          code: unquote(code),
          message: unquote(message),
          data: unquote(data)
      end

    {new_node, acc}
  end

  def postwalk({{:atom, function_name}, meta, args}, acc) when is_list(args) do
    args = try_unquote(args)

    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        Scope.execute_function_ast(unquote(function_name), unquote(args))
      end

    {new_node, acc}
  end

  # BigInt mathematics to avoid floating point issues
  def postwalk({ast, meta, [lhs, rhs]} = _node, acc) when ast in [:*, :/, :+, :-] do
    new_node =
      quote line: Keyword.fetch!(meta, :line) do
        AST.decimal_arithmetic(unquote(ast), unquote(lhs), unquote(rhs))
      end

    {new_node, acc}
  end

  # whitelist rest
  def postwalk(node, acc), do: {node, acc}

  def try_unquote(value) do
    quote do
      unquote(value)
    end

    value
  rescue
    _ ->
      value |> Macro.escape() |> add_escape_meta()
  end

  defp add_escape_meta({:{}, _, node}), do: {:{}, [:escape], add_escape_meta(node)}
  defp add_escape_meta(list) when is_list(list), do: Enum.map(list, &add_escape_meta/1)

  defp add_escape_meta(tuple) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&add_escape_meta/1) |> List.to_tuple()

  defp add_escape_meta(value), do: value
end
