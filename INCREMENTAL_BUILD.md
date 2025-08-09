# Incremental Build System for Ungoogled Chromium

This document explains the new incremental build system that dramatically reduces build times after the initial compilation.

## Overview

The incremental build system preserves build artifacts between runs, allowing subsequent builds to only recompile changed files. This reduces build times from ~1 hour to 5-15 minutes for typical changes.

## Key Features

- **Incremental Builds**: Only rebuilds changed files
- **ccache Support**: Caches compilation results for even faster rebuilds
- **Persistent Volumes**: Docker volumes preserve build artifacts between runs
- **Smart Patching**: Only applies patches once, tracks with marker files
- **Clean Build Option**: Can still do full clean builds when needed

## Quick Start

### First Build (Full Build)
```bash
./docker-build-incremental.sh
```
This will take ~1 hour as it builds everything from scratch.

### Subsequent Builds (Incremental)
```bash
./docker-build-incremental.sh
```
This will take 5-15 minutes, only rebuilding changed files.

### Force Clean Build
```bash
./docker-build-incremental.sh --clean
```
This removes all build artifacts and starts fresh (takes ~1 hour).

## File Structure

```
desktop-linux-builder/
├── .persistent/                    # Persistent storage (git-ignored)
│   ├── build/                     # Build artifacts
│   │   ├── src/                   # Chromium source with patches applied
│   │   ├── .markers/              # Tracks what steps have been completed
│   │   └── download_cache/        # Downloaded Chromium tarballs
│   ├── ccache/                    # Compiler cache
│   └── download_cache/            # Download cache
├── build-incremental.sh           # New incremental build script
├── docker-build-incremental.sh    # New Docker wrapper with volumes
└── [original files...]
```

## How It Works

### 1. Persistent Volumes
The system uses Docker volumes to persist:
- **Build directory**: Contains source code and compiled objects
- **ccache directory**: Stores cached compilation results
- **Download cache**: Keeps downloaded Chromium sources

### 2. Marker Files
The build system uses marker files to track completed steps:
- `patches_applied`: Ungoogled patches have been applied
- `domain_substitution_applied`: Domain substitution completed
- `local_patches_applied`: Your custom patches applied
- `hosts_fixed`: Download hosts have been fixed
- `tools_setup`: Prebuilt tools (Rust, Clang) are set up

### 3. ccache Integration
- Automatically detects and uses ccache if available
- Caches compilation results up to 50GB
- Dramatically speeds up rebuilds when switching branches

## Usage Scenarios

### Making Code Changes
1. Make your changes to the Chromium source
2. Run `./docker-build-incremental.sh`
3. Only modified files will be recompiled

### Updating Patches
1. Modify your patch files
2. Run `./docker-build-incremental.sh --clean`
3. This ensures patches are reapplied correctly

### Switching Branches
1. Switch to a different branch
2. Run `./docker-build-incremental.sh`
3. ccache will speed up compilation of previously compiled code

## Performance Comparison

| Build Type | Time | When to Use |
|------------|------|-------------|
| First Build | ~60 minutes | Initial setup |
| Incremental Build | 5-15 minutes | After code changes |
| Incremental with ccache hit | 2-5 minutes | Reverting changes or switching branches |
| Clean Build | ~60 minutes | After major changes or patch updates |

## Troubleshooting

### Build Fails After Changes
Try a clean build:
```bash
./docker-build-incremental.sh --clean
```

### Running Out of Disk Space
The persistent storage can grow large (50-100GB). Check usage:
```bash
du -sh .persistent/*
```

Clean ccache if needed:
```bash
rm -rf .persistent/ccache/*
```

### Need to Update Docker Image
```bash
./docker-build-incremental.sh --rebuild-image
```

## Advanced Options

### Manual ccache Statistics
```bash
docker run --rm -v $(pwd)/.persistent/ccache:/home/ubuntu/.ccache chromium-builder:noble \
    ccache --show-stats
```

### Clear Specific Caches
```bash
# Clear only build artifacts, keep downloads and ccache
rm -rf .persistent/build/src .persistent/build/.markers

# Clear only ccache
rm -rf .persistent/ccache/*

# Clear everything
rm -rf .persistent/
```

### Customize Build Parallelism
The system automatically uses all CPU cores. To limit:
```bash
export NINJA_JOBS=4  # Use only 4 cores
./docker-build-incremental.sh
```

## Tips for Faster Development

1. **Use ccache**: It's automatically configured if installed in the Docker image
2. **Don't clean unless necessary**: Incremental builds are much faster
3. **Keep download cache**: Even clean builds will be faster with cached downloads
4. **Monitor disk usage**: The `.persistent` directory can grow large
5. **Make small, focused changes**: Smaller changes = faster rebuilds

## Comparison with Original Build System

| Feature | Original (build.sh) | Incremental System |
|---------|-------------------|-------------------|
| First build time | ~60 min | ~60 min |
| Subsequent builds | ~60 min | 5-15 min |
| Preserves artifacts | No | Yes |
| ccache support | No | Yes |
| Disk usage | Minimal | 50-100GB |
| Docker volumes | No | Yes |

## Migration from Original System

The new incremental system coexists with the original:
- `docker-build.sh` → Original clean build system
- `docker-build-incremental.sh` → New incremental system

You can use either system. The incremental system is recommended for development.

## Notes

- The `.persistent` directory is automatically added to `.gitignore`
- Build artifacts are stored outside the git repository
- The system is compatible with your existing patches and configurations
- You can still use the original `docker-build.sh` if needed
