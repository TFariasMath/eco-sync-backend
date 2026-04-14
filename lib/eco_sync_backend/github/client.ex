defmodule EcoSyncBackend.GitHub.Client do
  @moduledoc """
  Cliente para interactuar con la API de GitHub v3 usando Req.
  Implementa manejo de paginación y mapeado de datos igual al cliente original en Python.
  """
  require Logger

  @api_base "https://api.github.com"

  defstruct [:token, :req]

  def new(token) do
    req = Req.new(
      base_url: @api_base,
      headers: [
        {"authorization", "token #{token}"},
        {"accept", "application/vnd.github.v3+json"},
        {"user-agent", "EcoSync-Elixir/1.0"}
      ]
    )
    %__MODULE__{token: token, req: req}
  end

  @doc """
  Retorna el perfil del usuario autenticado.
  """
  def get_user_profile(client) do
    client.req
    |> Req.get!(url: "/user")
    |> handle_response()
  end

  @doc """
  Retorna todos los repositorios donde el usuario es dueño.
  """
  def get_repos(client) do
    case get_paginated(client, "/user/repos", params: [affiliation: "owner", sort: "pushed", direction: "desc"]) do
      {:ok, repos} -> repos
      {:error, _} -> []
    end
  end

  @doc """
  Retorna detalles completos de un repositorio (incluyendo info del padre si es fork).
  """
  def get_repo_details(client, owner, repo) do
    client.req
    |> Req.get!(url: "/repos/#{owner}/#{repo}")
    |> handle_response()
  end

  @doc """
  Lista las ramas de un repositorio.
  """
  def get_branches(client, owner, repo) do
    case get_paginated(client, "/repos/#{owner}/#{repo}/branches") do
      {:ok, branches} -> branches
      _ -> []
    end
  end

  @doc """
  Retorna detalles de los commits más recientes.
  """
  def get_recent_commits_details(client, owner, repo, count \\ 5) do
    case client.req |> Req.get(url: "/repos/#{owner}/#{repo}/commits", params: [per_page: count]) do
      {:ok, %{status: 200, body: body}} when is_list(body) ->
        Enum.map(body, fn c ->
          commit_data = c["commit"]
          %{
            "sha" => String.slice(c["sha"], 0, 7),
            "message" => commit_data["message"] |> String.split("\n") |> List.first() |> String.slice(0, 80),
            "author" => get_in(commit_data, ["author", "name"]) || "Unknown",
            "date" => get_in(commit_data, ["author", "date"])
          }
        end)
      _ -> []
    end
  end

  @doc """
  Archiva un repositorio.
  """
  def archive_repo(client, owner, repo) do
    client.req
    |> Req.patch!(url: "/repos/#{owner}/#{repo}", json: %{archived: true})
    |> handle_response()
  end

  @doc """
  Elimina un repositorio.
  """
  def delete_repo(client, owner, repo) do
    client.req
    |> Req.delete!(url: "/repos/#{owner}/#{repo}")
    |> handle_response()
  end

  @doc """
  Retorna la fecha del último commit en la rama por defecto.
  """
  def get_last_commit_date(client, owner, repo) do
    case client.req |> Req.get(url: "/repos/#{owner}/#{repo}/commits", params: [per_page: 1]) do
      {:ok, %{status: 200, body: [commit | _]}} -> 
        get_in(commit, ["commit", "committer", "date"]) |> parse_iso8601()
      _ -> nil
    end
  end

  defp parse_iso8601(nil), do: nil
  defp parse_iso8601(date_str) do
    case DateTime.from_iso8601(String.replace(date_str, "Z", "+00:00")) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  @doc """
  Lista las llaves SSH del usuario.
  """
  def get_ssh_keys(client) do
    case client.req |> Req.get(url: "/user/keys") do
      {:ok, %{status: 200, body: body}} -> body
      _ -> []
    end
  end

  @doc """
  Lista las instalaciones de aplicaciones de GitHub del usuario.
  """
  def get_user_installations(client) do
    case client.req |> Req.get(url: "/user/installations") do
      {:ok, %{status: 200, body: %{"installations" => installations}}} -> installations
      _ -> []
    end
  end

  @doc """
  Lista los gists del usuario.
  """
  def get_public_gists(client) do
    # Usamos paginación para obtener todos los gists
    case get_paginated(client, "/gists") do
      {:ok, gists} -> gists
      _ -> []
    end
  end

  @doc """
  Lista los contenidos de una ruta en el repositorio.
  """
  def get_repo_contents(client, owner, repo, path \\ "") do
    client.req
    |> Req.get!(url: "/repos/#{owner}/#{repo}/contents/#{path}")
    |> handle_response()
  end

  @doc """
  Descarga el contenido de un archivo desde una URL de descarga de GitHub.
  """
  def get_file_content_from_url(client, download_url) do
    client.req
    |> Req.get!(url: download_url)
    |> handle_response()
  end

  # Helpers Internos

  defp get_paginated(client, url, opts \\ []) do
    params = Keyword.get(opts, :params, []) |> Keyword.put_new(:per_page, 100)
    fetch_pages(client, url, params, [])
  end

  defp fetch_pages(client, url, params, acc) do
    case client.req |> Req.get(url: url, params: params) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        new_acc = acc ++ List.wrap(body)
        case get_next_url(headers) do
          nil -> {:ok, new_acc}
          next_url -> 
            # Si next_url es absoluto y ya tiene el base_url, lo limpiamos para Req
            clean_url = String.replace(next_url, @api_base, "")
            fetch_pages(client, clean_url, [], new_acc)
        end
      {:ok, %{status: status, body: body}} ->
        Logger.error("GitHub API error #{status}: #{inspect(body)}")
        {:error, status}
      {:error, reason} ->
        Logger.error("GitHub API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_next_url(headers) do
    with [link_header] <- Map.get(headers, "link"),
         [_, next_url] <- Regex.run(~r/<([^>]+)>;\s*rel="next"/, link_header) do
      next_url
    else
      _ -> nil
    end
  end

  defp handle_response(%{status: status, body: body}) when status in 200..299, do: body
  defp handle_response(%{status: status, body: body}) do
    Logger.error("GitHub API error #{status}: #{inspect(body)}")
    raise "GitHub API error #{status}"
  end
end
