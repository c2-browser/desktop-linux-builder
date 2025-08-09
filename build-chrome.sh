#!/bin/bash

# Simple wrapper script for building C2 browser
# Provides an easy interface to the incremental build system

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

echo_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

# Default to incremental build
BUILD_TYPE="incremental"
CLEAN_FLAG=""
EXTRA_ARGS=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        clean|--clean|-c)
            BUILD_TYPE="clean"
            CLEAN_FLAG="--clean"
            shift
            ;;
        incremental|--incremental|-i)
            BUILD_TYPE="incremental"
            shift
            ;;
        legacy|--legacy|-l)
            BUILD_TYPE="legacy"
            shift
            ;;
        rebuild-image|--rebuild-image)
            EXTRA_ARGS="${EXTRA_ARGS} --rebuild-image"
            shift
            ;;
        help|--help|-h)
            echo "C2 Build Wrapper"
            echo ""
            echo "Usage: $0 [COMMAND] [OPTIONS]"
            echo ""
            echo "Commands:"
            echo "  incremental  Build incrementally (default, fast)"
            echo "  clean        Clean build from scratch (slow)"
            echo "  legacy       Use original build system"
            echo ""
            echo "Options:"
            echo "  --rebuild-image  Rebuild the Docker image"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Incremental build (default)"
            echo "  $0 incremental        # Explicit incremental build"
            echo "  $0 clean              # Clean build"
            echo "  $0 legacy             # Use original build system"
            echo "  $0 --rebuild-image    # Rebuild Docker image first"
            echo ""
            echo "Build Artifacts:"
            echo "  Incremental: .persistent/build/src/out/Default/chrome"
            echo "  Legacy:      build/src/out/Default/chrome"
            exit 0
            ;;
        *)
            echo_error "Unknown option: $1"
            echo "Use '$0 --help' for usage information"
            exit 1
            ;;
    esac
done

# Check if running in the correct directory
if [ ! -f "docker-build.sh" ]; then
    echo_error "This script must be run from the desktop-linux-builder directory"
    exit 1
fi

# Display build information
echo_header "C2 Browser Build System"
echo_info "Build Type: ${BUILD_TYPE}"

if [ "${BUILD_TYPE}" = "legacy" ]; then
    echo_warn "Using legacy build system (slow, no caching)"
    echo_info "Starting build with docker-build.sh..."
    ./docker-build.sh
elif [ "${BUILD_TYPE}" = "clean" ]; then
    if [ ! -f "docker-build-incremental.sh" ]; then
        echo_error "Incremental build system not found!"
        echo_info "Falling back to legacy build system..."
        ./docker-build.sh
    else
        echo_warn "Clean build requested - this will take ~1 hour"
        echo_info "All build artifacts will be removed"
        read -p "Continue? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            ./docker-build-incremental.sh --clean ${EXTRA_ARGS}
        else
            echo_info "Build cancelled"
            exit 0
        fi
    fi
else
    # Incremental build (default)
    if [ ! -f "docker-build-incremental.sh" ]; then
        echo_error "Incremental build system not found!"
        echo_info "Falling back to legacy build system..."
        ./docker-build.sh
    else
        # Check if this is the first build
        if [ ! -d ".persistent/build/src" ]; then
            echo_info "First build detected - this will take ~1 hour"
            echo_info "Subsequent builds will be much faster (5-15 minutes)"
        else
            echo_info "Incremental build - should be fast (5-15 minutes)"

            # Show last build time if available
            if [ -d ".persistent/build/src/out/Default" ]; then
                CHROME_BIN=".persistent/build/src/out/Default/chrome"
                if [ -f "$CHROME_BIN" ]; then
                    LAST_BUILD=$(stat -c %y "$CHROME_BIN" 2>/dev/null | cut -d' ' -f1,2 | cut -d'.' -f1)
                    echo_info "Last successful build: ${LAST_BUILD}"
                fi
            fi
        fi

        ./docker-build-incremental.sh ${CLEAN_FLAG} ${EXTRA_ARGS}
    fi
fi

# Post-build information
if [ $? -eq 0 ]; then
    echo
    echo_header "Build Completed Successfully!"

    if [ "${BUILD_TYPE}" != "legacy" ] && [ -f ".persistent/build/src/out/Default/chrome" ]; then
        echo_info "Chrome binary location:"
        echo "  .persistent/build/src/out/Default/chrome"
        echo ""
        echo_info "To run Chrome:"
        echo "  .persistent/build/src/out/Default/chrome"
        echo ""
        echo_info "To run with custom flags:"
        echo "  .persistent/build/src/out/Default/chrome --user-data-dir=/tmp/chrome-test"
    elif [ -f "build/src/out/Default/chrome" ]; then
        echo_info "Chrome binary location:"
        echo "  build/src/out/Default/chrome"
        echo ""
        echo_info "To run Chrome:"
        echo "  build/src/out/Default/chrome"
    fi

    # Show disk usage
    if [ -d ".persistent" ]; then
        echo ""
        echo_info "Disk usage:"
        du -sh .persistent/* 2>/dev/null | sed 's|.persistent/||' | while read size dir; do
            echo "  - $dir: $size"
        done
    fi
else
    echo_error "Build failed!"
    exit 1
fi
