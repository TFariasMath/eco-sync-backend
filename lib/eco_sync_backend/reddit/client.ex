defmodule EcoSyncBackend.Reddit.Client do
  @moduledoc """
  Cliente para la API de Reddit. Maneja autenticación vía Password Flow (Script)
  y permite la gestión de comentarios para limpieza de huella digital.
  """
  require Logger

  @api_base "https://oauth.reddit.com"

  defstruct [:token, :req]

  @doc """
  Crea una nueva instancia del cliente obteniendo un token de acceso.
  Requiere las credenciales de una aplicación tipo 'script'.
  """
  def new(client_id, client_secret, username, password) do
    form = [
      grant_type: "password",
      username: username,
      password: password
    ]

    auth = Base.encode64("#{client_id}:#{client_secret}")

    case Req.post("https://www.reddit.com/api/v1/access_token",
           form: form,
           headers: [{"authorization", "Basic #{auth}"}, {"user-agent", user_agent()}]
         ) do
      {:ok, %{status: 200, body: %{"access_token" => token}}} ->
        req =
          Req.new(
            base_url: @api_base,
            headers: [
              {"authorization", "bearer #{token}"},
              {"user-agent", user_agent()}
            ]
          )

        {:ok, %__MODULE__{token: token, req: req}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Reddit Auth Error #{status}: #{inspect(body)}")
        {:error, :auth_failed}

      {:error, reason} ->
        Logger.error("Reddit Auth Connection Error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Obtiene los comentarios del usuario filtrados por antigüedad.
  """
  def get_old_comments(client, limit \\ 100) do
    case client.req |> Req.get(url: "/api/v1/me") do
      {:ok, %{status: 200, body: %{"name" => name}}} ->
        url = "/user/#{name}/comments"

        case client.req |> Req.get(url: url, params: [limit: limit, sort: "new"]) do
          {:ok, %{status: 200, body: %{"data" => %{"children" => children}}}} ->
            Enum.map(children, & &1["data"])

          _ ->
            []
        end

      _ ->
        []
    end
  end

  @doc """
  Obtiene comentarios más antiguos que X días.
  """
  def get_comments_older_than(client, days, limit \\ 100) do
    all_comments = get_old_comments(client, limit)
    cutoff = DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)

    Enum.filter(all_comments, fn comment ->
      case DateTime.from_iso8601(String.replace(comment["created_utc"] || "", "Z", "+00:00")) do
        {:ok, dt, _} -> DateTime.compare(dt, cutoff) == :lt
        _ -> false
      end
    end)
  end

  @doc """
  Sobrescribe el texto de un comentario y luego lo borra.
  Esto ayuda a evitar que servicios de terceros mantengan el historial del comentario.
  """
  def overwrite_and_delete_comment(client, comment_id, text \\ "[DELETED BY SCRIPT]") do
    thing_id = if String.starts_with?(comment_id, "t1_"), do: comment_id, else: "t1_#{comment_id}"

    edit_result = do_edit_comment(client, thing_id, text)

    case edit_result do
      :ok ->
        do_delete_comment(client, thing_id)

      error ->
        Logger.error("Failed to overwrite Reddit comment #{comment_id}: #{inspect(error)}")
        false
    end
  end

  defp do_edit_comment(client, thing_id, text, attempts \\ 3) do
    edit_form = [
      thing_id: thing_id,
      text: text,
      api_type: "json"
    ]

    case client.req |> Req.post(url: "/api/editusertext", form: edit_form) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: 429}} when attempts > 0 ->
        Process.sleep(2000)
        do_edit_comment(client, thing_id, text, attempts - 1)

      other when attempts > 0 ->
        Logger.warning("Edit failed, retrying: #{inspect(other)}")
        Process.sleep(1000)
        do_edit_comment(client, thing_id, text, attempts - 1)

      other ->
        other
    end
  end

  defp do_delete_comment(client, thing_id, attempts \\ 3) do
    del_form = [id: thing_id]

    case client.req |> Req.post(url: "/api/del", form: del_form) do
      {:ok, %{status: 200}} ->
        true

      {:ok, %{status: 429}} when attempts > 0 ->
        Process.sleep(2000)
        do_delete_comment(client, thing_id, attempts - 1)

      other when attempts > 0 ->
        Logger.warning("Delete failed, retrying: #{inspect(other)}")
        Process.sleep(1000)
        do_delete_comment(client, thing_id, attempts - 1)

      other ->
        Logger.error("Delete final failure: #{inspect(other)}")
        false
    end
  end

  defp user_agent, do: "EcoSync-Elixir:v1.0 (by /u/YOUR_USERNAME)"
end
