defmodule EcoSyncBackend.Repos do
  @moduledoc """
  Lógica de negocio para analizar repositorios GitHub.
  Determina la inactividad, encuentra forks abandonados y escanea secretos.
  """
  require Logger
  alias EcoSyncBackend.GitHub.Client, as: GitHubClient
  alias EcoSyncBackend.Scanner

  @doc """
  Analiza todos los repositorios y devuelve los considerados inactivos.
  """
  def get_inactive_repos(client, months \\ 6, filters \\ %{}) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, -(months * 30 * 24 * 60 * 60), :second)

    all_repos = GitHubClient.get_repos(client)

    inactive = 
      all_repos
      |> Enum.filter(&matches_filters?(&1, filters))
      |> Enum.reduce([], fn repo, acc ->
        owner = get_in(repo, ["owner", "login"])
        name = repo["name"]

        # Fast path: pushed_at
        pushed_at = parse_datetime(repo["pushed_at"])
        
        if pushed_at && DateTime.compare(pushed_at, threshold) != :lt do
          acc # Reciente, omitir
        else
          # Slow path: real last commit
          last_commit = GitHubClient.get_last_commit_date(client, owner, name) || pushed_at

          if last_commit && DateTime.compare(last_commit, threshold) == :lt do
            days_inactive = DateTime.diff(now, last_commit, :day)
            
            repo_info = %{
              name: name,
              url: repo["html_url"],
              last_commit_date: last_commit,
              days_inactive: days_inactive,
              language: repo["language"],
              visibility: if(repo["private"], do: "private", else: "public")
            }
            [repo_info | acc]
          else
            acc
          end
        end
      end)
      |> Enum.sort_by(& &1.days_inactive, :desc)

    %{
      total_repos: length(all_repos),
      inactive_count: length(inactive),
      inactivity_threshold_months: months,
      repos: inactive
    }
  end

  @doc """
  Genera una auditoría de seguridad para la cuenta de GitHub.
  Analiza llaves SSH, Gists públicos e instalaciones de aplicaciones.
  """
  def generate_security_audit(client, unused_months_threshold \\ 6) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, -(unused_months_threshold * 30 * 24 * 60 * 60), :second)

    # 1. SSH Keys
    ssh_keys = GitHubClient.get_ssh_keys(client)
    old_ssh_keys = 
      Enum.reduce(ssh_keys, [], fn key, acc ->
        created_at = parse_datetime(key["created_at"])
        last_used = parse_datetime(key["last_used"])

        is_old = 
          cond do
            last_used && DateTime.compare(last_used, threshold) == :lt -> true
            is_nil(last_used) && created_at && DateTime.compare(created_at, threshold) == :lt -> true
            true -> false
          end

        if is_old do
          [%{
            id: key["id"],
            title: key["title"],
            created_at: created_at,
            last_used: last_used
          } | acc]
        else
          acc
        end
      end)

    # 2. Public Gists
    gists = GitHubClient.get_public_gists(client)
    public_gists_count = Enum.count(gists, & &1["public"] == true)

    # 3. App Installations
    installations = GitHubClient.get_user_installations(client)
    installed_apps = 
      Enum.map(installations, fn app ->
        %{
          id: app["id"],
          app_slug: app["app_slug"] || "unknown",
          repository_selection: app["repository_selection"],
          permissions: app["permissions"]
        }
      end)

    %{
      old_ssh_keys: old_ssh_keys,
      public_gists_count: public_gists_count,
      installed_apps: installed_apps
    }
  end

  @doc """
  Busca 'dead forks': repositorios que son forks y no han sido actualizados.
  """
  def get_dead_forks(client, months \\ 6) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, -(months * 30 * 24 * 60 * 60), :second)

    all_repos = GitHubClient.get_repos(client)
    forks = Enum.filter(all_repos, & &1["fork"])

    dead_forks = 
      forks
      |> Enum.reduce([], fn repo, acc ->
        owner = get_in(repo, ["owner", "login"])
        name = repo["name"]

        pushed_at = parse_datetime(repo["pushed_at"])

        if pushed_at && DateTime.compare(pushed_at, threshold) != :lt do
          acc
        else
          last_commit = GitHubClient.get_last_commit_date(client, owner, name) || pushed_at
          
          if last_commit && DateTime.compare(last_commit, threshold) == :lt do
            # Obtenemos info del padre para enriquecer
            # Nota: En una versión scalable usaríamos concurrencia aquí (Task.async_stream)
            repo_details = GitHubClient.get_repo_details(client, owner, name)
            parent = repo_details["parent"] || %{}

            fork_info = %{
              name: name,
              url: repo["html_url"],
              parent_name: parent["full_name"] || "Unknown Parent",
              parent_url: parent["html_url"] || "",
              last_commit_date: last_commit
            }
            [fork_info | acc]
          else
            acc
          end
        end
      end)

    %{
      total_forks: length(forks),
      dead_forks_count: length(dead_forks),
      forks: dead_forks
    }
  end

  @doc """
  Escanea repositorios en busca de secretos expuestos.
  """
  def scan_repositories_for_secrets(client, repo_name \\ nil) do
    repos_to_scan = 
      if repo_name do
        GitHubClient.get_repos(client) 
        |> Enum.filter(&(String.downcase(&1["name"]) == String.downcase(repo_name)))
      else
        GitHubClient.get_repos(client)
      end

    text_extensions = ~w(.py .js .ts .jsx .tsx .env .json .yml .yaml .txt .md .sh .bash .conf .ini .cfg .xml)

    results = 
      repos_to_scan
      |> Enum.reduce([], fn repo, acc ->
        owner = get_in(repo, ["owner", "login"])
        name = repo["name"]
        
        # Escaneo simple limitado a profundidad 2 para performance
        findings = scan_recursive(client, owner, name, "", 0, text_extensions, [])
        
        if findings != [] do
          [%{repo_name: name, findings: findings} | acc]
        else
          acc
        end
      end)

    %{
      total_repos_scanned: length(repos_to_scan),
      findings_count: Enum.reduce(results, 0, fn r, acc -> acc + length(r.findings) end),
      repos: results
    }
  end

  # Helpers

  defp scan_recursive(client, owner, repo, path, depth, extensions, acc) when depth <= 2 do
    case EcoSyncBackend.GitHub.Client.get_repo_contents(client, owner, repo, path) do
      items when is_list(items) ->
        Enum.reduce(items, acc, fn item, inner_acc ->
          cond do
            item["type"] == "dir" && item["name"] not in ~w(.git node_modules venv __pycache__) ->
              scan_recursive(client, owner, repo, item["path"], depth + 1, extensions, inner_acc)
            
            item["type"] == "file" ->
              ext = Path.extname(item["name"])
              if ext in extensions || String.starts_with?(item["name"], ".env") do
                case EcoSyncBackend.GitHub.Client.get_file_content_from_url(client, item["download_url"]) do
                  content when is_binary(content) ->
                    findings = Scanner.scan_content(content)
                    findings_with_path = Enum.map(findings, &Map.put(&1, :file_path, item["path"]))
                    inner_acc ++ findings_with_path
                  _ -> inner_acc
                end
              else
                inner_acc
              end

            true -> inner_acc
          end
        end)
      _ -> acc
    end
  end
  defp scan_recursive(_, _, _, _, _, _, acc), do: acc

  def matches_filters?(repo, filters) do
    lang_match = 
      case filters[:language] do
        nil -> true
        lang -> String.downcase(repo["language"] || "") == String.downcase(lang)
      end

    vis_match = 
      case filters[:visibility] do
        nil -> true
        vis -> 
          repo_vis = if repo["private"], do: "private", else: "public"
          String.downcase(repo_vis) == String.downcase(vis)
      end

    lang_match && vis_match
  end

  def parse_datetime(nil), do: nil
  def parse_datetime(date_str) do
    case DateTime.from_iso8601(String.replace(date_str, "Z", "+00:00")) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
