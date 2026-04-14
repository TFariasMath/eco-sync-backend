defmodule EcoSyncBackend.Drive do
  @moduledoc """
  Lógica de negocio para analizar archivos en Google Drive.
  Identifica duplicados, archivos pesados y archivos antiguos (basura digital).
  """
  require Logger
  alias EcoSyncBackend.Google.Client, as: GoogleClient

  @waste_extensions ~w(.tmp .temp .bak .old .log .cache .dmg .iso .exe .msi .deb .rpm .DS_Store .thumbs.db)
  @large_file_threshold_mb 100

  @doc """
  Analiza todos los archivos y los clasifica según su potencial de basura.
  """
  def scan_for_waste(client) do
    files = GoogleClient.list_all_files(client)
    quota = GoogleClient.get_storage_quota(client)
    now = DateTime.utc_now()
    one_year_ago = DateTime.add(now, -(365 * 24 * 60 * 60), :second)

    md5_groups = Enum.group_by(files, & &1["md5Checksum"]) |> Map.delete(nil)

    duplicate_ids =
      md5_groups
      |> Enum.flat_map(fn {_md5, group} ->
        if length(group) > 1 do
          group
          |> Enum.sort_by(& &1["modifiedTime"], :desc)
          |> Enum.drop(1)
          |> Enum.map(& &1["id"])
        else
          []
        end
      end)
      |> MapSet.new()

    {results, total_waste_bytes} =
      Enum.map_reduce(files, 0, fn f, acc_bytes ->
        file_id = f["id"]
        name = f["name"] || "Unknown"
        size_bytes = parse_int(f["size"])
        size_mb = size_bytes / (1024 * 1024)
        mime_type = f["mimeType"] || ""
        modified = f["modifiedTime"]
        viewed = f["viewedByMeTime"]

        {category, reason} = determine_waste(f, duplicate_ids, one_year_ago)

        is_waste = category != :activo
        new_acc = if is_waste, do: acc_bytes + size_bytes, else: acc_bytes

        item = %{
          id: file_id,
          name: name,
          size_bytes: size_bytes,
          size_mb: Float.round(size_mb, 2),
          mime_type: mime_type,
          modified_time: modified,
          viewed_time: viewed,
          is_waste: is_waste,
          waste_category: category,
          waste_reason: reason
        }

        {item, new_acc}
      end)

    sorted_results = Enum.sort_by(results, &{not &1.is_waste, -&1.size_bytes})

    total_waste_gb = total_waste_bytes / (1024 * 1024 * 1024)
    co2_grams = total_waste_gb * 0.5 * 0.475 * 1000

    %{
      total_files: length(files),
      waste_files: Enum.count(results, & &1.is_waste),
      total_size_gb:
        Float.round(
          Enum.reduce(files, 0, fn f, acc -> acc + parse_int(f["size"]) end) /
            (1024 * 1024 * 1024),
          3
        ),
      waste_size_gb: Float.round(total_waste_gb, 3),
      co2_grams_per_year: Float.round(co2_grams, 2),
      quota: quota,
      files: sorted_results
    }
  end

  defp determine_waste(f, duplicate_ids, threshold) do
    name = f["name"] || ""
    size_mb = parse_int(f["size"]) / (1024 * 1024)

    cond do
      MapSet.member?(duplicate_ids, f["id"]) ->
        {:duplicado, "Archivo duplicado (mismo contenido)"}

      Enum.any?(@waste_extensions, &String.ends_with?(String.downcase(name), &1)) ->
        {:temporal, "Archivo temporal o de sistema"}

      String.starts_with?(name, ["Copy of ", "Copia de "]) ->
        {:duplicado, "Copia manual de archivo"}

      size_mb > @large_file_threshold_mb && f["mimeType"] != "application/vnd.google-apps.folder" ->
        {:pesado, "Archivo grande (#{Float.round(size_mb, 0)} MB)"}

      is_old?(f, threshold) ->
        {:antiguo, get_old_reason(f)}

      true ->
        {:activo, ""}
    end
  end

  defp is_old?(f, threshold) do
    mod_dt = parse_datetime(f["modifiedTime"])
    view_dt = parse_datetime(f["viewedByMeTime"])

    cond do
      mod_dt && view_dt ->
        DateTime.compare(mod_dt, threshold) == :lt && DateTime.compare(view_dt, threshold) == :lt

      mod_dt ->
        DateTime.compare(mod_dt, threshold) == :lt

      true ->
        false
    end
  end

  defp get_old_reason(f) do
    view_dt = parse_datetime(f["viewedByMeTime"])
    mod_dt = parse_datetime(f["modifiedTime"])

    cond do
      view_dt -> "Sin acceso desde #{format_month(view_dt)}"
      mod_dt -> "Sin modificar desde #{format_month(mod_dt)}"
      true -> "Archivo sin uso prolongado"
    end
  end

  defp format_month(dt) do
    dt |> DateTime.to_string() |> String.slice(0..6)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(date_str) do
    case DateTime.from_iso8601(String.replace(date_str, "Z", "+00:00")) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_int(nil), do: 0
  defp parse_int(val) when is_binary(val), do: String.to_integer(val)
  defp parse_int(val) when is_integer(val), do: val
  defp parse_int(_), do: 0
end
