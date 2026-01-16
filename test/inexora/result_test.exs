defmodule Inexora.ResultTest do
  use ExUnit.Case, async: true

  alias Inexora.Result

  describe "new_select/2" do
    test "creates Result for SELECT with columns and rows" do
      columns = ["ID", "NAME"]
      rows = [[1, "Alice"], [2, "Bob"]]

      result = Result.new_select(columns, rows)

      assert %Result{} = result
      assert result.columns == ["ID", "NAME"]
      assert result.rows == [[1, "Alice"], [2, "Bob"]]
      assert result.num_rows == 2
    end

    test "handles empty result set" do
      result = Result.new_select(["ID"], [])

      assert result.columns == ["ID"]
      assert result.rows == []
      assert result.num_rows == 0
    end
  end

  describe "new_dml/1" do
    test "creates Result for INSERT/UPDATE/DELETE" do
      result = Result.new_dml(5)

      assert %Result{} = result
      assert result.columns == nil
      assert result.rows == nil
      assert result.num_rows == 5
    end

    test "handles zero affected rows" do
      result = Result.new_dml(0)
      assert result.num_rows == 0
    end
  end
end
