%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "mix.exs",
          "lib/",
          "src/",
          "test/",
          "web/",
          "apps/*/lib/",
          "apps/*/src/",
          "apps/*/test/",
          "apps/*/web/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      requires: ["./lib/checks/*.exs"],
      strict: true,
      color: true,
      checks: %{
        enabled: [
          # Custom checks
          {Archethic.Checks.AtVsn, []},
          {Archethic.Checks.NamedSupervisor, []},

          #
          ## Consistency Checks
          #
          # {Credo.Check.Consistency.ExceptionNames, []},
          # {Credo.Check.Consistency.LineEndings, []},
          # {Credo.Check.Consistency.SpaceAroundOperators, []},
          # {Credo.Check.Consistency.SpaceInParentheses, []},
          # {Credo.Check.Consistency.TabsOrSpaces, []},

          #
          ## Design Checks
          #
          # {Credo.Check.Design.DuplicatedCode, []},
          # {Credo.Check.Design.TagFIXME, []},
          # {Credo.Check.Design.TagTODO, [exit_status: 2]},

          #
          ## Readability Checks
          #
          # {Credo.Check.Readability.BlockPipe, []},
          # {Credo.Check.Readability.FunctionNames, []},
          # {Credo.Check.Readability.ImplTrue, []},
          # {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          # {Credo.Check.Readability.ModuleAttributeNames, []},
          # {Credo.Check.Readability.ModuleNames, []},
          # {Credo.Check.Readability.NestedFunctionCalls, []},
          # {Credo.Check.Readability.ParenthesesInCondition, []},
          # {Credo.Check.Readability.PredicateFunctionNames, []},
          # {Credo.Check.Readability.RedundantBlankLines, []},
          # {Credo.Check.Readability.Semicolons, []},
          # {Credo.Check.Readability.SeparateAliasRequire, []},
          # {Credo.Check.Readability.SingleFunctionToBlockPipe, []},
          # {Credo.Check.Readability.SpaceAfterCommas, []},
          # {Credo.Check.Readability.Specs, []},
          # {Credo.Check.Readability.TrailingBlankLine, []},
          # {Credo.Check.Readability.TrailingWhiteSpace, []},
          # {Credo.Check.Readability.VariableNames, []},

          #
          ## Refactoring Opportunities
          #
          {Credo.Check.Refactor.AppendSingleItem, []},
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CyclomaticComplexity, []},
          {Credo.Check.Refactor.DoubleBooleanNegation, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.FilterReject, []},
          {Credo.Check.Refactor.FunctionArity, []},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MapMap, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.NegatedIsNil, []},
          {Credo.Check.Refactor.Nesting, []},
          {Credo.Check.Refactor.RejectFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.UtcNowTruncate, []},

          #
          ## Warnings
          #
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.Dbg, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.MapGetUnsafePass, []},
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.UnsafeExec, []},
          {Credo.Check.Warning.UnsafeToAtom, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.WrongTestFileExtension, []}
        ],
        disabled: [
          #
          # Controversial and experimental checks (opt-in, just move the check to `:enabled`
          #   and be sure to use `mix credo --strict` to see low priority checks)
          #
          {Credo.Check.Consistency.UnusedVariableNames, []},
          {Credo.Check.Design.SkipTestWithoutComment, []},
          {Credo.Check.Readability.AliasAs, []},
          {Credo.Check.Readability.OnePipePerLine, []},
          {Credo.Check.Readability.WithCustomTaggedTuple, []},
          {Credo.Check.Refactor.ABCSize, []},
          {Credo.Check.Refactor.IoPuts, []},
          {Credo.Check.Refactor.ModuleDependencies, []},
          {Credo.Check.Refactor.PassAsyncInTestCases, []},
          {Credo.Check.Refactor.VariableRebinding, []},
          {Credo.Check.Warning.LazyLogging, []},
          {Credo.Check.Warning.LeakyEnvironment, []},
          {Credo.Check.Warning.MixEnv, []},

          # Styler Rewrites
          #
          # The following rules are automatically rewritten by Styler and so disabled here to save time
          # Some of the rules have `priority: :high`, meaning Credo runs them unless we explicitly disable them
          # (removing them from this file wouldn't be enough, the `false` is required)
          #
          {Credo.Check.Consistency.MultiAliasImportRequireUse, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Design.AliasUsage, []},
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.LargeNumbers, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.MultiAlias, []},
          {Credo.Check.Readability.OneArityFunctionInPipe, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.SinglePipe, []},
          {Credo.Check.Readability.StrictModuleLayout, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.WithSingleClause, []},
          {Credo.Check.Refactor.CaseTrivialMatches, []},
          {Credo.Check.Refactor.CondStatements, []},
          {Credo.Check.Refactor.FilterCount, []},
          {Credo.Check.Refactor.MapInto, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.PipeChainStart, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.WithClauses, []}
        ]
      }
    }
  ]
}
