defmodule EcoSyncBackendWeb.DigitalFootprintController do
  use EcoSyncBackendWeb, :controller
  alias EcoSyncBackend.OSINTScanner
  alias EcoSyncBackend.Reddit.Client, as: RedditClient
  alias EcoSyncBackend.PwnedClient

  @doc """
  Realiza un escaneo OSINT paralelo para un nombre de usuario.
  """
  def osint_scan(conn, %{"username" => username}) do
    if String.length(username) < 3 do
      conn
      |> put_status(400)
      |> json(%{error: "El nombre de usuario debe tener al menos 3 caracteres."})
    else
      results = OSINTScanner.scan_username(username)
      json(conn, results)
    end
  end

  @doc """
  Verifica si un correo ha sido filtrado en bases de datos comprometidas (HIBP).
  """
  def check_leaks(conn, %{"email" => email}) do
    client = PwnedClient.new()

    case PwnedClient.get_breaches_for_account(client, email) do
      {:error, :rate_limit} ->
        conn |> put_status(429) |> json(%{error: "Límite de peticiones de HIBP excedido."})

      {:error, _} ->
        conn
        |> put_status(500)
        |> json(%{error: "Error consultando el servicio de filtraciones."})

      results ->
        json(conn, %{email: email, breaches: results, count: length(results)})
    end
  end

  @doc """
  Limpia el historial de Reddit (sobrescribe y borra).
  Opcionalmente filtra por antigüedad (older_than_days).
  """
  def clean_reddit(conn, params) do
    client_id = System.get_env("REDDIT_CLIENT_ID")
    client_secret = System.get_env("REDDIT_CLIENT_SECRET")
    username = System.get_env("REDDIT_USERNAME")
    password = System.get_env("REDDIT_PASSWORD")

    limit = params["limit"] || 100
    older_than_days = params["older_than_days"] || 30

    case RedditClient.new(client_id, client_secret, username, password) do
      {:ok, client} ->
        # Obtener comentarios filtrados por antigüedad
        comments =
          if older_than_days > 0 do
            RedditClient.get_comments_older_than(client, older_than_days, limit)
          else
            RedditClient.get_old_comments(client, limit)
          end

        if Enum.empty?(comments) do
          json(conn, %{
            status: "completed",
            total_found: 0,
            deleted_count: 0,
            failed_count: 0,
            message: "No se encontraron comentarios mayores a #{older_than_days} días."
          })
        else
          # Procesar en paralelo
          results =
            comments
            |> Task.async_stream(
              fn comment ->
                id = comment["id"]
                body = comment["body"] |> String.slice(0..50) |> String.replace("\n", " ")

                result = RedditClient.overwrite_and_delete_comment(client, id)
                %{id: id, body_preview: body, success: result}
              end, max_concurrency: 5, timeout: 30_000)
            |> Enum.to_list()

          {successes, failures} =
            Enum.reduce(results, {[], []}, fn
              {:ok, %{success: true} = item}, {s, f} -> {[item | s], f}
              {:ok, %{success: false} = item}, {s, f} -> {s, [item | f]}
              {:error, %{id: id}}, {s, f} -> {s, [%{id: id, error: "timeout"} | f]}
            end)

          json(conn, %{
            status: "completed",
            total_found: length(comments),
            deleted_count: length(successes),
            failed_count: length(failures),
            details: %{
              deleted: Enum.map(successes, &%{id: &1.id, body_preview: &1.body_preview}),
              failed: Enum.map(failures, &%{id: &1.id || &1[:id], error: &1[:error] || "Unknown"})
            }
          })
        end

      {:error, _} ->
        conn
        |> put_status(500)
        |> json(%{
          error:
            "No se pudo autenticar con Reddit. Revisa las credenciales (REDDIT_CLIENT_ID, REDDIT_CLIENT_SECRET, REDDIT_USERNAME, REDDIT_PASSWORD)."
        })
    end
  end
end
