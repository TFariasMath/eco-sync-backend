defmodule EcoSyncBackendWeb.RepoController do
  use EcoSyncBackendWeb, :controller
  alias EcoSyncBackend.GitHub.Client, as: GitHubClient
  alias EcoSyncBackend.Repos

  @doc """
  Lista repositorios inactivos.
  """
  def list_inactive_repos(conn, params) do
    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      months = parse_int(params["months"], 6)
      filters = %{language: params["language"], visibility: params["visibility"]}

      result = Repos.get_inactive_repos(client, months, filters)
      json(conn, result)
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  @doc """
  Escanea secretos en los repositorios.
  """
  def list_secrets(conn, params) do
    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      result = Repos.scan_repositories_for_secrets(client, params["repo_name"])
      json(conn, result)
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  @doc """
  Lista forks abandonados.
  """
  def list_dead_forks(conn, params) do
    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      months = parse_int(params["months"], 6)
      result = Repos.get_dead_forks(client, months)
      json(conn, result)
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  @doc """
  Genera una auditoría de seguridad de la cuenta.
  """
  def security_audit(conn, params) do
    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      months = parse_int(params["months"], 6)
      result = Repos.generate_security_audit(client, months)
      json(conn, result)
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  @doc """
  Vista detallada para el dashboard principal.
  Porta la lógica compleja de app/routes.py:repos_overview()
  Usa Task.async_stream para paralelizar las llamadas a GitHub API.
  """
  def repos_overview(conn, _params) do
    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      user = GitHubClient.get_user_profile(client)
      all_repos = GitHubClient.get_repos(client)

      enriched =
        all_repos
        |> Task.async_stream(
          fn repo ->
            owner = get_in(repo, ["owner", "login"])
            name = repo["name"]

            branches = GitHubClient.get_branches(client, owner, name)
            commits = GitHubClient.get_recent_commits_details(client, owner, name)

            last_commit_date =
              case commits do
                [first | _] -> first["date"]
                _ -> repo["pushed_at"]
              end

            days_inactive = calc_days_inactive(last_commit_date)

            %{
              name: name,
              url: repo["html_url"],
              description: repo["description"],
              language: repo["language"],
              visibility: if(repo["private"], do: "private", else: "public"),
              is_fork: repo["fork"],
              is_archived: repo["archived"],
              stars: repo["stargazers_count"],
              forks_count: repo["forks_count"],
              open_issues: repo["open_issues_count"],
              size_kb: repo["size"],
              default_branch: repo["default_branch"],
              topics: repo["topics"] || [],
              created_at: repo["created_at"],
              pushed_at: repo["pushed_at"],
              last_commit_date: last_commit_date,
              days_inactive: days_inactive,
              branches_count: length(branches),
              recent_commits: commits
            }
          end, max_concurrency: 10, timeout: 30_000)
        |> Enum.map(fn {:ok, result} -> result end)
        |> Enum.sort_by(& &1.days_inactive, {:desc, 0})

      json(conn, %{
        user: %{
          login: user["login"],
          name: user["name"],
          avatar_url: user["avatar_url"],
          html_url: user["html_url"],
          public_repos: user["public_repos"],
          followers: user["followers"],
          following: user["following"],
          bio: user["bio"]
        },
        total_repos: length(enriched),
        repos: enriched
      })
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  @doc """
  Archiva o borra un repositorio individual.
  """
  def manage_repo(conn, %{"repo_name" => name, "confirm" => true} = params) do
    action = params["action"]

    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      # En GitHub API, necesitamos el owner
      user = GitHubClient.get_user_profile(client)
      owner = user["login"]

      case action do
        "archive" ->
          GitHubClient.archive_repo(client, owner, name)

          json(conn, %{
            status: "success",
            message: "Repository archived successfully.",
            repo_name: name
          })

        "delete" ->
          GitHubClient.delete_repo(client, owner, name)
          EcoSyncBackend.AuditLogger.log_deletion(owner, name, "SUCCESS")

          json(conn, %{
            status: "success",
            message: "Repository deleted successfully.",
            repo_name: name
          })

        _ ->
          conn |> put_status(400) |> json(%{error: "Invalid action"})
      end
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
      _ -> conn |> put_status(400) |> json(%{error: "Confirmation required"})
    end
  end

  @doc """
  Borrado masivo de repositorios.
  """
  def bulk_delete(conn, %{"confirm" => true} = params) do
    with {:ok, token} <- get_token(conn),
         client <- GitHubClient.new(token) do
      user = GitHubClient.get_user_profile(client)
      owner = user["login"]

      # Determinar objetivos
      target_names =
        if params["delete_all_candidates"] do
          # Por ahora simplificamos: el frontend suele enviar nombres o pide borrar candidatos
          result = Repos.get_dead_forks(client)
          Enum.map(result.forks, & &1.name)
        else
          params["repo_names"] || []
        end

      results =
        Enum.map(target_names, fn name ->
          try do
            GitHubClient.delete_repo(client, owner, name)
            EcoSyncBackend.AuditLogger.log_deletion(owner, name, "SUCCESS (BULK)")
            %{repo_name: name, status: "deleted"}
          rescue
            e ->
              EcoSyncBackend.AuditLogger.log_deletion(owner, name, "FAILED (BULK)")
              %{repo_name: name, status: "failed", detail: inspect(e)}
          end
        end)

      json(conn, %{
        mode: if(params["delete_all_candidates"], do: "automatic", else: "manual"),
        total_requested: length(target_names),
        deleted_count: Enum.count(results, &(&1.status == "deleted")),
        failed_count: Enum.count(results, &(&1.status == "failed")),
        results: results
      })
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
      _ -> conn |> put_status(400) |> json(%{error: "Confirmation required"})
    end
  end

  # Helpers

  defp get_token(conn) do
    token =
      get_session(conn, :access_token) ||
        get_req_header(conn, "authorization") |> List.first() |> clean_token()

    if token, do: {:ok, token}, else: {:error, :unauthorized}
  end

  defp clean_token(nil), do: nil
  defp clean_token("Bearer " <> token), do: token
  defp clean_token("token " <> token), do: token
  defp clean_token(token), do: token

  defp error_unauthorized(conn) do
    conn
    |> put_status(401)
    |> json(%{detail: "Unauthorized. Please login via /auth/github first."})
  end

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {i, _} -> i
      _ -> default
    end
  end

  defp parse_int(val, _), do: val

  defp calc_days_inactive(nil), do: 0

  defp calc_days_inactive(date_str) do
    with {:ok, dt, _} <- DateTime.from_iso8601(String.replace(date_str, "Z", "+00:00")) do
      DateTime.diff(DateTime.utc_now(), dt, :day)
    else
      _ -> 0
    end
  end
end
