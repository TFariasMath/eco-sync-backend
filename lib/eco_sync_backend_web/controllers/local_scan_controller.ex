defmodule EcoSyncBackendWeb.LocalScanController do
  use EcoSyncBackendWeb, :controller
  alias EcoSyncBackend.LocalScanner

  @doc """
  Retorna información sobre los directorios base del sistema.
  """
  def directories(conn, _params) do
    try do
      summaries = LocalScanner.get_directory_summaries()
      json(conn, %{directories: summaries})
    rescue
      _ ->
        json(conn, %{
          directories: [],
          error: "No se pudo acceder a los directorios. Verifica permisos."
        })
    end
  end

  @doc """
  Realiza un escaneo profundo de las rutas proporcionadas.
  """
  def scan(conn, params) do
    paths = params["paths"] || []
    full_scan = params["full_scan"] || false

    paths_to_scan =
      if full_scan or Enum.empty?(paths) do
        Map.values(LocalScanner.get_default_directories())
      else
        paths
      end

    opts = %{
      min_months_old: params["min_months_old"] || 12,
      min_size_mb: params["min_size_mb"] || 100,
      installers: params["include_installers"] |> Kernel.!=(false),
      temps: params["include_temps"] |> Kernel.!=(false),
      cache: params["include_cache"] |> Kernel.!=(false)
    }

    try do
      results = LocalScanner.scan_paths(paths_to_scan, opts)
      json(conn, results)
    rescue
      _ ->
        json(conn, %{error: "Error al escanear directorios", files: [], waste_files: 0})
    end
  end

  @doc """
  Elimina los archivos locales seleccionados.
  """
  def delete(conn, %{"files" => files} = params) do
    permanent = params["permanent"] || false

    result = LocalScanner.delete_files(files, permanent)
    json(conn, result)
  end
end
