defmodule EcoSyncBackend.AuditLogger do
  @moduledoc """
  Módulo para registrar acciones destructivas en un log persistente.
  Portado de audit_logger.py.
  """

  @log_file "deletions.log"

  @doc """
  Registra la eliminación de un recurso en el log de auditoría.
  Formato: [TIMESTAMP] USER: <user> ACTION: DELETE REPO: <repo> STATUS: <status>
  """
  def log_deletion(username, resource_name, status \\ "SUCCESS") do
    timestamp = 
      DateTime.utc_now() 
      |> DateTime.truncate(:second) 
      |> DateTime.to_iso8601()
      |> String.replace("Z", "+00:00") # Para mantener paridad con el formato de Python si es necesario

    line = "[#{timestamp}] USER: #{username} ACTION: DELETE RESOURCE: #{resource_name} STATUS: #{status}\n"
    
    # Aseguramos que el archivo existe o lo creamos
    File.write(@log_file, line, [:append])
  end
end
