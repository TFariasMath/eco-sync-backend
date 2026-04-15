# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Conventional Commits](https://www.conventionalcommits.org/).

## [1.0.0] - 2025-04-14

### Added

- **GitHub Integration**: Full GitHub API client with pagination support
  - `GitHub.Client` - API client for GitHub operations
  - `Repos` - Service for analyzing repository inactivity and dead forks
  - `Scanner` - Secret scanning in repositories
  
- **Google Drive Integration**: Google Drive API client and waste detection
  - `Google.Client` - OAuth and API client for Google Drive
  - `Drive` - Service for identifying duplicate, old, and large files
  - CO2 calculation for stored files
  
- **OSINT Scanner**: Username enumeration across multiple platforms
  - `OSINTScanner` - Scans 18+ platforms for username presence
  - Platform detection with CO2 footprint estimation
  
- **HaveIBeenPwned Integration**: Email leak checking
  - `PwnedClient` - Client for HIBP API
  
- **Reddit Integration**: Comment management
  - `Reddit.Client` - OAuth and API client for Reddit
  - Overwrite and delete functionality for privacy
  
- **Local Storage Scanner**: Local filesystem analysis
  - `LocalScanner` - Scans local directories for large/waste files
  - PowerShell-based implementation for Windows compatibility
  
- **Authentication**: OAuth flow for GitHub and Google
  - `AuthController` - OAuth 2.0 authorization code flow
  - Token exchange and session management
  
- **Controllers**: REST API endpoints
  - `RepoController` - GitHub repositories management
  - `DriveController` - Google Drive operations
  - `LocalScanController` - Local storage scanning
  - `DigitalFootprintController` - OSINT, HIBP, Reddit

### Changed

- Migrated from Python/FastAPI to Elixir/Phoenix
- Updated project structure to follow Elixir best practices
- Improved error handling with graceful degradation

### Documentation

- README.md with project description
- AGENTS.md with development guidelines
- .env.example with required environment variables

### Configuration

- Added LICENSE (MPL 2.0) for code
- Added LICENSE-DOCS (CC BY-NC-SA 4.0) for documentation
- Added .editorconfig for code style consistency
- Set version to 1.0.0 following Romantic Versioning

---

## [0.1.0] - 2024-XX-XX (Initial Development - Python/FastAPI)

### Added

- Original FastAPI backend with:
  - GitHub API integration
  - Google Drive scanning
  - OSINT username scanner
  - Reddit comment management
  - HaveIBeenPwned integration
  - Local storage scanning

*Note: Detailed changelog not available for initial development phase.*

---

## Unreleased

- [ ] Add typespecs to all public functions
- [ ] Increase test coverage to 80%+
- [ ] Configure Credo for code analysis
- [ ] Organize code following DDD bounded contexts