%{
  configs: [
    %{
      name: "default",
      strict: true,
      checks: [
        # Aliases
        {Credo.Check.Design.Aliases, []},

        # Readability
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.MaxLineLength, max_length: 120},
        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Readability.ModuleNames, []},
        {Credo.Check.Readability.SpacesAroundOperators, []},
        {Credo.Check.Readability.Specs, []},

        # Refactoring
        {Credo.Check.Refactor.FunctionAppendEndToBlockExpression, []},
        {Credo.Check.Refactor.MatchInCondition, []},
        {Credo.Check.Refactor.PipeChainStart, []},

        # Warnings
        {Credo.Check.Warning.Application, []},
        {Credo.Check.Warning.LazyLogging, []},
        {Credo.Check.Warning.OperationOnLiteral, []},

        # Consistency
        {Credo.Check.Consistency.MultiAliasImportUseInside, []},
        {Credo.Check.Consistency.UnusedVariableNames, []}
      ]
    },
    %{
      name: "test",
      strict: false,
      checks: [
        {Credo.Check.Design.Aliases, []},
        {Credo.Check.Readability.FunctionNames, []},
        {Credo.Check.Readability.MaxLineLength, max_length: 120}
      ]
    }
  ]
}
