# DVD Rip Automation

Automated DVD and Blu-ray ripping and encoding workflow using MakeMKV and HandBrake. Insert disc → rip → encode → eject → repeat.

## Overview

This PowerShell automation suite handles the complete workflow for digitizing DVD and Blu-ray collections:

1. **makemkv-autorip.ps1** - Automatically detects discs, rips main movie content with MakeMKV, names files using TMDb lookup, and ejects when complete
2. **handbrake-encode.ps1** - Batch encodes ripped MKV files to H.265/HEVC with optimized presets based on disc type (DVD/Blu-ray)
3. **test-tmdb-lookup.ps1** - Test utility for TMDb API movie searches
4. **test-get-disctype.ps1** - Diagnostic tool for DVD/Blu-ray drive detection

## Features

- 🔄 **Automatic disc detection and ripping**
- 🎬 **TMDb integration** for automatic movie title lookup
- 📀 **Disc type detection** (DVD vs Blu-ray) for optimized encoding
- ⚙️ **Configurable settings** via JSON file
- 📁 **Smart file naming** with automatic deduplication
- 🔁 **Continuous operation** - insert next disc after ejection
- 🎯 **Main movie extraction** using configurable length heuristics
- 💾 **H.265/HEVC encoding** for efficient file sizes

## Requirements

### Required Software

