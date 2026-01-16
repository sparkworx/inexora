defmodule Ecto.Adapters.OracleIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :oracle_database

  defmodule TestRepo do
    use Ecto.Repo,
      otp_app: :inexora,
      adapter: Ecto.Adapters.Oracle
  end

  defmodule User do
    use Ecto.Schema

    @primary_key {:id, :integer, autogenerate: false}
    schema "ecto_test_users" do
      field :name, :string
      field :email, :string
      field :age, :integer
      field :active, :boolean
    end
  end

  setup_all do
    opts = [
      username: System.get_env("ORACLE_USER", "inexora"),
      password: System.get_env("ORACLE_PASSWORD", "Welcome4321"),
      database: System.get_env("ORACLE_DATABASE", "localhost:1521/FREEPDB1"),
      pool_size: 1
    ]

    Application.put_env(:inexora, TestRepo, opts)

    {:ok, pid} = TestRepo.start_link()

    # Create test table
    setup_result = TestRepo.query("""
      DECLARE
        table_exists NUMBER;
      BEGIN
        SELECT COUNT(*) INTO table_exists FROM user_tables WHERE table_name = 'ECTO_TEST_USERS';
        IF table_exists > 0 THEN
          EXECUTE IMMEDIATE 'DROP TABLE ecto_test_users';
        END IF;
        EXECUTE IMMEDIATE 'CREATE TABLE ecto_test_users (
          id NUMBER(19) PRIMARY KEY,
          name VARCHAR2(255),
          email VARCHAR2(255),
          age NUMBER(19),
          active NUMBER(1)
        )';
      END;
    """)

    case setup_result do
      {:ok, _} ->
        # Insert initial test data
        TestRepo.query("""
          INSERT INTO ecto_test_users (id, name, email, age, active)
          VALUES (1, 'Alice', 'alice@example.com', 30, 1)
        """)

        on_exit(fn ->
          # Clean up test table if repo is still running
          try do
            TestRepo.query("DROP TABLE ecto_test_users")
          rescue
            _ -> :ok
          catch
            :exit, _ -> :ok
          end

          # Stop repo if still alive
          if Process.alive?(pid) do
            GenServer.stop(pid)
          end
        end)

        {:ok, repo: TestRepo}

      {:error, error} ->
        GenServer.stop(pid)
        {:error, "Failed to setup test table: #{inspect(error)}"}
    end
  end

  describe "Repo.query/2" do
    test "executes raw SQL query" do
      {:ok, result} = TestRepo.query("SELECT 1 + 1 AS answer FROM dual")

      assert result.num_rows == 1
      assert result.columns == ["ANSWER"]
      assert [[val]] = result.rows
      assert Decimal.equal?(val, Decimal.new(2))
    end

    test "executes query with parameters" do
      {:ok, result} = TestRepo.query("SELECT :1 AS val FROM dual", [42])

      assert result.num_rows == 1
      assert [[val]] = result.rows
      assert Decimal.equal?(val, Decimal.new(42))
    end
  end

  describe "Repo.insert/2" do
    test "inserts a record" do
      user = %User{id: 10, name: "Diana", email: "diana@example.com", age: 28, active: true}

      {:ok, inserted} = TestRepo.insert(user)

      assert inserted.id == 10
      assert inserted.name == "Diana"
    end

    test "inserts multiple records" do
      user2 = %User{id: 2, name: "Bob", email: "bob@example.com", age: 25, active: true}
      user3 = %User{id: 3, name: "Charlie", email: "charlie@example.com", age: 35, active: false}

      {:ok, _} = TestRepo.insert(user2)
      {:ok, _} = TestRepo.insert(user3)

      # Verify they exist
      {:ok, result} = TestRepo.query("SELECT COUNT(*) FROM ecto_test_users WHERE id IN (2, 3)")
      assert [[count]] = result.rows
      assert Decimal.equal?(count, Decimal.new(2))
    end
  end

  describe "Repo.all/2" do
    test "retrieves all records" do
      import Ecto.Query

      users = TestRepo.all(from u in User)

      assert length(users) >= 1
      assert Enum.all?(users, &is_struct(&1, User))
    end

    test "retrieves records with where clause" do
      import Ecto.Query

      users = TestRepo.all(from u in User, where: u.active == true)

      assert Enum.all?(users, fn u -> u.active == true end)
    end

    test "retrieves records with select" do
      import Ecto.Query

      names = TestRepo.all(from u in User, select: u.name)

      assert is_list(names)
      assert Enum.all?(names, &is_binary/1)
    end

    test "retrieves records with order by" do
      import Ecto.Query

      users = TestRepo.all(from u in User, order_by: [asc: u.name])

      names = Enum.map(users, & &1.name)
      assert names == Enum.sort(names)
    end

    test "retrieves records with limit" do
      import Ecto.Query

      users = TestRepo.all(from u in User, limit: 2)

      assert length(users) <= 2
    end
  end

  describe "Repo.one/2" do
    test "retrieves single record" do
      import Ecto.Query

      user = TestRepo.one(from u in User, where: u.id == 1)

      assert user.id == 1
      assert user.name == "Alice"
    end

    test "returns nil when no match" do
      import Ecto.Query

      user = TestRepo.one(from u in User, where: u.id == 99999)

      assert user == nil
    end
  end

  describe "Repo.get/3" do
    test "retrieves record by primary key" do
      user = TestRepo.get(User, 1)

      assert user.id == 1
      assert user.name == "Alice"
    end

    test "returns nil for non-existent record" do
      user = TestRepo.get(User, 99999)

      assert user == nil
    end
  end

  describe "Repo.update/2" do
    test "updates a record" do
      import Ecto.Changeset

      # Create a dedicated record for this test to avoid conflicts
      {:ok, user} = TestRepo.insert(%User{
        id: 50,
        name: "UpdateTest",
        email: "update@example.com",
        age: 40,
        active: true
      })

      changeset = change(user, name: "UpdateTest Updated")

      {:ok, updated} = TestRepo.update(changeset)

      assert updated.name == "UpdateTest Updated"

      # Verify in database
      reloaded = TestRepo.get(User, 50)
      assert reloaded.name == "UpdateTest Updated"
    end
  end

  describe "Repo.delete/2" do
    test "deletes a record" do
      # Insert a record to delete
      user = %User{id: 100, name: "ToDelete", email: "delete@example.com", age: 20, active: false}
      {:ok, inserted} = TestRepo.insert(user)

      # Delete it
      {:ok, deleted} = TestRepo.delete(inserted)

      assert deleted.id == 100

      # Verify it's gone
      assert TestRepo.get(User, 100) == nil
    end
  end

  describe "Repo.aggregate/3" do
    test "counts records" do
      import Ecto.Query

      count = TestRepo.aggregate(User, :count)

      # Oracle returns NUMBER for count(*), which becomes Decimal
      # Convert to integer for assertion
      count_int = if is_integer(count), do: count, else: Decimal.to_integer(count)
      assert count_int >= 1
    end

    test "calculates sum" do
      import Ecto.Query

      sum = TestRepo.aggregate(from(u in User, where: u.active == true), :sum, :age)

      assert is_number(sum) or is_nil(sum) or match?(%Decimal{}, sum)
    end
  end

  describe "Repo.update_all/2" do
    test "updates multiple records" do
      import Ecto.Query

      # First, set up some data
      TestRepo.query("UPDATE ecto_test_users SET age = 25 WHERE id IN (2, 3)")

      # Update with Ecto
      {count, nil} = TestRepo.update_all(
        from(u in User, where: u.id in [2, 3]),
        set: [age: 99]
      )

      assert count >= 0

      # Verify
      {:ok, result} = TestRepo.query("SELECT age FROM ecto_test_users WHERE id IN (2, 3)")
      ages = Enum.map(result.rows, fn [age] -> age end)
      assert Enum.all?(ages, fn age -> Decimal.equal?(age, Decimal.new(99)) end)
    end
  end

  describe "Repo.delete_all/2" do
    test "deletes multiple records" do
      import Ecto.Query

      # Insert some records to delete
      TestRepo.query("INSERT INTO ecto_test_users (id, name, email, age, active) VALUES (200, 'Del1', 'del1@test.com', 1, 0)")
      TestRepo.query("INSERT INTO ecto_test_users (id, name, email, age, active) VALUES (201, 'Del2', 'del2@test.com', 1, 0)")

      # Delete with Ecto
      {count, nil} = TestRepo.delete_all(from u in User, where: u.id >= 200)

      assert count >= 2

      # Verify they're gone
      {:ok, result} = TestRepo.query("SELECT COUNT(*) FROM ecto_test_users WHERE id >= 200")
      assert [[remaining]] = result.rows
      assert Decimal.equal?(remaining, Decimal.new(0))
    end
  end
end
