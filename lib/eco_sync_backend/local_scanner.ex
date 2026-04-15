defmodule EcoSyncBackend.LocalScanner do
  @moduledoc """
  Escáner de Almacenamiento Local.
  Analiza directorios en busca de archivos basura.
  """
  require Logger

  @waste_extensions ~w(.tmp .temp .bak .old .log .cache .DS_Store .thumbs.db .~tmp)

  @type directory_info :: %{
          name: String.t(),
          path: String.t(),
          size_bytes: non_neg_integer(),
          size_str: String.t(),
          files_count: non_neg_integer()
        }

  @type local_file :: %{
          id: String.t(),
          name: String.t(),
          path: String.t(),
          size_bytes: non_neg_integer(),
          size_mb: float(),
          modified_time: String.t(),
          is_waste: boolean(),
          waste_category: atom(),
          waste_reason: String.t()
        }

  @type scan_result :: %{
          total_files: non_neg_integer(),
          waste_files: non_neg_integer(),
          total_size_gb: float(),
          waste_size_gb: float(),
          co2_grams_per_year: float(),
          files: [local_file()]
        }

  @type delete_result :: %{
          deleted: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }

  @doc """
  Retorna los directorios estándar para escanear.
  """
  @spec get_default_directories() :: [directory_info()]
  def get_default_directories do
    home = System.get_env("USERPROFILE") || System.get_env("HOME") || "."
    downloads = Path.join(home, "Downloads")

    if File.dir?(downloads) do
      [
        %{
          name: "Descargas",
          path: downloads,
          size_bytes: 0,
          size_str: "Calculando...",
          files_count: 0
        }
      ]
    else
      []
    end
  end

  @doc """
  Calcula el tamaño rápido de los directorios.
  """
  @spec get_directory_summaries() :: [directory_info()]
  def get_directory_summaries do
    dirs = get_default_directories()

    Enum.map(dirs, fn dir ->
      result = get_dir_size_simple(dir.path)

      %{
        dir
        | size_bytes: result.size,
          size_str: format_size(result.size),
          files_count: result.count
      }
    end)
  end

  defp get_dir_size_simple(path) do
    case System.cmd("powershell", [
           "-Command",
           "(Get-ChildItem -Path '#{path}' -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum"
         ]) do
      {output, 0} ->
        size = String.trim(output) |> String.to_integer() |> Kernel.||(0)
        %{size: size, count: 0}

      _ ->
        %{size: 0, count: 0}
    end
  rescue
    _ -> %{size: 0, count: 0}
  end

  @doc """
  Escaneo profundo de rutas seleccionadas para clasificar basura.
  """
  @spec scan_paths([String.t()], map()) :: scan_result()
  def scan_paths(paths, _opts \\ %{}) do
    results =
      Enum.flat_map(paths, fn path ->
        if File.dir?(path) do
          scan_with_powershell(path)
        else
          []
        end
      end)
      |> Enum.sort_by(&(-&1.size_bytes))

    total_waste_bytes = Enum.reduce(results, 0, &(&1.size_bytes + &2))
    total_waste_gb = total_waste_bytes / (1024 * 1024 * 1024)
    co2_grams = total_waste_gb * 0.5 * 0.475 * 1000

    %{
      total_files: length(results),
      waste_files: length(results),
      total_size_gb: 0,
      waste_size_gb: Float.round(total_waste_gb, 3),
      co2_grams_per_year: Float.round(co2_grams, 2),
      files: results
    }
  end

  defp scan_with_powershell(path) do
    now = DateTime.utc_now()
    threshold = DateTime.add(now, -(365 * 24 * 60 * 60), :second)
    threshold_str = DateTime.to_iso8601(threshold)

    ps_script = """
    $files = Get-ChildItem -Path '#{path}' -Recurse -File -ErrorAction SilentlyContinue | 
      Where-Object { $_.LastWriteTime -lt '#{threshold_str}' -and $_.Length -gt 104857600 } |
      Select-Object -First 50 Name, FullName, Length, LastWriteTime
    $files | ConvertTo-Json -Compress
    """

    case System.cmd("powershell", ["-NoProfile", "-Command", ps_script]) do
      {output, 0} ->
        if output == "" or output == "null" do
          []
        else
          parse_files(output)
        end

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp parse_files(output) do
    case Jason.decode(output) do
      {:ok, data} when is_list(data) ->
        Enum.map(data, fn f ->
          size = Map.get(f, "Length", 0) || 0

          %{
            id: Map.get(f, "FullName", ""),
            name: Map.get(f, "Name", ""),
            path: Map.get(f, "FullName", ""),
            size_bytes: size,
            size_mb: Float.round(size / (1024 * 1024), 2),
            modified_time: Map.get(f, "LastWriteTime", ""),
            is_waste: true,
            waste_category: :pesado,
            waste_reason: "Archivo grande sin usar (>100MB, >1 año)"
          }
        end)

      {:ok, %{"Name" => name}} ->
        size = Map.get(output, "Length", 0) || 0

        [
          %{
            id: Map.get(output, "FullName", ""),
            name: name,
            path: Map.get(output, "FullName", ""),
            size_bytes: size,
            size_mb: Float.round(size / (1024 * 1024), 2),
            modified_time: Map.get(output, "LastWriteTime", ""),
            is_waste: true,
            waste_category: :pesado,
            waste_reason: "Archivo grande sin usar (>100MB, >1 año)"
          }
        ]

      _ ->
        []
    end
  rescue
    _ -> []
  end

  defp format_size(bytes) do
    cond do
      bytes >= 1024 * 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
      bytes >= 1024 * 1024 -> "#{Float.round(bytes / (1024 * 1024), 1)} MB"
      true -> "#{Float.round(bytes / 1024, 0)} KB"
    end
  end

  @doc """
  Elimina archivos localmente.
  """
  @spec delete_files([String.t()], boolean()) :: delete_result()
  def delete_files(file_paths, permanent \\ false) do
    results =
      Enum.reduce(file_paths, %{deleted: 0, failed: 0}, fn path, acc ->
        try do
          File.rm!(path)
          %{acc | deleted: acc.deleted + 1}
        rescue
          _ -> %{acc | failed: acc.failed + 1}
        end
      end)

    %{results | total: length(file_paths)}
  end
end
