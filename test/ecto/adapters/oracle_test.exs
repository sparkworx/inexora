defmodule Ecto.Adapters.OracleTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Ecto.Adapters.Oracle.Connection, as: SQL

  defmodule Schema do
    use Ecto.Schema

    schema "users" do
      field :name, :string
      field :email, :string
      field :age, :integer
      field :active, :boolean
    end
  end

  defmodule Schema2 do
    use Ecto.Schema

    schema "posts" do
      field :title, :string
      field :user_id, :integer
    end
  end

  defp plan(query, operation \\ :all) do
    {query, _cast_params, _dump_params} =
      Ecto.Adapter.Queryable.plan_query(operation, Ecto.Adapters.Oracle, query)

    query
  end

  defp all(query) do
    query
    |> SQL.all()
    |> IO.iodata_to_binary()
  end

  defp update_all(query) do
    query
    |> SQL.update_all()
    |> IO.iodata_to_binary()
  end

  defp delete_all(query) do
    query
    |> SQL.delete_all()
    |> IO.iodata_to_binary()
  end

  defp insert(prefix, table, header, rows, on_conflict, returning, placeholders \\ []) do
    SQL.insert(prefix, table, header, rows, on_conflict, returning, placeholders)
    |> IO.iodata_to_binary()
  end

  defp update(prefix, table, fields, filters, returning) do
    SQL.update(prefix, table, fields, filters, returning)
    |> IO.iodata_to_binary()
  end

  defp delete(prefix, table, filters, returning) do
    SQL.delete(prefix, table, filters, returning)
    |> IO.iodata_to_binary()
  end

  describe "all/1" do
    test "simple select" do
      query = from(u in Schema, select: u.name) |> plan()
      result = all(query)
      assert result =~ "SELECT"
      assert result =~ ~s("NAME")
      assert result =~ ~s(FROM "USERS")
    end

    test "select with where" do
      query = from(u in Schema, where: u.active == true, select: u.name) |> plan()
      result = all(query)
      assert result =~ ~s("ACTIVE" = 1)
    end

    test "select with multiple conditions" do
      query = from(u in Schema, where: u.active == true and u.age > 18, select: u.name) |> plan()
      result = all(query)
      assert result =~ "AND"
    end

    test "select with limit" do
      query = from(u in Schema, limit: 10, select: u.name) |> plan()
      result = all(query)
      assert result =~ "FETCH FIRST 10 ROWS ONLY"
    end

    test "select with offset" do
      query = from(u in Schema, offset: 5, select: u.name) |> plan()
      result = all(query)
      assert result =~ "OFFSET 5 ROWS"
    end

    test "select with order by" do
      query = from(u in Schema, order_by: u.name, select: u.name) |> plan()
      result = all(query)
      assert result =~ "ORDER BY"
    end

    test "select with order by desc" do
      query = from(u in Schema, order_by: [desc: u.name], select: u.name) |> plan()
      result = all(query)
      assert result =~ "DESC"
    end

    test "select with distinct" do
      query = from(u in Schema, distinct: true, select: u.name) |> plan()
      result = all(query)
      assert result =~ "DISTINCT"
    end

    test "select with inner join" do
      query = from(u in Schema, join: p in Schema2, on: p.user_id == u.id, select: u.name) |> plan()
      result = all(query)
      assert result =~ "INNER JOIN"
    end

    test "select with left join" do
      query = from(u in Schema, left_join: p in Schema2, on: p.user_id == u.id, select: u.name) |> plan()
      result = all(query)
      assert result =~ "LEFT OUTER JOIN"
    end

    test "select with group by" do
      query = from(u in Schema, group_by: u.active, select: {u.active, count()}) |> plan()
      result = all(query)
      assert result =~ "GROUP BY"
    end

    test "select count" do
      query = from(u in Schema, select: count()) |> plan()
      result = all(query)
      assert result =~ "count(*)"
    end

    test "select with parameter binding" do
      query = from(u in Schema, where: u.name == ^"John", select: u.name) |> plan()
      result = all(query)
      assert result =~ ":1"
    end
  end

  describe "update_all/1" do
    test "simple update" do
      query = from(u in Schema, update: [set: [name: "updated"]]) |> plan(:update_all)
      result = update_all(query)
      assert result =~ "UPDATE"
      assert result =~ ~s("NAME" = )
    end

    test "update with where" do
      query = from(u in Schema, where: u.active == true, update: [set: [name: "updated"]]) |> plan(:update_all)
      result = update_all(query)
      assert result =~ "WHERE"
    end

    test "update with increment" do
      query = from(u in Schema, update: [inc: [age: 1]]) |> plan(:update_all)
      result = update_all(query)
      assert result =~ ~s("AGE" = )
      assert result =~ "+ "
    end
  end

  describe "delete_all/1" do
    test "simple delete" do
      query = from(u in Schema) |> plan(:delete_all)
      result = delete_all(query)
      assert result =~ "DELETE FROM"
    end

    test "delete with where" do
      query = from(u in Schema, where: u.active == false) |> plan(:delete_all)
      result = delete_all(query)
      assert result =~ "WHERE"
    end
  end

  describe "insert/7" do
    test "simple insert" do
      result = insert(nil, "users", [:name, :email], [[1, 2]], {:raise, [], []}, [])
      assert result =~ "INSERT INTO"
      assert result =~ ~s("USERS")
      assert result =~ ~s("NAME")
      assert result =~ ~s("EMAIL")
      assert result =~ "VALUES"
      assert result =~ ":1"
      assert result =~ ":2"
    end

    test "insert with returning" do
      result = insert(nil, "users", [:name], [[1]], {:raise, [], []}, [:id])
      assert result =~ "RETURNING"
      assert result =~ ~s("ID")
    end
  end

  describe "update/5" do
    test "simple update" do
      result = update(nil, "users", [:name, :email], [id: 1], [])
      assert result =~ "UPDATE"
      assert result =~ ~s("USERS")
      assert result =~ "SET"
      assert result =~ "WHERE"
    end

    test "update with returning" do
      result = update(nil, "users", [:name], [id: 1], [:id, :name])
      assert result =~ "RETURNING"
    end
  end

  describe "delete/4" do
    test "simple delete" do
      result = delete(nil, "users", [id: 1], [])
      assert result =~ "DELETE FROM"
      assert result =~ ~s("USERS")
      assert result =~ "WHERE"
    end

    test "delete with returning" do
      result = delete(nil, "users", [id: 1], [:id])
      assert result =~ "RETURNING"
    end
  end

  describe "type mapping" do
    test "generates correct DDL for types" do
      columns = [
        {:add, :id, :bigserial, [primary_key: true]},
        {:add, :name, :string, [size: 100]},
        {:add, :description, :text, []},
        {:add, :count, :integer, []},
        {:add, :price, :decimal, [precision: 10, scale: 2]},
        {:add, :active, :boolean, []},
        {:add, :created_at, :naive_datetime, []}
      ]

      table = %Ecto.Migration.Table{name: "products"}
      [ddl] = SQL.execute_ddl({:create, table, columns})
      result = IO.iodata_to_binary(ddl)

      assert result =~ "CREATE TABLE"
      assert result =~ ~s("PRODUCTS")
      assert result =~ "NUMBER(19)"  # bigserial
      assert result =~ "VARCHAR2(100)"  # string with size
      assert result =~ "CLOB"  # text
      assert result =~ "NUMBER(10,2)"  # decimal with precision/scale
      assert result =~ "NUMBER(1)"  # boolean
      assert result =~ "TIMESTAMP"  # naive_datetime
      assert result =~ "PRIMARY KEY"
    end
  end
end
