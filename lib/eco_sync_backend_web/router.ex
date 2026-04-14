defmodule EcoSyncBackendWeb.Router do
  use EcoSyncBackendWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :auth do
    plug(:accepts, ["html", "json"])
    plug(:fetch_session)
  end

  scope "/", EcoSyncBackendWeb do
    pipe_through(:api)

    get("/repos", RepoController, :repos_overview)
    get("/inactive-repos", RepoController, :list_inactive_repos)
    get("/dead-forks", RepoController, :list_dead_forks)
    get("/scan-secrets", RepoController, :list_secrets)
    post("/manage-repo", RepoController, :manage_repo)
    post("/bulk-delete", RepoController, :bulk_delete)
    get("/security-audit", RepoController, :security_audit)

    # Google Drive
    get("/drive/scan", DriveController, :scan)
    post("/drive/delete", DriveController, :delete)

    # Huella Digital (OSINT/Reddit/Pwned)
    get("/osint/scan", DigitalFootprintController, :osint_scan)
    get("/check-leaks", DigitalFootprintController, :check_leaks)
    post("/clean-reddit", DigitalFootprintController, :clean_reddit)

    # Escaneo Local
    get("/local/directories", LocalScanController, :directories)
    post("/local/scan", LocalScanController, :scan)
    post("/local/delete", LocalScanController, :delete)
  end

  scope "/auth", EcoSyncBackendWeb do
    pipe_through(:auth)

    get("/logout", AuthController, :logout)
    get("/login", AuthController, :login)
    get("/github/login", AuthController, :github_login)
    get("/google/login", AuthController, :google_login)
    get("/github/callback", AuthController, :callback)
    get("/google/callback", AuthController, :callback)
    post("/github/callback", AuthController, :callback)
    post("/google/callback", AuthController, :callback)
  end
end
