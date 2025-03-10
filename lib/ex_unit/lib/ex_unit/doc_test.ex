defmodule ExUnit.DocTest do
  @moduledoc """
  Extract test cases from the documentation.

  Doctests allow us to generate tests from code examples found
  in `@moduledoc` and `@doc` attributes. To do this, invoke the
  `doctest/1` macro from within your test case and ensure your
  code examples are written according to the syntax and guidelines
  below.

  ## Syntax

  Every new test starts on a new line, with an `iex>` prefix.
  Multiline expressions can be used by prefixing subsequent lines
  with either `...>` (recommended) or `iex>`.

  The expected result should start the line after the `iex>`
  and `...>` line(s) and be terminated by a newline.

  ## Examples

  To run doctests include them in an ExUnit case with a `doctest` macro:

      defmodule MyModuleTest do
        use ExUnit.Case, async: true
        doctest MyModule
      end

  The `doctest` macro loops through all functions and
  macros defined in `MyModule`, parsing their documentation in
  search of code examples.

  A very basic example is:

      iex> 1 + 1
      2

  Expressions on multiple lines are also supported:

      iex> Enum.map([1, 2, 3], fn x ->
      ...>   x * 2
      ...> end)
      [2, 4, 6]

  Multiple results can be checked within the same test:

      iex> a = 1
      1
      iex> a + 1
      2

  If you want to keep any two tests separate,
  add an empty line between them:

      iex> a = 1
      1

      iex> a + 1 # will fail with a `undefined variable "a"` error
      2

  If you don't want to assert for every result in a doctest, you can omit
  the result. You can do so between expressions:

      iex> pid = spawn(fn -> :ok end)
      iex> is_pid(pid)
      true

  As well as at the end:

      iex> Mod.do_a_call_that_should_not_raise!(...)

  This is useful when the result is something variable (like a PID in the
  example above) or when the result is a complicated data structure and you
  don't want to show it all, but just parts of it or some of its properties.

  Similarly to IEx you can use numbers in your "prompts":

      iex(1)> [1 + 2,
      ...(1)>  3]
      [3, 3]

  This is useful in two cases:

    * being able to refer to specific numbered scenarios
    * copy-pasting examples from an actual IEx session

  You can also select or skip functions when calling
  `doctest`. See the documentation on the `:except` and `:only` options below
  for more information.

  ## Opaque types

  Some types' internal structures are kept hidden and instead show a
  user-friendly structure when inspected. The idiom in
  Elixir is to print those data types in the format `#Name<...>`. Because those
  values are treated as comments in Elixir code due to the leading
  `#` sign, they require special care when being used in doctests.

  Imagine you have a map that contains a MapSet and is printed as:

      %{users: #MapSet<[:foo, :bar]>}

  If you try to match on such an expression, `doctest` will fail to compile.
  There are two ways to resolve this.

  The first is to rely on the fact that doctest can compare internal
  structures as long as they are at the root. So one could write:

      iex> map = %{users: Enum.into([:foo, :bar], MapSet.new())}
      iex> map.users
      #MapSet<[:foo, :bar]>

  Whenever a doctest starts with "#Name<", `doctest` will perform a string
  comparison. For example, the above test will perform the following match:

      inspect(map.users) == "#MapSet<[:foo, :bar]>"

  Alternatively, since doctest results are actually evaluated, you can have
  the MapSet building expression as the doctest result:

      iex> %{users: Enum.into([:foo, :bar], MapSet.new())}
      %{users: Enum.into([:foo, :bar], MapSet.new())}

  The downside of this approach is that the doctest result is not really
  what users would see in the terminal.

  ## Exceptions

  You can also showcase expressions raising an exception, for example:

      iex(1)> raise "some error"
      ** (RuntimeError) some error

  Doctest will look for a line starting with `** (` and it will parse it
  accordingly to extract the exception name and message. The exception parser
  will consider all following lines part of the exception message until there
  is an empty line or there is a new expression prefixed with `iex>`.
  Therefore, it is possible to match on multiline messages as long as there
  are no empty lines on the message itself.

  ## When not to use doctest

  In general, doctests are not recommended when your code examples contain
  side effects. For example, if a doctest prints to standard output, doctest
  will not try to capture the output.

  Similarly, doctests do not run in any kind of sandbox. So any module
  defined in a code example is going to linger throughout the whole test
  suite run.
  """

  @opaque_type_regex ~r/#[\w\.]+</

  defmodule Error do
    defexception [:message]

    @impl true
    def exception(opts) do
      module = Keyword.fetch!(opts, :module)
      message = Keyword.fetch!(opts, :message)

      file = module.module_info(:compile)[:source] |> Path.relative_to_cwd()
      info = Exception.format_file_line(file, opts[:line])
      %__MODULE__{message: info <> " " <> message}
    end
  end

  @doc """
  Generate test cases from module documentation.

  Calling `doctest(Module)` will generate tests for all doctests found
  in the `module`.

  ## Options

    * `:except` - generates tests for all functions except those listed
      (list of `{function, arity}` tuples, and/or `:moduledoc`).

    * `:only` - generates tests only for functions listed
      (list of `{function, arity}` tuples, and/or `:moduledoc`).

    * `:import` - when `true`, one can test a function defined in the module
      without referring to the module name. However, this is not feasible when
      there is a clash with a module like `Kernel`. In these cases, `:import`
      should be set to `false` and `Module.function(...)` should be used instead.

    * `:tags` - a list of tags to apply to all generated doctests.

  ## Examples

      defmodule MyModuleTest do
        use ExUnit.Case
        doctest MyModule, except: [:moduledoc, trick_fun: 1]
      end

  This macro is auto-imported with every `ExUnit.Case`.
  """
  defmacro doctest(module, opts \\ []) do
    caller = __CALLER__

    require =
      if is_atom(Macro.expand(module, caller)) do
        quote do
          require unquote(module)
        end
      end

    tests =
      quote bind_quoted: [
              module: module,
              opts: opts,
              env_line: caller.line,
              env_file: caller.file
            ] do
        file = ExUnit.DocTest.__file__(module)

        for {name, test, tags} <- ExUnit.DocTest.__doctests__(module, opts) do
          @file file
          doc = ExUnit.Case.register_test(__MODULE__, env_file, env_line, :doctest, name, tags)
          def unquote(doc)(_), do: unquote(test)
        end
      end

    [require, tests]
  end

  @doc """
  Generate test cases from a markdown file.

  ## Options

    * `:tags` - a list of tags to apply to all generated doctests.

  ## Examples

      defmodule ReadmeTest do
        use ExUnit.Case
        doctest_file "README.md"
      end

  This macro is auto-imported with every `ExUnit.Case`.
  """
  @doc since: "1.15.0"
  defmacro doctest_file(file, opts \\ []) do
    caller = __CALLER__

    tests =
      quote bind_quoted: [file: file, opts: opts, env_line: caller.line, env_file: caller.file] do
        for {name, test, tags} <- ExUnit.DocTest.__doctest_file__(file, __MODULE__, opts) do
          doc = ExUnit.Case.register_test(__MODULE__, env_file, env_line, :doctest, name, tags)
          def unquote(doc)(_), do: unquote(test)
        end
      end

    tests
  end

  @doc false
  def __doctest_file__(file, module, opts) do
    doc = File.read!(file)
    file = Path.relative_to_cwd(file)
    tags = [doctest: file] ++ Keyword.get(opts, :tags, [])

    extract_tests(1, doc, module)
    |> Stream.map(&normalize_test(&1, :moduledoc))
    |> Stream.with_index(1)
    |> Enum.map(fn {test, acc} ->
      tags = [doctest_line: test.line] ++ tags
      {"#{file} (#{acc})", test_content(test, module, false, file), tags}
    end)
  end

  @doc false
  def __file__(module) do
    source =
      module.module_info(:compile)[:source] ||
        raise "#{inspect(module)} does not have compile-time source information"

    "(for doctest at) " <> Path.relative_to_cwd(source)
  end

  @doc false
  def __doctests__(module, opts) do
    tags = [doctest: module] ++ Keyword.get(opts, :tags, [])
    import = Keyword.get(opts, :import, false)
    file = module.module_info(:compile)[:source] |> Path.relative_to_cwd()

    extract(module)
    |> filter_by_opts(module, opts)
    |> Enum.sort_by(& &1.line)
    |> Enum.with_index(fn test, index ->
      compile_test(test, module, import, index + 1, file, tags)
    end)
  end

  defp filter_by_opts(tests, module, opts) do
    except = Keyword.get(opts, :except, [])

    case Keyword.fetch(opts, :only) do
      {:ok, []} -> []
      {:ok, only} -> filter_tests(module, tests, except, only)
      :error -> Stream.reject(tests, &(&1.fun_arity in except))
    end
  end

  defp filter_tests(module, tests, except, only) do
    {filtered_tests, fun_arities} =
      for test <- tests,
          test.fun_arity not in except,
          test.fun_arity in only,
          reduce: {[], []} do
        {tests, fun_arities} -> {[test | tests], [test.fun_arity | fun_arities]}
      end

    case only -- [:moduledoc | fun_arities] do
      [] ->
        filtered_tests

      undefined_fun_arities ->
        pluralized = pluralize_list_name("function", undefined_fun_arities)

        functions =
          Enum.map_join(undefined_fun_arities, "\n    ", fn {fun, arity} ->
            Exception.format_mfa(module, fun, arity)
          end)

        raise Error,
          module: module,
          message: "undefined or private #{pluralized} given to doctest:\n\n    #{functions}\n\n"
    end
  end

  defp pluralize_list_name(name, [_]), do: name
  defp pluralize_list_name(name, _), do: ExUnit.plural_rule(name)

  ## Compilation of extracted tests

  defp compile_test(test, module, do_import, n, file, tags) do
    tags = [doctest_line: test.line] ++ tags
    {test_name(test, module, n), test_content(test, module, do_import, file), tags}
  end

  defp test_name(%{fun_arity: :moduledoc}, m, n) do
    "module #{inspect(m)} (#{n})"
  end

  defp test_name(%{fun_arity: {f, a}}, m, n) do
    "#{inspect(m)}.#{f}/#{a} (#{n})"
  end

  defp test_content(%{exprs: exprs, line: line}, module, do_import, file) do
    location = [line: line, file: Path.relative_to_cwd(file)]
    stack = Macro.escape([{module, :__MODULE__, 0, location}])

    if multiple_exceptions?(exprs) do
      raise Error,
        line: line,
        module: module,
        message:
          "multiple exceptions in the same doctest example are not supported, " <>
            "please separate your iex> prompts by multiple newlines to start new examples"
    end

    tests =
      Enum.map(exprs, fn {expr, expected, doctest} ->
        test_case_content(expr, expected, location, stack, doctest)
      end)

    {:__block__, [], test_import(module, do_import) ++ tests}
  end

  defp multiple_exceptions?(exprs) do
    Enum.count(exprs, fn
      {_, {:error, _, _}, _} -> true
      _ -> false
    end) > 1
  end

  defp test_case_content(expr_lines, :test, location, stack, doctest) do
    string_to_quoted(location, stack, expr_lines, doctest) |> insert_assertions()
  end

  defp test_case_content(expr_lines, {:test, expected}, location, stack, doctest) do
    expr_ast = string_to_quoted(location, stack, expr_lines, doctest) |> insert_assertions()
    expected_ast = string_to_quoted(update_line(location, expr_lines), stack, expected, doctest)
    last_expr = Macro.to_string(last_expr(expr_ast))

    quote do
      value = unquote(expr_ast)
      expected = unquote(expected_ast)
      doctest = unquote(doctest)
      last_expr = unquote(last_expr)
      expected_expr = unquote(expected)
      stack = unquote(stack)

      ExUnit.DocTest.__test__(value, expected, doctest, last_expr, expected_expr, stack)
    end
  end

  defp test_case_content(expr_lines, {:inspect, expected}, location, stack, doctest) do
    expr_ast = string_to_quoted(location, stack, expr_lines, doctest) |> insert_assertions()
    last_expr = Macro.to_string(last_expr(expr_ast))

    quote do
      value = unquote(expr_ast)
      expected = unquote(expected)
      doctest = unquote(doctest)
      last_expr = unquote(last_expr)
      expected_expr = unquote(inspect(expected))
      stack = unquote(stack)

      ExUnit.DocTest.__inspect__(value, expected, doctest, last_expr, expected_expr, stack)
    end
  end

  defp test_case_content(expr, {:error, exception, message}, location, stack, doctest) do
    expr_ast = string_to_quoted(location, stack, expr, doctest)

    quote do
      stack = unquote(stack)
      message = unquote(message)
      doctest = unquote(doctest)
      exception = unquote(exception)
      ExUnit.DocTest.__error__(fn -> unquote(expr_ast) end, message, exception, doctest, stack)
    end
  end

  defp update_line(location, lines) do
    Keyword.replace_lazy(location, :line, &(&1 + length(lines)))
  end

  @doc false
  def __test__(value, expected, doctest, last_expr, expected_expr, stack) do
    case value do
      ^expected ->
        {:ok, value}

      _ ->
        error = [
          message: "Doctest failed",
          doctest: doctest,
          expr: "#{last_expr} === #{String.trim(expected_expr)}",
          left: value,
          right: expected
        ]

        reraise ExUnit.AssertionError, error, stack
    end
  end

  @doc false
  def __inspect__(value, expected, doctest, last_expr, expected_expr, parent_stack) do
    result =
      try do
        inspect(value, safe: false)
      rescue
        e ->
          stack = Enum.drop(__STACKTRACE__, 1)
          {[message: Exception.message(e)], ExUnit.Runner.prune_stacktrace(stack)}
      else
        ^expected -> :ok
        actual -> {[left: actual, right: expected, message: "Doctest failed"], []}
      end

    case result do
      :ok ->
        {:ok, value}

      {extra, stack} ->
        expr = "inspect(#{last_expr}) === #{String.trim(expected_expr)}"
        error = [doctest: doctest, expr: expr] ++ extra
        reraise ExUnit.AssertionError, error, stack ++ parent_stack
    end
  end

  @doc false
  def __error__(fun, message, exception, doctest, stack) do
    try do
      fun.()
    rescue
      error ->
        actual_exception = error.__struct__
        actual_message = Exception.message(error)

        failed =
          cond do
            actual_exception != exception ->
              "Doctest failed: expected exception #{inspect(exception)} but got " <>
                "#{inspect(actual_exception)} with message #{inspect(actual_message)}"

            actual_message != message ->
              "Doctest failed: wrong message for #{inspect(actual_exception)}\n" <>
                "expected:\n" <>
                "  #{inspect(message)}\n" <>
                "actual:\n" <> "  #{inspect(actual_message)}"

            true ->
              nil
          end

        if failed do
          reraise ExUnit.AssertionError, [message: failed, doctest: doctest], stack
        end
    else
      _ ->
        failed = "Doctest failed: expected exception #{inspect(exception)} but nothing was raised"
        error = [message: failed, doctest: doctest]
        reraise ExUnit.AssertionError, error, stack
    end
  end

  defp test_import(_mod, false), do: []
  defp test_import(mod, _), do: [quote(do: import(unquote(mod)))]

  defp string_to_quoted(location, stack, expr, doctest) do
    expr = IO.iodata_to_binary(expr)

    try do
      Code.string_to_quoted!(expr, location)
    rescue
      e ->
        ex_message = "(#{inspect(e.__struct__)}) #{Exception.message(e)}"
        message = "Doctest did not compile, got: #{ex_message}"

        message =
          if e.__struct__ == TokenMissingError and expr =~ @opaque_type_regex do
            message <>
              """
              \nIf you are planning to assert on the result of an iex> expression \
              which contains a value inspected as #Name<...>, please make sure \
              the inspected value is placed at the beginning of the expression; \
              otherwise Elixir will treat it as a comment due to the leading sign #.\
              """
          else
            message
          end

        opts =
          if String.valid?(doctest) do
            [message: message, doctest: doctest]
          else
            [message: message]
          end

        quote do
          reraise ExUnit.AssertionError, unquote(opts), unquote(stack)
        end
    end
  end

  ## Extraction of the tests

  defp extract(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, annotation, _, _, moduledoc, _, docs} ->
        extract_from_moduledoc(annotation, moduledoc, module) ++
          extract_from_docs(Enum.sort(docs), module)

      {:error, reason} ->
        raise Error,
          module: module,
          message:
            "could not retrieve the documentation for module #{inspect(module)}. " <>
              explain_docs_error(reason)
    end
  end

  defp explain_docs_error(:module_not_found),
    do: "The BEAM file of the module cannot be accessed"

  defp explain_docs_error(:chunk_not_found),
    do: "The module was not compiled with documentation"

  defp explain_docs_error({:invalid_chunk, _}),
    do: "The documentation chunk in the module is invalid"

  defp extract_from_moduledoc(annotation, %{"en" => doc}, module) do
    for test <- extract_tests(:erl_anno.line(annotation), doc, module) do
      normalize_test(test, :moduledoc)
    end
  end

  defp extract_from_moduledoc(_, _doc, _module), do: []

  defp extract_from_docs(docs, module) do
    for doc <- docs, doc <- extract_from_doc(doc, module), do: doc
  end

  defp extract_from_doc({{_, name, arity}, annotation, _, %{"en" => doc}, _}, module) do
    line = :erl_anno.line(annotation)

    for test <- extract_tests(line, doc, module) do
      normalize_test(test, {name, arity})
    end
  end

  defp extract_from_doc(_doc, _module),
    do: []

  @iex_prompt ["iex>", "iex("]
  @dot_prompt ["...>", "...("]

  defp adjust_indent(lines, line_no, module) do
    adjust_indent(:text, lines, line_no, [], 0, module)
  end

  defp adjust_indent(_kind, [], _line_no, adjusted_lines, _indent, _module) do
    Enum.reverse(adjusted_lines)
  end

  defp adjust_indent(:text, [line | rest], line_no, adjusted_lines, indent, module) do
    case String.starts_with?(String.trim_leading(line), @iex_prompt) do
      true ->
        line_indent = get_indent(line, indent)
        adjust_indent(:prompt, [line | rest], line_no, adjusted_lines, line_indent, module)

      false ->
        adjust_indent(:text, rest, line_no + 1, adjusted_lines, indent, module)
    end
  end

  defp adjust_indent(kind, [line | rest], line_no, adjusted_lines, indent, module)
       when kind in [:prompt, :after_prompt] do
    stripped_line = strip_indent(line, indent)

    case String.trim_leading(line) do
      "" ->
        :ok

      ^stripped_line ->
        :ok

      _ ->
        n_spaces = if indent == 1, do: "#{indent} space", else: "#{indent} spaces"

        raise Error,
          line: line_no,
          module: module,
          message: """
          indentation level mismatch on doctest line: #{inspect(line)}

          If you are planning to assert on the result of an `iex>` expression, \
          make sure the result is indented at the beginning of `iex>`, which \
          in this case is exactly #{n_spaces}.

          If instead you have an `iex>` expression that spans over multiple lines, \
          please make sure that each line after the first one begins with `...>`.
          """
    end

    adjusted_lines = [{stripped_line, line_no} | adjusted_lines]

    next =
      cond do
        kind == :prompt -> :after_prompt
        String.starts_with?(stripped_line, @iex_prompt ++ @dot_prompt) -> :after_prompt
        true -> :code
      end

    adjust_indent(next, rest, line_no + 1, adjusted_lines, indent, module)
  end

  defp adjust_indent(:code, [line | rest], line_no, adjusted_lines, indent, module) do
    stripped_line = strip_indent(line, indent)

    cond do
      stripped_line == "" ->
        adjusted_lines = [{stripped_line, line_no} | adjusted_lines]
        adjust_indent(:text, rest, line_no + 1, adjusted_lines, 0, module)

      String.starts_with?(String.trim_leading(line), @iex_prompt) ->
        adjust_indent(:prompt, [line | rest], line_no, adjusted_lines, indent, module)

      true ->
        adjusted_lines = [{stripped_line, line_no} | adjusted_lines]
        adjust_indent(:code, rest, line_no + 1, adjusted_lines, indent, module)
    end
  end

  defp get_indent(line, current_indent) do
    case :binary.match(line, "iex") do
      {pos, _len} -> pos
      :nomatch -> current_indent
    end
  end

  defp strip_indent(line, indent) do
    length = byte_size(line) - indent

    if length > 0 do
      binary_part(line, indent, length)
    else
      ""
    end
  end

  @fences ["```", "~~~"]

  defp extract_tests(line_no, doc, module) do
    all_lines = String.split(doc, ["\r\n", "\n"], trim: false)
    lines = adjust_indent(all_lines, line_no + 1, module)
    extract_tests(lines, [], [], [], true, module, [])
  end

  defp extract_tests(lines, expr_acc, expected_acc, acc, new_test, module, formatted)

  defp extract_tests([], [], [], [], _, _, _) do
    []
  end

  defp extract_tests([], [], [], acc, _, _, _) do
    Enum.reverse(acc)
  end

  # End of input and we've still got a test pending.
  defp extract_tests([], expr_acc, expected_acc, [test | rest], _, _, formatted) do
    test = add_expr(test, expr_acc, expected_acc, formatted)
    Enum.reverse([test | rest])
  end

  # We've encountered the next test on an adjacent line. Put them into one group.
  defp extract_tests(
         [{"iex>" <> _, _} | _] = list,
         expr_acc,
         expected_acc,
         [test | rest],
         new_test,
         module,
         formatted
       )
       when expr_acc != [] and expected_acc != [] do
    test = add_expr(test, expr_acc, expected_acc, formatted)
    extract_tests(list, [], [], [test | rest], new_test, module, [])
  end

  # Store expr_acc and start a new test case.
  defp extract_tests(
         [{"iex>" <> string = line, line_no} | lines],
         [],
         expected_acc,
         acc,
         true,
         module,
         _
       ) do
    test = %{line: line_no, fun_arity: nil, exprs: []}
    extract_tests(lines, [string], expected_acc, [test | acc], false, module, line)
  end

  # Store expr_acc.
  defp extract_tests(
         [{"iex>" <> string = line, _} | lines],
         [],
         expected_acc,
         acc,
         false,
         module,
         _
       ) do
    extract_tests(lines, [string], expected_acc, acc, false, module, line)
  end

  # Still gathering expr_acc. Synonym for the next clause.
  defp extract_tests(
         [{"iex>" <> string = line, _} | lines],
         expr_acc,
         expected_acc,
         acc,
         new_test,
         module,
         formatted
       ) do
    expr_acc = add_line(expr_acc, string)
    formatted = add_line(formatted, line)
    extract_tests(lines, expr_acc, expected_acc, acc, new_test, module, formatted)
  end

  # Still gathering expr_acc. Synonym for the previous clause.
  defp extract_tests(
         [{"...>" <> string = line, _} | lines],
         expr_acc,
         expected_acc,
         acc,
         new_test,
         module,
         formatted
       )
       when expr_acc != [] do
    expr_acc = add_line(expr_acc, string)
    formatted = add_line(formatted, line)
    extract_tests(lines, expr_acc, expected_acc, acc, new_test, module, formatted)
  end

  # Expression numbers are simply skipped.
  defp extract_tests(
         [{<<"iex(", _>> <> string = line, line_no} | lines],
         expr_acc,
         expected_acc,
         acc,
         new_test,
         module,
         formatted
       ) do
    new_line = {"iex" <> skip_iex_number(string, module, line_no, line), line_no}
    extract_tests([new_line | lines], expr_acc, expected_acc, acc, new_test, module, formatted)
  end

  # Expression numbers are simply skipped redux.
  defp extract_tests(
         [{<<"...(", _>> <> string, line_no} = line | lines],
         expr_acc,
         expected_acc,
         acc,
         new_test,
         module,
         formatted
       ) do
    new_line = {"..." <> skip_iex_number(string, module, line_no, line), line_no}
    extract_tests([new_line | lines], expr_acc, expected_acc, acc, new_test, module, formatted)
  end

  # Skip empty or documentation line.
  defp extract_tests([_ | lines], [], [], acc, _, module, _formatted) do
    extract_tests(lines, [], [], acc, true, module, [])
  end

  # Encountered end of fenced code block, store pending test
  defp extract_tests(
         [{<<fence::3-bytes>> <> _, _} | lines],
         expr_acc,
         expected_acc,
         [test | rest],
         _new_test,
         module,
         formatted
       )
       when fence in @fences and expr_acc != [] do
    test = add_expr(test, expr_acc, expected_acc, formatted)
    extract_tests(lines, [], [], [test | rest], true, module, [])
  end

  # Encountered an empty line, store pending test
  defp extract_tests(
         [{"", _} | lines],
         expr_acc,
         expected_acc,
         [test | rest],
         _new_test,
         module,
         formatted
       ) do
    test = add_expr(test, expr_acc, expected_acc, formatted)
    extract_tests(lines, [], [], [test | rest], true, module, [])
  end

  # Finally, parse expected_acc.
  defp extract_tests([{expected, _} | lines], expr_acc, [], acc, new_test, module, formatted) do
    extract_tests(lines, expr_acc, expected, acc, new_test, module, formatted)
  end

  defp extract_tests(
         [{expected, _} | lines],
         expr_acc,
         expected_acc,
         acc,
         new_test,
         module,
         formatted
       ) do
    expected_acc = add_line(expected_acc, expected)
    extract_tests(lines, expr_acc, expected_acc, acc, new_test, module, formatted)
  end

  defp add_line(acc, line) do
    [acc, [?\n, line]]
  end

  defp skip_iex_number(")>" <> string, _module, _line_no, _line) do
    ">" <> string
  end

  defp skip_iex_number("", module, line_no, line) do
    message =
      "unknown IEx prompt: #{inspect(line)}.\nAccepted formats are: iex>, iex(1)>, ...>, ...(1)>}"

    raise Error, line: line_no, module: module, message: message
  end

  defp skip_iex_number(<<_>> <> string, module, line_no, line) do
    skip_iex_number(string, module, line_no, line)
  end

  defp normalize_test(%{exprs: exprs} = test, fa) do
    %{test | fun_arity: fa, exprs: Enum.reverse(exprs)}
  end

  defp add_expr(%{exprs: exprs} = test, expr_lines, expected_lines, formatted_lines) do
    expected = IO.iodata_to_binary(expected_lines)
    doctest = IO.iodata_to_binary([?\n, formatted_lines, ?\n, expected])
    %{test | exprs: [{expr_lines, tag_expected(expected), doctest} | exprs]}
  end

  defp tag_expected(expected) do
    case expected do
      "" ->
        :test

      "** (" <> error ->
        [mod, message] = :binary.split(error, ")")
        {:error, Module.concat([mod]), String.trim_leading(message)}

      _ ->
        if inspectable?(expected) do
          {:inspect, expected}
        else
          {:test, expected}
        end
    end
  end

  defp inspectable?(<<?#, char, rest::binary>>) when char in ?A..?Z, do: inspectable_end?(rest)
  defp inspectable?(_), do: false

  defp inspectable_end?(<<?., char, rest::binary>>) when char in ?A..?Z,
    do: inspectable_end?(rest)

  defp inspectable_end?(<<char, rest::binary>>)
       when char in ?A..?Z
       when char in ?a..?z
       when char in ?0..?9
       when char == ?_,
       do: inspectable_end?(rest)

  defp inspectable_end?(<<?<, _::binary>>), do: true
  defp inspectable_end?(_), do: false

  defp last_expr({:__block__, _, [_ | _] = block}), do: block |> List.last() |> last_expr()
  defp last_expr(other), do: other

  defp insert_assertions({:__block__, meta, block}),
    do: {:__block__, meta, Enum.map(block, &insert_match_assertion/1)}

  defp insert_assertions(ast),
    do: insert_match_assertion(ast)

  defp insert_match_assertion({:=, _, [{var, _, context}, _]} = ast)
       when is_atom(var) and is_atom(context),
       do: ast

  defp insert_match_assertion({:=, meta, [left, right]}),
    do: {{:., meta, [__MODULE__, :__assert__]}, meta, [{:=, meta, [left, right]}]}

  defp insert_match_assertion(ast),
    do: ast

  @doc false
  defmacro __assert__({:=, _, [left, right]} = assertion) do
    code = Macro.escape(assertion, prune_metadata: true)
    ExUnit.Assertions.__match__(left, right, code, :ok, __CALLER__)
  end
end
