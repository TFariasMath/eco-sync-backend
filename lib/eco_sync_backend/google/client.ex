defmodule EcoSyncBackend.Google.Client do
  @moduledoc """
  Cliente para la API de Google Drive v3 usando Req.
  Implementa cuotas, listado paginado y gestión de archivos.
  """
  require Logger

  @api_base "https://www.googleapis.com/drive/v3"

  defstruct [:token, :req]

  def new(token) do
    req = Req.new(
      base_url: @api_base,
      headers: [
        {"authorization", "Bearer #{token}"},
        {"accept", "application/json"},
        {"user-agent", "EcoSync-Elixir/1.0"}
      ]
    )
    %__MODULE__{token: token, req: req}
  end

  @doc """
  Obtiene información de la cuota de almacenamiento y del usuario.
  """
  def get_storage_quota(client) do
    case client.req |> Req.get(url: "https://www.googleapis.com/drive/v3/about", params: [fields: "storageQuota,user"]) do
      {:ok, %{status: 200, body: data}} ->
        quota = data["storageQuota"] || %{}
        user = data["user"] || %{}
        %{
          "total_bytes" => parse_int(quota["limit"]),
          "used_bytes" => parse_int(quota["usage"]),
          "trash_bytes" => parse_int(quota["usageInDriveTrash"]),
          "user_email" => user["emailAddress"] || "",
          "user_name" => user["displayName"] || ""
        }
      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Drive API error #{status}: #{inspect(body)}")
        %{}
      _ -> %{}
    end
  end

  @doc """
  Lista todos los archivos del usuario con metadatos relevantes.
  """
  def list_all_files(client) do
    fields = "nextPageToken, files(id,name,mimeType,size,modifiedTime,viewedByMeTime,md5Checksum,trashed,ownedByMe,parents)"
    query = "'me' in owners and trashed=false"
    
    case fetch_pages(client, "/files", [
      q: query,
      spaces: "drive",
      fields: fields,
      pageSize: 1000,
      orderBy: "modifiedTime desc"
    ], []) do
      {:ok, files} -> files
      _ -> []
    end
  end

  @doc """
  Mueve un archivo a la papelera.
  """
  def delete_file(client, file_id) do
    client.req
    |> Req.patch!(url: "/files/#{file_id}", json: %{trashed: true})
    |> handle_response()
  end

  # Helpers Internos

  defp fetch_pages(client, url, params, acc) do
    case client.req |> Req.get(url: url, params: params) do
      {:ok, %{status: 200, body: body}} ->
        files = body["files"] || []
        new_acc = acc ++ files
        case body["nextPageToken"] do
          nil -> {:ok, new_acc}
          token -> 
            new_params = Keyword.put(params, :pageToken, token)
            fetch_pages(client, url, new_params, new_acc)
        end
      {:ok, %{status: status, body: body}} ->
        Logger.error("Google Drive API error #{status}: #{inspect(body)}")
        {:error, status}
      {:error, reason} ->
        Logger.error("Google Drive API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_response(%{status: status, body: body}) when status in 200..299, do: body
  defp handle_response(%{status: status, body: body}) do
    Logger.error("Google Drive API error #{status}: #{inspect(body)}")
    raise "Google Drive API error #{status}"
  end

  defp parse_int(nil), do: 0
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(_), do: 0
end
