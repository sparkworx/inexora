defmodule Inexora.QueryTest do
  use ExUnit.Case, async: true

  alias Inexora.Query

  describe "new/1" do
    test "creates a Query struct from SQL string" do
      query = Query.new("SELECT 1 FROM dual")

      assert %Query{} = query
      assert query.sql == "SELECT 1 FROM dual"
      assert query.statement == nil
      assert query.num_columns == nil
      assert query.columns == nil
    end
  end

  describe "String.Chars implementation" do
    test "converts Query to SQL string" do
      query = Query.new("SELECT * FROM users")
      assert to_string(query) == "SELECT * FROM users"
    end
  end

  describe "DBConnection.Query implementation" do
    test "parse returns query unchanged" do
      query = Query.new("SELECT 1")
      assert DBConnection.Query.parse(query, []) == query
    end

    test "describe returns query unchanged" do
      query = Query.new("SELECT 1")
      assert DBConnection.Query.describe(query, []) == query
    end

    test "encode passes params through" do
      query = Query.new("SELECT :1")
      params = ["test", 123, nil]
      assert DBConnection.Query.encode(query, params, []) == params
    end

    test "decode passes result through" do
      query = Query.new("SELECT 1")
      result = %{columns: ["COL1"], rows: [[1]]}
      assert DBConnection.Query.decode(query, result, []) == result
    end
  end
end
