# CountryTags Plugin - Copilot Instructions

## Repository Overview
This repository contains a SourceMod plugin for Source engine games that automatically assigns clan tags and flags based on players' country locations using GeoIP. The plugin is designed for CS:GO/CS2 servers and integrates with SourceMod's client preferences system.

## Technical Environment
- **Language**: SourcePawn (.sp files)
- **Platform**: SourceMod 1.11+ (see sourceknight.yaml for exact version)
- **Target Game**: CS:GO/CS2 (Counter-Strike games)
- **Build System**: SourceKnight (Docker-based compilation)
- **CI/CD**: GitHub Actions with automated building and releases

## Project Structure
```
/
├── addons/sourcemod/scripting/          # Source code
│   └── CountryTags.sp                   # Main plugin file
├── csgo/                                # Game-specific files
│   ├── addons/sourcemod/configs/        # Configuration files
│   │   └── countryflags.cfg            # Country code to flag mappings
│   └── materials/panorama/              # UI assets (flag images)
├── .github/workflows/ci.yml             # CI/CD pipeline
└── sourceknight.yaml                   # Build configuration
```

## Build System
The project uses **SourceKnight** for compilation:
- Build configuration in `sourceknight.yaml`
- Dependencies: SourceMod 1.11.0-git6934, MultiColors plugin
- Output: Compiled .smx files in `/addons/sourcemod/plugins`
- CI builds automatically on push/PR and creates releases

To build locally, use the SourceKnight Docker action or compatible toolchain.

## Core Functionality
The plugin (`CountryTags.sp`):
1. **GeoIP Integration**: Uses SourceMod's GeoIP extension to detect player countries
2. **Clan Tag Assignment**: Sets clan tags to country codes (e.g., "US", "CA", "UK")
3. **Flag Display**: Shows country flags in game scoreboard using custom materials
4. **Client Preferences**: Allows players to disable country tags via cookies and cookie menu integration
5. **Bot Support**: Configurable country tags for bots
6. **Team-based Logic**: Only applies tags when players join non-spectator teams

## Key Components

### Global Variables
- `g_cvTagMethod`: ConVar controlling plugin functionality (0=disabled, 1=tag all, 2=tag tagless only)
- `g_cvBotTags`: ConVar with comma-separated bot country codes
- `g_aryBotTags`: ArrayList storing parsed bot tags
- `g_hCTagCookie`: Client preference cookie for enabling/disabling tags
- `g_sCountryTag[MAXPLAYERS + 1][6]`: Array storing each player's country code

### Core Functions
- `OnPluginStart()`: Initialization, ConVar creation, event hooks
- `OnClientPostAdminCheck()`: GeoIP lookup and country tag assignment
- `SetClientClanTagToCountryCode()`: Main tag assignment logic
- `TagPlayer()`: Determines if player should be tagged based on settings
- `Event_PlayerTeam()`: Handles team changes and delayed tag application

## Code Style & Standards
This repository follows SourcePawn best practices:

### Formatting
- Indentation: Tabs (4 spaces equivalent)
- Line endings: CRLF (Windows-style)
- `#pragma semicolon 1` and `#pragma newdecls required` enforced

### Naming Conventions
- Global variables: `g_` prefix (e.g., `g_cvTagMethod`)
- Member variables: `m_` prefix (e.g., `m_iLevel`)
- Functions: PascalCase (e.g., `SetClientClanTagToCountryCode`)
- Local variables: camelCase (e.g., `sBuffer`, `iClient`)
- Constants: ALL_CAPS (e.g., `SIZEOF_BOTTAG`)

### Memory Management
- Use `delete` for cleanup (no null checks needed)
- Avoid `.Clear()` on ArrayList/StringMap (causes memory leaks)
- Prefer `new ArrayList()` over array-based solutions
- Handle late loading scenarios in `OnPluginStart()`

## Development Guidelines

### Making Changes
1. **Test Thoroughly**: Plugin affects player visibility and game experience
2. **Handle Edge Cases**: Consider late loading, disconnections, team changes
3. **GeoIP Reliability**: Account for failed GeoIP lookups and local/bot clients
4. **Performance**: Minimize operations in frequently called functions
5. **Backwards Compatibility**: Maintain ConVar names and functionality

### Common Patterns
- **Late Loading**: Check `g_bLateLoad` and handle existing clients
- **Client Validation**: Always validate client index and connection state
- **ConVar Changes**: Use change hooks for runtime configuration updates
- **Timer Usage**: Use `CreateTimer()` for delayed operations (e.g., tag application)
- **Cookie Integration**: Respect player preferences via client cookies

### Dependencies
- **SourceMod Extensions**: GeoIP (for country detection), ClientPrefs (for cookies)
- **Include Files**: `<clientprefs>`, `<cstrike>`, `<geoip>`, `<multicolors>`
- **External Plugins**: 
  - MultiColors (required for colored chat messages)
  - SCL (SourceComms Levels) - optional integration for level-based features
  - Note: SCL native is marked as optional and won't cause plugin failure if missing

## Configuration Files

### countryflags.cfg
Maps country codes to flag indices for display:
```
"CountryFlags"
{
    "US" { "index" "1200" }
    "CA" { "index" "1201" }
    // ... more mappings
}
```

### ConVars
- `sm_countrytags`: Plugin mode (0=off, 1=all players, 2=tagless only)
- `sm_countrytags_bots`: Comma-separated bot country codes

### Console Commands
- `sm_ctag`: Toggles country tag display for the calling player
- `sm_showflag`: Alias for `sm_ctag` command
- Both commands require cached client cookies and allow players to hide their country flags

## Testing & Validation
- **Build Testing**: Ensure compilation succeeds with SourceKnight
- **Runtime Testing**: Test on development server with multiple scenarios:
  - Players joining different teams
  - Late loading scenarios
  - ConVar changes during gameplay
  - Cookie preferences (enable/disable tags)
  - Bot handling
- **Memory Testing**: Use SourceMod profiler to check for leaks

## Common Issues & Solutions
1. **Tags not appearing**: Check team assignment, GeoIP data, and ConVar settings
2. **Memory leaks**: Ensure proper cleanup in `OnPluginEnd()` and avoid `.Clear()`
3. **Late loading problems**: Verify client iteration and cookie caching in `OnPluginStart()`
4. **Performance issues**: Review timer usage and frequent function calls

## Release Process
- Version updates in plugin info block
- CI automatically builds and creates GitHub releases
- Artifacts include compiled plugin and game assets
- Use semantic versioning (MAJOR.MINOR.PATCH)

## Key Files to Understand
1. `CountryTags.sp` - Main plugin logic
2. `sourceknight.yaml` - Build dependencies and configuration
3. `countryflags.cfg` - Country to flag ID mappings
4. `.github/workflows/ci.yml` - Build and release automation

When working on this plugin, prioritize stability and performance since it affects all players on a server. Always test changes thoroughly and consider the impact on server performance.