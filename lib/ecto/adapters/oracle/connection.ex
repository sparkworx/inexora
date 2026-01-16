defmodule Ecto.Adapters.Oracle.Connection do
  @moduledoc false

  @behaviour Ecto.Adapters.SQL.Connection

  alias Ecto.Query.{BooleanExpr, ByExpr, JoinExpr, LimitExpr, QueryExpr, WithExpr}
  alias Ecto.Migration.Reference

  # Module attributes
  @parent_as __MODULE__
  @binary_ops [:==, :!=, :<=, :>=, :<, :>, :and, :or, :like, :ilike]

  # ============================================================
  # Connection API
  # ============================================================

  @impl true
  def child_spec(opts) do
    DBConnection.child_spec(Inexora.Connection, opts)
  end

  @impl true
  def prepare_execute(conn, _name, sql, params, opts) do
    query = %Inexora.Query{sql: sql, statement: nil}
    DBConnection.prepare_execute(conn, query, params, opts)
  end

  @impl true
  def execute(conn, query, params, opts) do
    DBConnection.execute(conn, query, params, opts)
  end

  @impl true
  def query(conn, sql, params, opts) do
    query = %Inexora.Query{sql: sql, statement: nil}
    case DBConnection.prepare_execute(conn, query, params, opts) do
      {:ok, _query, result} -> {:ok, result}
      {:error, err} -> {:error, err}
    end
  end

  @impl true
  def query_many(_conn, _sql, _params, _opts) do
    raise "query_many is not supported by Oracle adapter"
  end

  @impl true
  def stream(_conn, _sql, _params, _opts) do
    raise "streaming is not yet supported by Oracle adapter"
  end

  # ============================================================
  # Query API - SELECT
  # ============================================================

  @impl true
  def all(query, as_prefix \\ []) do
    sources = create_names(query, as_prefix)
    {select_distinct, order_by_distinct} = distinct(query.distinct, sources, query)

    cte = cte(query, sources)
    from = from(query, sources)
    select = select(query, select_distinct, sources)
    join = join(query, sources)
    where = where(query, sources)
    group_by = group_by(query, sources)
    having = having(query, sources)
    window = window(query, sources)
    combinations = combinations(query, as_prefix)
    order_by = order_by(query, order_by_distinct, sources)
    limit = limit(query, sources)
    offset = offset(query, sources)
    lock = lock(query, sources)

    [cte, select, from, join, where, group_by, having, window, combinations, order_by, offset, limit, lock]
  end

  # ============================================================
  # Query API - UPDATE ALL
  # ============================================================

  @impl true
  def update_all(%{from: %{source: source}} = query, prefix \\ []) do
    sources = create_names(query, prefix)
    {from, name} = get_source(query, sources, 0, source)

    cte = cte(query, sources)
    prefix = prefix(prefix, query)
    fields = update_fields(query, sources)
    where = where(query, sources)

    [cte, "UPDATE ", prefix, from, " ", name, " SET ", fields, where]
  end

  # ============================================================
  # Query API - DELETE ALL
  # ============================================================

  @impl true
  def delete_all(%{from: %{source: source}} = query, prefix \\ []) do
    sources = create_names(query, prefix)
    {from, name} = get_source(query, sources, 0, source)

    cte = cte(query, sources)
    prefix = prefix(prefix, query)
    where = where(query, sources)

    [cte, "DELETE FROM ", prefix, from, " ", name, where]
  end

  # ============================================================
  # Query API - INSERT
  # ============================================================

  @impl true
  def insert(prefix, table, header, rows, on_conflict, returning, placeholders) do
    values =
      if header == [] do
        [?(, intersperse_map(rows, ?,, fn _ -> "DEFAULT" end), ?)]
      else
        [?(, intersperse_map(header, ?,, &quote_name/1), ") VALUES " | insert_all(rows, 1, placeholders)]
      end

    [
      "INSERT INTO ",
      quote_table(prefix, table),
      values,
      on_conflict(on_conflict, header),
      returning(returning)
    ]
  end

  defp insert_all(rows, counter, placeholders) do
    intersperse_reduce(rows, ?,, counter, fn row, counter ->
      {row_values, counter} = insert_each(row, counter, placeholders)
      {[?(, row_values, ?)], counter}
    end)
    |> elem(0)
  end

  defp insert_each(values, counter, placeholders) do
    intersperse_reduce(values, ?,, counter, fn
      {:placeholder, key}, counter ->
        {[placeholders[key]], counter}

      _, counter ->
        {[?: | Integer.to_string(counter)], counter + 1}
    end)
  end

  defp on_conflict({:raise, _, []}, _header), do: []
  defp on_conflict({:nothing, _, _}, _header), do: []
  defp on_conflict({:replace_all, _, _}, _header), do: []
  defp on_conflict(_, _), do: []

  # ============================================================
  # Query API - UPDATE
  # ============================================================

  @impl true
  def update(prefix, table, fields, filters, returning) do
    {fields, count} =
      intersperse_reduce(fields, ", ", 1, fn field, counter ->
        {[quote_name(field), " = :" | Integer.to_string(counter)], counter + 1}
      end)

    {filters, _count} =
      intersperse_reduce(filters, " AND ", count, fn
        {field, nil}, counter ->
          {[quote_name(field), " IS NULL"], counter}

        {field, _value}, counter ->
          {[quote_name(field), " = :" | Integer.to_string(counter)], counter + 1}
      end)

    [
      "UPDATE ",
      quote_table(prefix, table),
      " SET ",
      fields,
      " WHERE ",
      filters,
      returning(returning)
    ]
  end

  # ============================================================
  # Query API - DELETE
  # ============================================================

  @impl true
  def delete(prefix, table, filters, returning) do
    {filters, _count} =
      intersperse_reduce(filters, " AND ", 1, fn
        {field, nil}, counter ->
          {[quote_name(field), " IS NULL"], counter}

        {field, _value}, counter ->
          {[quote_name(field), " = :" | Integer.to_string(counter)], counter + 1}
      end)

    [
      "DELETE FROM ",
      quote_table(prefix, table),
      " WHERE ",
      filters,
      returning(returning)
    ]
  end

  # ============================================================
  # Query API - EXPLAIN
  # ============================================================

  @impl true
  def explain_query(_conn, _query, _params, _opts) do
    raise "EXPLAIN is not yet supported by Oracle adapter"
  end

  # ============================================================
  # Table Operations (DDL)
  # ============================================================

  @impl true
  def execute_ddl({command, %Ecto.Migration.Table{} = table, columns})
      when command in [:create, :create_if_not_exists] do
    table_name = quote_table(table.prefix, table.name)

    query = [
      "CREATE TABLE ",
      if_do(command == :create_if_not_exists, ""),
      table_name,
      ?\s,
      ?(,
      column_definitions(table, columns),
      pk_definition(columns),
      ?),
      options_expr(table.options)
    ]

    [query]
  end

  def execute_ddl({command, %Ecto.Migration.Table{} = table, _})
      when command in [:drop, :drop_if_exists] do
    [
      [
        "DROP TABLE ",
        if_do(command == :drop_if_exists, ""),
        quote_table(table.prefix, table.name)
      ]
    ]
  end

  def execute_ddl({:alter, %Ecto.Migration.Table{} = table, changes}) do
    table_name = quote_table(table.prefix, table.name)

    Enum.map(changes, fn change ->
      ["ALTER TABLE ", table_name, ?\s, column_change(table, change)]
    end)
  end

  def execute_ddl({:create, %Ecto.Migration.Index{} = index}) do
    fields = intersperse_map(index.columns, ", ", &index_expr/1)

    [
      [
        "CREATE ",
        if_do(index.unique, "UNIQUE "),
        "INDEX ",
        quote_name(index.name),
        " ON ",
        quote_table(index.prefix, index.table),
        ?\s,
        ?(,
        fields,
        ?)
      ]
    ]
  end

  def execute_ddl({:create_if_not_exists, %Ecto.Migration.Index{} = index}) do
    execute_ddl({:create, index})
  end

  def execute_ddl({command, %Ecto.Migration.Index{} = index})
      when command in [:drop, :drop_if_exists] do
    [
      [
        "DROP INDEX ",
        quote_name(index.name)
      ]
    ]
  end

  def execute_ddl({:create, %Ecto.Migration.Constraint{} = constraint}) do
    table_name = quote_table(constraint.prefix, constraint.table)

    [
      [
        "ALTER TABLE ",
        table_name,
        " ADD CONSTRAINT ",
        quote_name(constraint.name),
        constraint_expr(constraint)
      ]
    ]
  end

  def execute_ddl({:drop, %Ecto.Migration.Constraint{} = constraint}) do
    table_name = quote_table(constraint.prefix, constraint.table)

    [
      [
        "ALTER TABLE ",
        table_name,
        " DROP CONSTRAINT ",
        quote_name(constraint.name)
      ]
    ]
  end

  def execute_ddl({:rename, %Ecto.Migration.Table{} = current_table, %Ecto.Migration.Table{} = new_table}) do
    [
      [
        "ALTER TABLE ",
        quote_table(current_table.prefix, current_table.name),
        " RENAME TO ",
        quote_name(new_table.name)
      ]
    ]
  end

  def execute_ddl({:rename, %Ecto.Migration.Table{} = table, current_column, new_column}) do
    [
      [
        "ALTER TABLE ",
        quote_table(table.prefix, table.name),
        " RENAME COLUMN ",
        quote_name(current_column),
        " TO ",
        quote_name(new_column)
      ]
    ]
  end

  def execute_ddl(string) when is_binary(string), do: [string]

  def execute_ddl(keyword) when is_list(keyword) do
    raise ArgumentError, "Oracle adapter does not support keyword lists in execute"
  end

  # ============================================================
  # Query String Generation Helpers
  # ============================================================

  defp select(%{select: %{fields: fields}} = query, select_distinct, sources) do
    ["SELECT ", select_distinct, select_fields(fields, sources, query)]
  end

  defp select_fields([], _sources, _query), do: "1"

  defp select_fields(fields, sources, query) do
    intersperse_map(fields, ", ", fn
      {:&, _, [idx]} ->
        case elem(sources, idx) do
          {_, source, nil} ->
            error!(query, "Oracle does not support selecting all fields from #{source} without a schema")

          {_, source, _} ->
            source
        end

      {key, value} ->
        [expr(value, sources, query), " AS " | quote_name(key)]

      value ->
        expr(value, sources, query)
    end)
  end

  defp distinct(nil, _, _), do: {[], []}
  defp distinct(%ByExpr{expr: true}, _, _), do: {["DISTINCT "], []}
  defp distinct(%ByExpr{expr: false}, _, _), do: {[], []}

  defp distinct(%ByExpr{expr: exprs}, sources, query) do
    # Oracle doesn't support DISTINCT ON, so we use DISTINCT
    {["DISTINCT "], Enum.map(exprs, &order_by_expr(&1, sources, query))}
  end

  defp from(%{from: %{source: source, hints: hints}} = query, sources) do
    {from, name} = get_source(query, sources, 0, source)
    [" FROM ", from, " ", name | hints(hints)]
  end

  defp cte(%{with_ctes: %WithExpr{recursive: recursive, queries: [_ | _] = queries}} = query, sources) do
    recursive_opt = if recursive, do: "RECURSIVE ", else: ""
    ctes = intersperse_map(queries, ", ", &cte_expr(&1, sources, query))
    ["WITH ", recursive_opt, ctes, " "]
  end

  defp cte(%{with_ctes: _}, _), do: []

  defp cte_expr({name, cte}, sources, query) do
    [quote_name(name), " AS ", cte_query(cte, sources, query)]
  end

  defp cte_query(%Ecto.Query{} = query, sources, parent_query) do
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    ["(", all(query), ")"]
  end

  defp cte_query(%QueryExpr{expr: expr}, sources, query) do
    expr(expr, sources, query)
  end

  defp update_fields(%{updates: updates} = query, sources) do
    for(
      %{expr: expr} <- updates,
      {op, kw} <- expr,
      {key, value} <- kw,
      do: update_op(op, key, value, sources, query)
    )
    |> Enum.intersperse(", ")
  end

  defp update_op(:set, key, value, sources, query) do
    [quote_name(key), " = " | expr(value, sources, query)]
  end

  defp update_op(:inc, key, value, sources, query) do
    [
      quote_name(key),
      " = ",
      quote_qualified_name(key, sources, 0),
      " + "
      | expr(value, sources, query)
    ]
  end

  defp update_op(:push, _key, _value, _sources, query) do
    error!(query, "Oracle does not support :push in update")
  end

  defp update_op(:pull, _key, _value, _sources, query) do
    error!(query, "Oracle does not support :pull in update")
  end

  defp update_op(op, _key, _value, _sources, query) do
    error!(query, "Unknown update operation #{inspect(op)}")
  end

  defp join(%{joins: []}, _sources), do: []

  defp join(%{joins: joins} = query, sources) do
    Enum.map(joins, fn
      %JoinExpr{on: %QueryExpr{expr: expr}, qual: qual, ix: ix, source: source, hints: hints} ->
        {join, name} = get_source(query, sources, ix, source)
        [join_qual(qual), join, " ", name, hints(hints) | join_on(qual, expr, sources, query)]
    end)
  end

  defp join_on(:cross, true, _sources, _query), do: []
  defp join_on(:cross_lateral, true, _sources, _query), do: []
  defp join_on(_qual, expr, sources, query), do: [" ON " | expr(expr, sources, query)]

  defp join_qual(:inner), do: " INNER JOIN "
  defp join_qual(:left), do: " LEFT OUTER JOIN "
  defp join_qual(:right), do: " RIGHT OUTER JOIN "
  defp join_qual(:full), do: " FULL OUTER JOIN "
  defp join_qual(:cross), do: " CROSS JOIN "
  defp join_qual(:cross_lateral), do: " CROSS JOIN LATERAL "
  defp join_qual(:inner_lateral), do: " INNER JOIN LATERAL "
  defp join_qual(:left_lateral), do: " LEFT OUTER JOIN LATERAL "

  defp where(%{wheres: wheres} = query, sources) do
    boolean(" WHERE ", wheres, sources, query)
  end

  defp having(%{havings: havings} = query, sources) do
    boolean(" HAVING ", havings, sources, query)
  end

  defp group_by(%{group_bys: []}, _sources), do: []

  defp group_by(%{group_bys: group_bys} = query, sources) do
    [
      " GROUP BY "
      | intersperse_map(group_bys, ", ", fn %ByExpr{expr: expr} ->
          intersperse_map(expr, ", ", &expr(&1, sources, query))
        end)
    ]
  end

  defp window(%{windows: []}, _sources), do: []

  defp window(%{windows: windows} = query, sources) do
    [
      " WINDOW "
      | intersperse_map(windows, ", ", fn {name, %{expr: kw}} ->
          [quote_name(name), " AS " | window_exprs(kw, sources, query)]
        end)
    ]
  end

  defp window_exprs(kw, sources, query) do
    [?(, intersperse_map(kw, ?\s, &window_expr(&1, sources, query)), ?)]
  end

  defp window_expr({:partition_by, fields}, sources, query) do
    ["PARTITION BY " | intersperse_map(fields, ", ", &expr(&1, sources, query))]
  end

  defp window_expr({:order_by, fields}, sources, query) do
    ["ORDER BY " | intersperse_map(fields, ", ", &order_by_expr(&1, sources, query))]
  end

  defp window_expr({:frame, {:fragment, _, _} = fragment}, sources, query) do
    expr(fragment, sources, query)
  end

  defp order_by(%{order_bys: []}, _distinct, _sources), do: []

  defp order_by(%{order_bys: order_bys} = query, distinct, sources) do
    order_bys = Enum.flat_map(order_bys, & &1.expr)

    [
      " ORDER BY "
      | intersperse_map(distinct ++ order_bys, ", ", &order_by_expr(&1, sources, query))
    ]
  end

  defp order_by_expr({dir, expr}, sources, query) do
    str = expr(expr, sources, query)

    case dir do
      :asc -> str
      :asc_nulls_last -> [str | " ASC NULLS LAST"]
      :asc_nulls_first -> [str | " ASC NULLS FIRST"]
      :desc -> [str | " DESC"]
      :desc_nulls_last -> [str | " DESC NULLS LAST"]
      :desc_nulls_first -> [str | " DESC NULLS FIRST"]
    end
  end

  # Oracle uses FETCH FIRST for LIMIT instead of LIMIT
  defp limit(%{limit: nil}, _sources), do: []

  defp limit(%{limit: %LimitExpr{expr: expr}} = query, sources) do
    [" FETCH FIRST ", expr(expr, sources, query), " ROWS ONLY"]
  end

  # Oracle uses OFFSET for skip
  defp offset(%{offset: nil}, _sources), do: []

  defp offset(%{offset: %QueryExpr{expr: expr}} = query, sources) do
    [" OFFSET ", expr(expr, sources, query), " ROWS"]
  end

  defp combinations(%{combinations: []}, _as_prefix), do: []

  defp combinations(%{combinations: combinations}, as_prefix) do
    Enum.map(combinations, fn
      {:union, query} -> [" UNION ", all(query, as_prefix)]
      {:union_all, query} -> [" UNION ALL ", all(query, as_prefix)]
      {:except, query} -> [" MINUS ", all(query, as_prefix)]
      {:except_all, query} -> [" MINUS ", all(query, as_prefix)]
      {:intersect, query} -> [" INTERSECT ", all(query, as_prefix)]
      {:intersect_all, query} -> [" INTERSECT ", all(query, as_prefix)]
    end)
  end

  defp lock(%{lock: nil}, _sources), do: []
  defp lock(%{lock: "FOR UPDATE"}, _sources), do: " FOR UPDATE"
  defp lock(%{lock: lock_expr}, _sources), do: [?\s | lock_expr]

  defp boolean(_name, [], _sources, _query), do: []

  defp boolean(name, [%{expr: expr, op: op} | query_exprs], sources, query) do
    [
      name,
      Enum.reduce(query_exprs, {op, paren_expr(expr, sources, query)}, fn
        %BooleanExpr{expr: expr, op: op}, {op, acc} ->
          {op, [acc, operator_to_boolean(op) | paren_expr(expr, sources, query)]}

        %BooleanExpr{expr: expr, op: op}, {_, acc} ->
          {op, [?(, acc, ?), operator_to_boolean(op) | paren_expr(expr, sources, query)]}
      end)
      |> elem(1)
    ]
  end

  defp operator_to_boolean(:and), do: " AND "
  defp operator_to_boolean(:or), do: " OR "

  defp paren_expr(expr, sources, query) do
    [?(, expr(expr, sources, query), ?)]
  end

  defp returning([]), do: []

  defp returning(fields) do
    [" RETURNING ", intersperse_map(fields, ", ", &quote_name/1), " INTO ",
     intersperse_map(Enum.with_index(fields, 1), ", ", fn {_, i} ->
       [":", Integer.to_string(i)]
     end)]
  end

  # ============================================================
  # Expression Helpers
  # ============================================================

  defp expr({:^, [], [idx]}, _sources, _query) do
    [?: | Integer.to_string(idx + 1)]
  end

  defp expr({{:., _, [{:&, _, [idx]}, field]}, _, []}, sources, _query) when is_atom(field) do
    quote_qualified_name(field, sources, idx)
  end

  defp expr({{:., _, [{:parent_as, _, [as]}, field]}, _, []}, _sources, query)
       when is_atom(field) do
    {parent_query, sources} = Map.fetch!(query.aliases, as)
    quote_qualified_name(field, sources, parent_query)
  end

  defp expr({:&, _, [idx]}, sources, _query) do
    {_, source, _} = elem(sources, idx)
    source
  end

  defp expr({:in, _, [_left, []]}, _sources, _query) do
    "0=1"
  end

  defp expr({:in, _, [left, right]}, sources, query) when is_list(right) do
    args = intersperse_map(right, ?,, &expr(&1, sources, query))
    [expr(left, sources, query), " IN (", args, ?)]
  end

  defp expr({:in, _, [left, {:^, _, [idx, _length]}]}, sources, query) do
    [expr(left, sources, query), " IN (:", Integer.to_string(idx + 1), ?)]
  end

  defp expr({:in, _, [left, %Ecto.SubQuery{} = subquery]}, sources, query) do
    [expr(left, sources, query), " IN ", expr(subquery, sources, query)]
  end

  defp expr({:in, _, [left, right]}, sources, query) do
    [expr(left, sources, query), " = ANY(", expr(right, sources, query), ?)]
  end

  defp expr({:is_nil, _, [arg]}, sources, query) do
    [expr(arg, sources, query) | " IS NULL"]
  end

  defp expr({:not, _, [expr]}, sources, query) do
    ["NOT (", expr(expr, sources, query), ?)]
  end

  defp expr(%Ecto.SubQuery{query: query}, sources, parent_query) do
    query = put_in(query.aliases[@parent_as], {parent_query, sources})
    [?(, all(query, subquery_as_prefix(sources)), ?)]
  end

  defp expr({:fragment, _, [kw]}, _sources, query) when is_list(kw) or tuple_size(kw) == 3 do
    error!(query, "Oracle adapter does not support keyword or interpolated fragments")
  end

  defp expr({:fragment, _, parts}, sources, query) do
    Enum.map(parts, fn
      {:raw, part} -> part
      {:expr, expr} -> expr(expr, sources, query)
    end)
  end

  defp expr({:literal, _, [literal]}, _sources, _query) do
    quote_name(literal)
  end

  defp expr({:selected_as, _, [name]}, _sources, _query) do
    quote_name(name)
  end

  defp expr({:datetime_add, _, [datetime, count, interval]}, sources, query) do
    [
      expr(datetime, sources, query),
      " + INTERVAL '",
      expr(count, sources, query),
      "' ",
      interval
    ]
  end

  defp expr({:date_add, _, [date, count, interval]}, sources, query) do
    [
      expr(date, sources, query),
      " + INTERVAL '",
      expr(count, sources, query),
      "' ",
      interval
    ]
  end

  defp expr({:over, _, [agg, name]}, sources, query) when is_atom(name) do
    [expr(agg, sources, query), " OVER " | quote_name(name)]
  end

  defp expr({:over, _, [agg, kw]}, sources, query) do
    [expr(agg, sources, query), " OVER " | window_exprs(kw, sources, query)]
  end

  defp expr({:{}, _, elems}, sources, query) do
    [?(, intersperse_map(elems, ?,, &expr(&1, sources, query)), ?)]
  end

  defp expr({:count, _, []}, _sources, _query), do: "count(*)"

  defp expr({fun, _, args}, sources, query) when is_atom(fun) and is_list(args) do
    {modifier, args} =
      case args do
        [rest, :distinct] -> {"DISTINCT ", [rest]}
        _ -> {[], args}
      end

    case handle_call(fun, length(args)) do
      {:binary_op, op} ->
        [left, right] = args
        [op_to_binary(left, sources, query), op | op_to_binary(right, sources, query)]

      {:fun, fun} ->
        [fun, ?(, modifier, intersperse_map(args, ", ", &expr(&1, sources, query)), ?)]
    end
  end

  defp expr(list, sources, query) when is_list(list) do
    [?(, intersperse_map(list, ?,, &expr(&1, sources, query)), ?)]
  end

  defp expr(%Decimal{} = decimal, _sources, _query) do
    Decimal.to_string(decimal, :normal)
  end

  defp expr(%Ecto.Query.Tagged{value: binary, type: :binary}, _sources, _query)
       when is_binary(binary) do
    hex = Base.encode16(binary, case: :lower)
    ["'", hex, "'"]
  end

  defp expr(%Ecto.Query.Tagged{value: other, type: type}, sources, query) do
    ["CAST(", expr(other, sources, query), " AS ", ecto_to_db(type), ?)]
  end

  defp expr(nil, _sources, _query), do: "NULL"
  defp expr(true, _sources, _query), do: "1"
  defp expr(false, _sources, _query), do: "0"

  defp expr(literal, _sources, _query) when is_binary(literal) do
    [?', escape_string(literal), ?']
  end

  defp expr(literal, _sources, _query) when is_integer(literal) do
    Integer.to_string(literal)
  end

  defp expr(literal, _sources, _query) when is_float(literal) do
    Float.to_string(literal)
  end

  defp expr(expr, _sources, query) do
    error!(query, "unsupported expression: #{inspect(expr)}")
  end

  defp op_to_binary({op, _, [_, _]} = expr, sources, query) when op in @binary_ops do
    paren_expr(expr, sources, query)
  end

  defp op_to_binary({:is_nil, _, [_]} = expr, sources, query) do
    paren_expr(expr, sources, query)
  end

  defp op_to_binary(expr, sources, query) do
    expr(expr, sources, query)
  end

  defp handle_call(fun, _arity) when fun in @binary_ops do
    {:binary_op, op_to_sql(fun)}
  end

  defp handle_call(:+, 2), do: {:binary_op, " + "}
  defp handle_call(:-, 2), do: {:binary_op, " - "}
  defp handle_call(:*, 2), do: {:binary_op, " * "}
  defp handle_call(:/, 2), do: {:binary_op, " / "}

  defp handle_call(fun, _arity) do
    {:fun, Atom.to_string(fun)}
  end

  defp op_to_sql(:==), do: " = "
  defp op_to_sql(:!=), do: " != "
  defp op_to_sql(:<=), do: " <= "
  defp op_to_sql(:>=), do: " >= "
  defp op_to_sql(:<), do: " < "
  defp op_to_sql(:>), do: " > "
  defp op_to_sql(:and), do: " AND "
  defp op_to_sql(:or), do: " OR "
  defp op_to_sql(:like), do: " LIKE "
  defp op_to_sql(:ilike), do: " LIKE "

  # ============================================================
  # Type Mapping
  # ============================================================

  defp ecto_to_db(:id), do: "NUMBER(19)"
  defp ecto_to_db(:serial), do: "NUMBER(19)"
  defp ecto_to_db(:bigserial), do: "NUMBER(19)"
  defp ecto_to_db(:binary_id), do: "RAW(16)"
  defp ecto_to_db(:uuid), do: "RAW(16)"
  defp ecto_to_db(:string), do: "VARCHAR2"
  defp ecto_to_db(:binary), do: "BLOB"
  defp ecto_to_db(:raw), do: "RAW"
  defp ecto_to_db(:long_raw), do: "LONG RAW"
  defp ecto_to_db(:integer), do: "NUMBER(19)"
  defp ecto_to_db(:bigint), do: "NUMBER(19)"
  defp ecto_to_db(:float), do: "BINARY_DOUBLE"
  defp ecto_to_db(:binary_float), do: "BINARY_FLOAT"
  defp ecto_to_db(:binary_double), do: "BINARY_DOUBLE"
  defp ecto_to_db(:interval_day_to_second), do: "INTERVAL DAY TO SECOND"
  defp ecto_to_db(:interval_year_to_month), do: "INTERVAL YEAR TO MONTH"
  defp ecto_to_db(:decimal), do: "NUMBER"
  defp ecto_to_db(:boolean), do: "NUMBER(1)"
  defp ecto_to_db(:date), do: "DATE"
  defp ecto_to_db(:time), do: "TIMESTAMP"
  defp ecto_to_db(:time_usec), do: "TIMESTAMP(6)"
  defp ecto_to_db(:utc_datetime), do: "TIMESTAMP"
  defp ecto_to_db(:utc_datetime_usec), do: "TIMESTAMP(6)"
  defp ecto_to_db(:naive_datetime), do: "TIMESTAMP"
  defp ecto_to_db(:naive_datetime_usec), do: "TIMESTAMP(6)"
  defp ecto_to_db(:map), do: "CLOB"
  defp ecto_to_db({:map, _}), do: "CLOB"
  defp ecto_to_db(:text), do: "CLOB"
  defp ecto_to_db({:array, _}), do: raise("Oracle does not support arrays")
  defp ecto_to_db(other), do: Atom.to_string(other)

  # ============================================================
  # Name Quoting
  # ============================================================

  defp quote_name(name) when is_atom(name) do
    quote_name(Atom.to_string(name))
  end

  defp quote_name(name) when is_binary(name) do
    if String.contains?(name, "\"") do
      error!(nil, "bad literal/field/table name #{inspect(name)}")
    end

    [?", String.upcase(name), ?"]
  end

  defp quote_table(nil, name), do: quote_name(name)

  defp quote_table(prefix, name) do
    [quote_name(prefix), ?., quote_name(name)]
  end

  defp quote_qualified_name(name, sources, ix) do
    {_, source, _} = elem(sources, ix)
    [source, ?. | quote_name(name)]
  end

  # ============================================================
  # DDL Helpers
  # ============================================================

  defp column_definitions(table, columns) do
    intersperse_map(columns, ", ", &column_definition(table, &1))
  end

  defp column_definition(table, {:add, name, %Reference{} = ref, opts}) do
    [
      quote_name(name),
      ?\s,
      reference_column_type(ref.type, opts),
      column_options(opts),
      reference_expr(ref, table, name)
    ]
  end

  defp column_definition(_table, {:add, name, type, opts}) do
    [quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
  end

  defp column_change(table, {:add, name, %Reference{} = ref, opts}) do
    [
      "ADD ",
      quote_name(name),
      ?\s,
      reference_column_type(ref.type, opts),
      column_options(opts),
      reference_expr(ref, table, name)
    ]
  end

  defp column_change(_table, {:add, name, type, opts}) do
    ["ADD ", quote_name(name), ?\s, column_type(type, opts), column_options(opts)]
  end

  defp column_change(_table, {:modify, name, type, opts}) do
    ["MODIFY ", quote_name(name), ?\s, column_type(type, opts), modify_options(opts)]
  end

  defp column_change(_table, {:remove, name}) do
    ["DROP COLUMN ", quote_name(name)]
  end

  defp column_change(_table, {:remove, name, _type, _opts}) do
    ["DROP COLUMN ", quote_name(name)]
  end

  defp column_options(opts) do
    default = Keyword.get(opts, :default)
    null = Keyword.get(opts, :null)

    [default_expr(default), null_expr(null)]
  end

  defp modify_options(opts) do
    null = Keyword.get(opts, :null)
    [null_expr(null)]
  end

  defp null_expr(false), do: " NOT NULL"
  defp null_expr(true), do: " NULL"
  defp null_expr(_), do: []

  defp default_expr(nil), do: []

  defp default_expr(literal) when is_binary(literal) do
    [" DEFAULT '", escape_string(literal), ?']
  end

  defp default_expr(literal) when is_number(literal) do
    [" DEFAULT ", to_string(literal)]
  end

  defp default_expr(literal) when is_boolean(literal) do
    [" DEFAULT ", if(literal, do: "1", else: "0")]
  end

  defp default_expr({:fragment, expr}) do
    [" DEFAULT ", expr]
  end

  defp default_expr(expr) do
    raise ArgumentError, "unsupported default value: #{inspect(expr)}"
  end

  defp column_type(type, opts) do
    size = Keyword.get(opts, :size)
    precision = Keyword.get(opts, :precision)
    scale = Keyword.get(opts, :scale)

    type_name = ecto_to_db(type)

    cond do
      size -> [type_name, ?(, to_string(size), ?)]
      precision && scale -> [type_name, ?(, to_string(precision), ?,, to_string(scale), ?)]
      precision -> [type_name, ?(, to_string(precision), ?)]
      # Apply default size for string types
      type == :string -> [type_name, "(255)"]
      true -> type_name
    end
  end

  defp reference_column_type(:serial, _opts), do: "NUMBER(19)"
  defp reference_column_type(:bigserial, _opts), do: "NUMBER(19)"
  defp reference_column_type(type, opts), do: column_type(type, opts)

  defp reference_expr(%Reference{} = ref, table, name) do
    {_current_columns, reference_columns} =
      if is_nil(ref.with) do
        {[name], [ref.column]}
      else
        {[name | Keyword.keys(ref.with)], [ref.column | Keyword.values(ref.with)]}
      end

    [
      " CONSTRAINT ",
      reference_name(ref, table, name),
      " REFERENCES ",
      quote_table(ref.prefix || table.prefix, ref.table),
      ?(,
      intersperse_map(reference_columns, ?,, &quote_name/1),
      ?),
      reference_on_delete(ref.on_delete),
      reference_on_update(ref.on_update)
    ]
  end

  defp reference_name(%Reference{name: nil}, table, column) do
    quote_name("#{table.name}_#{column}_fkey")
  end

  defp reference_name(%Reference{name: name}, _table, _column) do
    quote_name(name)
  end

  defp reference_on_delete(:nothing), do: []
  defp reference_on_delete(:delete_all), do: " ON DELETE CASCADE"
  defp reference_on_delete(:nilify_all), do: " ON DELETE SET NULL"
  defp reference_on_delete(:restrict), do: []
  defp reference_on_delete(_), do: []

  defp reference_on_update(:nothing), do: []
  defp reference_on_update(:update_all), do: []
  defp reference_on_update(:nilify_all), do: []
  defp reference_on_update(_), do: []

  defp pk_definition(columns) do
    pks =
      for {:add, name, _, opts} <- columns,
          opts[:primary_key],
          do: name

    if pks != [] do
      [", PRIMARY KEY (", intersperse_map(pks, ", ", &quote_name/1), ")"]
    else
      []
    end
  end

  defp constraint_expr(%Ecto.Migration.Constraint{check: check}) when is_binary(check) do
    [" CHECK (", check, ")"]
  end

  defp constraint_expr(%Ecto.Migration.Constraint{exclude: exclude}) when is_binary(exclude) do
    raise ArgumentError, "Oracle does not support exclusion constraints"
  end

  defp index_expr(literal) when is_binary(literal), do: literal
  defp index_expr(literal) when is_atom(literal), do: quote_name(literal)

  defp options_expr(nil), do: []
  defp options_expr(options), do: [?\s, options]

  # ============================================================
  # Source/Name Helpers
  # ============================================================

  defp create_names(%{sources: sources}, as_prefix) do
    sources |> create_names(0, tuple_size(sources), as_prefix) |> List.to_tuple()
  end

  defp create_names(sources, pos, limit, as_prefix) when pos < limit do
    [create_name(sources, pos, as_prefix) | create_names(sources, pos + 1, limit, as_prefix)]
  end

  defp create_names(_sources, pos, limit, _as_prefix) when pos == limit do
    []
  end

  defp subquery_as_prefix(sources) do
    [?s | :erlang.element(tuple_size(sources), sources) |> elem(1)]
  end

  defp create_name(sources, pos, as_prefix) do
    case elem(sources, pos) do
      {:fragment, _, _} ->
        {nil, as_prefix ++ [?f | Integer.to_string(pos)], nil}

      {table, schema, prefix} ->
        name = as_prefix ++ [create_alias(table) | Integer.to_string(pos)]
        {quote_table(prefix, table), name, schema}

      %Ecto.SubQuery{} ->
        {nil, as_prefix ++ [?s | Integer.to_string(pos)], nil}
    end
  end

  defp create_alias(name) when is_atom(name) do
    create_alias(Atom.to_string(name))
  end

  defp create_alias(name) do
    [name |> String.first() |> String.downcase()]
  end

  defp get_source(query, sources, ix, source) do
    {expr, name, _schema} = elem(sources, ix)
    {expr || expr(source, sources, query), name}
  end

  defp prefix([], _query), do: []
  defp prefix(_prefix, %{prefix: nil}), do: []
  defp prefix(_prefix, %{prefix: prefix}), do: [quote_name(prefix), ?.]

  # ============================================================
  # Utility Functions
  # ============================================================

  defp hints([_ | _] = hints), do: [" " | Enum.intersperse(hints, " ")]
  defp hints([]), do: []

  defp if_do(true, value), do: value
  defp if_do(false, _value), do: []

  defp escape_string(value) when is_binary(value) do
    String.replace(value, "'", "''")
  end

  defp intersperse_map(list, separator, mapper)

  defp intersperse_map([], _separator, _mapper), do: []
  defp intersperse_map([elem], _separator, mapper), do: [mapper.(elem)]

  defp intersperse_map([elem | rest], separator, mapper) do
    [mapper.(elem), separator | intersperse_map(rest, separator, mapper)]
  end

  defp intersperse_reduce(list, separator, user_acc, reducer)

  defp intersperse_reduce([], _separator, user_acc, _reducer), do: {[], user_acc}

  defp intersperse_reduce([elem], _separator, user_acc, reducer) do
    {elem, user_acc} = reducer.(elem, user_acc)
    {[elem], user_acc}
  end

  defp intersperse_reduce([elem | rest], separator, user_acc, reducer) do
    {elem, user_acc} = reducer.(elem, user_acc)
    {rest, user_acc} = intersperse_reduce(rest, separator, user_acc, reducer)
    {[elem, separator | rest], user_acc}
  end

  defp error!(query, message) do
    raise Ecto.QueryError, query: query, message: message
  end

  # ============================================================
  # Required Behaviour Callbacks
  # ============================================================

  @impl true
  def ddl_logs(%Ecto.Migration.Table{}), do: []
  def ddl_logs(%Ecto.Migration.Index{}), do: []
  def ddl_logs(%Ecto.Migration.Constraint{}), do: []

  @impl true
  def table_exists_query(table) do
    {"SELECT COUNT(*) FROM user_tables WHERE table_name = :1", [String.upcase(table)]}
  end

  @impl true
  def to_constraints(%Ecto.Changeset{} = changeset, _opts) do
    # Extract constraint errors from Oracle error messages
    changeset
  end

  def to_constraints(%DBConnection.ConnectionError{}, _opts), do: []

  def to_constraints(%Inexora.Error{oracle_code: code, message: message}, _opts) do
    case code do
      # ORA-00001: unique constraint violated
      1 ->
        case Regex.run(~r/unique constraint \(.*\.(\w+)\) violated/i, message) do
          [_, constraint] -> [unique: String.downcase(constraint)]
          _ -> []
        end

      # ORA-02291: integrity constraint violated - parent key not found
      2291 ->
        case Regex.run(~r/integrity constraint \(.*\.(\w+)\) violated/i, message) do
          [_, constraint] -> [foreign_key: String.downcase(constraint)]
          _ -> []
        end

      # ORA-02292: integrity constraint violated - child record found
      2292 ->
        case Regex.run(~r/integrity constraint \(.*\.(\w+)\) violated/i, message) do
          [_, constraint] -> [foreign_key: String.downcase(constraint)]
          _ -> []
        end

      # ORA-02290: check constraint violated
      2290 ->
        case Regex.run(~r/check constraint \(.*\.(\w+)\) violated/i, message) do
          [_, constraint] -> [check: String.downcase(constraint)]
          _ -> []
        end

      _ ->
        []
    end
  end

  def to_constraints(_, _opts), do: []
end
