defmodule EcoSyncBackendWeb.AuthController do
  use EcoSyncBackendWeb, :controller

  def login(conn, _params) do
    redirect(conn, external: oauth_url("github"))
  end

  def github_login(conn, _params) do
    redirect(conn, external: oauth_url("github"))
  end

  def google_login(conn, _params) do
    redirect(conn, external: oauth_url("google"))
  end

  def callback(conn, %{"provider" => provider}) do
    code = Map.get(conn.query_params, "code")

    if code do
      case provider do
        "github" ->
          case exchange_github_token(code) do
            {:ok, token} ->
              conn
              |> put_session(:access_token, token)
              |> redirect(external: frontend_url("/scan/github?authenticated=true"))

            {:error, _} ->
              conn
              |> put_status(401)
              |> json(%{error: "Failed to exchange token"})
          end

        "google" ->
          case exchange_google_token(code) do
            {:ok, token, refresh_token} ->
              conn
              |> put_session(:google_access_token, token)
              |> maybe_put_session(:google_refresh_token, refresh_token)
              |> redirect(external: frontend_url("/scan/drive?authenticated=true"))

            {:error, _} ->
              conn
              |> put_status(401)
              |> json(%{error: "Failed to exchange token"})
          end

        _ ->
          conn |> put_status(400) |> json(%{error: "Provider desconocido"})
      end
    else
      conn |> put_status(400) |> json(%{error: "Code no proporcionado"})
    end
  end

  def callback(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{error: "Provider no proporcionado"})
  end

  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(external: frontend_url("/"))
  end

  defp oauth_url("github") do
    client_id = System.get_env("GITHUB_CLIENT_ID") || "demo_client_id"

    redirect_uri =
      System.get_env("GITHUB_REDIRECT_URI") || "http://localhost:4000/auth/github/callback"

    scope = "repo,delete_repo,user"

    "https://github.com/login/oauth/authorize?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&scope=#{URI.encode_www_form(scope)}"
  end

  defp oauth_url("google") do
    client_id = System.get_env("GOOGLE_CLIENT_ID") || "demo_client_id"

    redirect_uri =
      System.get_env("GOOGLE_REDIRECT_URI") || "http://localhost:4000/auth/google/callback"

    scope =
      "https://www.googleapis.com/auth/drive.metadata.readonly https://www.googleapis.com/auth/drive.file"

    "https://accounts.google.com/o/oauth2/v2/auth?client_id=#{client_id}&redirect_uri=#{URI.encode_www_form(redirect_uri)}&response_type=code&scope=#{URI.encode_www_form(scope)}&access_type=offline"
  end

  defp exchange_github_token(code) do
    client_id = System.get_env("GITHUB_CLIENT_ID") || "demo_client_id"
    client_secret = System.get_env("GITHUB_CLIENT_SECRET") || "demo_client_secret"

    redirect_uri =
      System.get_env("GITHUB_REDIRECT_URI") || "http://localhost:4000/auth/github/callback"

    case Req.post("https://github.com/login/oauth/access_token",
           form: [
             client_id: client_id,
             client_secret: client_secret,
             code: code,
             redirect_uri: redirect_uri
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        access_token = body["access_token"]
        if access_token, do: {:ok, access_token}, else: {:error, "no token"}

      _ ->
        {:error, "request failed"}
    end
  end

  defp exchange_google_token(code) do
    client_id = System.get_env("GOOGLE_CLIENT_ID") || "demo_client_id"
    client_secret = System.get_env("GOOGLE_CLIENT_SECRET") || "demo_client_secret"

    redirect_uri =
      System.get_env("GOOGLE_REDIRECT_URI") || "http://localhost:4000/auth/google/callback"

    case Req.post("https://oauth2.googleapis.com/token",
           form: [
             client_id: client_id,
             client_secret: client_secret,
             code: code,
             redirect_uri: redirect_uri,
             grant_type: "authorization_code"
           ]
         ) do
      {:ok, %{status: 200, body: body}} ->
        access_token = body["access_token"]
        refresh_token = body["refresh_token"]
        if access_token, do: {:ok, access_token, refresh_token}, else: {:error, "no token"}

      _ ->
        {:error, "request failed"}
    end
  end

  defp maybe_put_session(conn, _key, nil), do: conn
  defp maybe_put_session(conn, key, value), do: put_session(conn, key, value)

  defp frontend_url(path) do
    base = System.get_env("URL_FRONTEND") || "http://localhost:5173"
    base <> path
  end
end