1. **[MakeMKV](https://www.makemkv.com/)** (v1.17.0 or later)
   - Free while in beta
   - Default install path: `C:\Program Files (x86)\MakeMKV\makemkvcon64.exe`
   - Used for ripping disc content to MKV format

2. **[Docker Desktop](https://www.docker.com/products/docker-desktop/)** (Windows)
   - Free for personal use
   - Required for HandBrake encoding
   - HandBrake runs in `jlesage/handbrake` container (no local installation needed)

3. **Windows PowerShell 5.1+** (included with Windows 10/11)

4. **DVD/Blu-ray Drive**
   - Must be detected by Windows as a CD-ROM drive
   - Blu-ray drive recommended for both DVD and Blu-ray support

### Optional

- **[TMDb API Key](https://www.themoviedb.org/settings/api)** (free)
  - Required for automatic movie title lookups
  - Sign up at TMDb and request an API key
  - Add to `settings.json`

## Installation

1. **Clone the repository**
   ```powershell
   git clone https://github.com/kknapp1/DVD-Rip-Automation.git
   cd DVD-Rip-Automation
   ```

2. **Install required software**
   - Install MakeMKV from link above
   - Install Docker Desktop from link above
   - Pull HandBrake Docker image:
     ```powershell
     docker pull jlesage/handbrake
     ```

3. **Configure settings**
   ```powershell
   # Copy example settings to create your config
   Copy-Item settings.example.json settings.json
   
   # Edit settings.json with your preferences
   notepad settings.json
   ```

4. **Update settings.json**
   ```json
   {
     "MakeMKV": "C:\\Program Files (x86)\\MakeMKV\\makemkvcon64.exe",
     "RipRoot": "C:\\DVD_Rip_Work\\INBOX",
     "PollSeconds": 5,
     "TitlePromptSeconds": 15,
     "TMDbApiKey": "YOUR_TMDB_API_KEY_HERE",
     "UseTMDbLookup": true
   }
   ```

## Usage

### Ripping Discs

```powershell
# Start auto-rip with default settings (1 hour minimum length)
.\makemkv-autorip.ps1

# Override minimum length (e.g., for TV shows)
.\makemkv-autorip.ps1 -MinLengthSeconds 1800  # 30 minutes
```

**Workflow:**
1. Script waits for disc insertion
2. Detects disc type (DVD/Blu-ray) and reads volume label
3. Looks up movie title via TMDb API
4. Prompts for title confirmation (15 second auto-accept)
5. Rips main movie content to `RipRoot` directory
6. Saves disc type info for encoding
7. Ejects disc and waits for next one

### Encoding Ripped Files

```powershell
# Encode all files in INBOX
.\handbrake-encode.ps1
```

**Process:**
1. Scans `RipRoot\INBOX` for `.mkv` files
2. Reads `.disctype` file to determine DVD vs Blu-ray
3. Runs HandBrake in Docker container with appropriate preset:
   - **DVD**: HQ 480p30 Surround
   - **Blu-ray**: HQ 1080p30 Surround
4. Outputs to `RipRoot\ENCODED`
5. Original files remain in `INBOX`

### Testing Utilities

```powershell
# Test disc type detection
.\test-get-disctype.ps1

# Test TMDb API lookups
.\test-tmdb-lookup.ps1
```

## Configuration Reference

### settings.json

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `MakeMKV` | string | `C:\Program Files (x86)\MakeMKV\makemkvcon64.exe` | Path to MakeMKV CLI executable |
| `RipRoot` | string | `C:\DVD_Rip_Work\INBOX` | Directory for ripped files |
| `PollSeconds` | int | `5` | Seconds between disc detection checks |
| `TitlePromptSeconds` | int | `15` | Auto-accept timeout for title confirmation |
| `TMDbApiKey` | string | `YOUR_TMDB_API_KEY_HERE` | TMDb API key for lookups |
| `UseTMDbLookup` | bool | `true` | Enable/disable TMDb integration |

### Command-Line Parameters

**makemkv-autorip.ps1**
- `-MinLengthSeconds` - Minimum title length in seconds (default: 3600)
  - Used to filter out extras and menus
  - Lower for TV shows, keep high for movies

**handbrake-encode.ps1**
- No parameters (uses Docker container automatically)

## Directory Structure

```
DVD_Rip_Work/
├── INBOX/          # Ripped MKV files (input for encoding)
│   ├── Movie Title (2024).mkv
│   └── .disctype   # DVD or BLURAY
└── ENCODED/        # Encoded MP4 files (final output)
    └── Movie Title (2024)/
        └── Movie Title (2024).mp4
```

## Encoding Presets

| Source | HandBrake Preset | Output | Notes |
|--------|-----------------|--------|-------|
| DVD | HQ 480p30 Surround | MP4 | Good quality for SD content |
| Blu-ray | HQ 1080p30 Surround | MP4 | High quality for HD/FHD content |

Presets include:
- Video: H.264 encoding with chapter markers
- Audio: Surround sound preserved
- Subtitles: All tracks included
- Container: MP4

## Troubleshooting

**Disc not detected**
- Ensure disc is properly inserted and Windows recognizes it
- Run `test-get-disctype.ps1` to diagnose drive detection
- Check drive shows as "Media Loaded" in Device Manager

**TMDb lookup fails**
- Verify API key is correct in `settings.json`
- Check internet connection
- Try manual search when prompted
- Disc label may not match movie title (use manual entry)

**MakeMKV errors**
- Ensure MakeMKV license is valid (free during beta)
- Check disc is not copy-protected beyond MakeMKV capabilities
- Try cleaning disc if read errors occur

**Encoding fails**
- Ensure Docker Desktop is running
- Verify `jlesage/handbrake` image is pulled
- Check Docker has access to drive letters (Docker Desktop settings)
- Ensure sufficient disk space in ENCODED directory
- Check input MKV file is not corrupted

## Tips

- **Batch Processing**: Let makemkv-autorip run overnight with a stack of discs
- **Docker Performance**: Ensure Docker Desktop has adequate RAM allocated (8GB+ recommended)
- **Custom Presets**: Modify `$PresetDVD` and `$PresetBluRay` in handbrake-encode.ps1 for different quality
- **TV Shows**: Use `-MinLengthSeconds 1200` (20 min) for TV episode detection
- **Manual Titles**: Press Enter at prompt to type custom title if TMDb lookup fails
- **Disc Cleaning**: Clean discs before ripping to avoid read errors

## Known Limitations

- Windows only (uses WMI and COM for drive access)
- Single drive support (uses first detected drive)
- Main movie only (extras not ripped)
- No multi-disc set coordination

## Contributing

Issues and pull requests welcome at https://github.com/kknapp1/DVD-Rip-Automation

## License

This project is provided as-is for personal use. MakeMKV and HandBrake have their own licenses.

## Credits

- [MakeMKV](https://www.makemkv.com/) - GuinpinSoft inc
- [HandBrake](https://handbrake.fr/) - HandBrake Team
- [TMDb](https://www.themoviedb.org/) - The Movie Database
