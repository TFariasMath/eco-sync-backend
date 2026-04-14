defmodule EcoSyncBackend.DriveTest do
  use ExUnit.Case, async: true
end

defmodule EcoSyncBackend.LocalScannerTest do
  use ExUnit.Case, async: true

  describe "LocalScanner funciones" do
    test "get_default_directories retorna mapas" do
      dirs = EcoSyncBackend.LocalScanner.get_default_directories()

      assert is_map(dirs)
      assert Map.has_key?(dirs, "Descargas")
      assert Map.has_key?(dirs, "Documentos")
    end
  end
end

defmodule EcoSyncBackend.OSINTScannerTest do
  use ExUnit.Case, async: true

  describe "scan_username/1" do
    test "retorna estructura correcta" do
      result = EcoSyncBackend.OSINTScanner.scan_username("testuser")

      assert is_map(result)
      assert result.username == "testuser"
      assert is_list(result.platforms)
      assert is_integer(result.total_co2_grams)
    end
  end
end
