defmodule EcoSyncBackend.GitHub.ClientTest do
  use ExUnit.Case, async: true
  alias EcoSyncBackend.GitHub.Client

  import Req.Test
  import Plug.Conn

  setup do
    # Registramos un stub para las peticiones de GitHub
    stub(GitHubMock, fn conn ->
      case conn.request_path do
        "/user" ->
          json(conn, %{"login" => "testuser", "name" => "Test User"})
        "/user/repos" ->
          json(conn, [%{"name" => "repo1", "fork" => false, "pushed_at" => "2024-01-01T00:00:00Z", "owner" => %{"login" => "testuser"}}])
        "/repos/testuser/repo1/commits" ->
          json(conn, [%{"sha" => "abcdef12345", "commit" => %{"message" => "First commit", "author" => %{"name" => "Test", "date" => "2024-01-01T00:00:00Z"}}}])
        _ ->
          conn
          |> put_status(404)
          |> json(%{"message" => "Not Found"})
      end
    end)
    :ok
  end

  test "get_user_profile returns parsed profile" do
    # Configuramos el cliente para usar el mock
    client = Client.new("fake_token")
    client = %{client | req: Req.update(client.req, plug: {Req.Test, GitHubMock})}

    result = Client.get_user_profile(client)
    assert result["login"] == "testuser"
    assert result["name"] == "Test User"
  end

  test "get_repos returns repositories list" do
    client = Client.new("fake_token")
    client = %{client | req: Req.update(client.req, plug: {Req.Test, GitHubMock})}

    repos = Client.get_repos(client)
    assert is_list(repos)
    assert length(repos) == 1
    assert List.first(repos)["name"] == "repo1"
  end

  test "get_recent_commits_details returns simplified commit info" do
    client = Client.new("fake_token")
    client = %{client | req: Req.update(client.req, plug: {Req.Test, GitHubMock})}

    commits = Client.get_recent_commits_details(client, "testuser", "repo1")
    assert length(commits) == 1
    assert List.first(commits)["sha"] == "abcdef1"
    assert List.first(commits)["message"] == "First commit"
  end
end
