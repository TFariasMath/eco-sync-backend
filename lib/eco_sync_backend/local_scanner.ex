defmodule EcoSyncBackend.LocalScanner do
  @moduledoc """
  Escáner de Almacenamiento Local.
  Analiza directorios en busca de archivos basura.
  """
  require Logger

  @waste_extensions ~w(.tmp .temp .bak .old .log .cache .DS_Store .thumbs.db .~tmp)
  @installer_extensions ~w(.msi .exe .dmg .iso .pkg .rpm .deb)

  def get_default_directories do
    home = System.get_env("USERPROFILE") || System.get_env("HOME") || "."
    base = Path.join(home, "Downloads")

    if File.dir?(base) do
      [%{name: "Descargas", path: base, size_bytes: 0, size_str: "Calculando...", files_count: 0}]
    else
      []
    end
  end

  def get_directory_summaries do
    get_default_directories()
  end

  def scan_paths(_paths, _opts \\ %{}) do
    %{
      total_files: 0,
      waste_files: 0,
      total_size_gb: 0,
      waste_size_gb: 0,
      co2_grams_per_year: 0,
      files: [],
      message: "Escaneo local deshabilitado temporalmente"
    }
  end

  def delete_files(file_paths, permanent \\ false) do
    deleted =
      Enum.count(file_paths, fn path ->
        try do
          if permanent, do: File.rm!(path), else: File.rm!(path)
          true
        rescue
          _ -> false
        end
      end)

    %{deleted: deleted, failed: length(file_paths) - deleted, total: length(file_paths)}
  end
end
