defmodule EcoSyncBackendWeb.DriveController do
  use EcoSyncBackendWeb, :controller
  alias EcoSyncBackend.Google.Client, as: GoogleClient
  alias EcoSyncBackend.Drive

  def scan(conn, _params) do
    with {:ok, token} <- get_google_token(conn),
         client <- GoogleClient.new(token) do
      result = Drive.scan_for_waste(client)
      json(conn, result)
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  def delete(conn, %{"file_ids" => file_ids}) do
    with {:ok, token} <- get_google_token(conn),
         client <- GoogleClient.new(token) do
      
      results = Enum.reduce(file_ids, %{deleted: 0, failed: 0}, fn fid, acc ->
        try do
          GoogleClient.delete_file(client, fid)
          Map.update!(acc, :deleted, & &1 + 1)
        rescue
          e -> 
            IO.inspect(e, label: "Error deleting drive file")
            Map.update!(acc, :failed, & &1 + 1)
        end
      end)

      json(conn, Map.put(results, :total, length(file_ids)))
    else
      {:error, :unauthorized} -> error_unauthorized(conn)
    end
  end

  # Helpers

  defp get_google_token(conn) do
    token = get_session(conn, :google_access_token)
    if token, do: {:ok, token}, else: {:error, :unauthorized}
  end

  defp error_unauthorized(conn) do
    conn
    |> put_status(401)
    |> json(%{detail: "Not authenticated with Google. Please login via /auth/google first."})
  end
end
