#!/bin/bash

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
GIT_SUBMODULE="desktop"

BUILDER_DISTRO="noble"
IMAGE="chromium-builder:$BUILDER_DISTRO"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Parse command line arguments
CLEAN_BUILD=""
REBUILD_IMAGE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN_BUILD="-c"
            echo_warn "Clean build requested. This will take longer."
            shift
            ;;
        --rebuild-image)
            REBUILD_IMAGE=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean          Perform a clean build (removes all artifacts)"
            echo "  --rebuild-image  Rebuild the Docker image"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Incremental build (fast)"
            echo "  $0 --clean            # Clean build (slow)"
            echo "  $0 --rebuild-image    # Rebuild Docker image and then build"
            exit 0
            ;;
        *)
            echo_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Build or rebuild Docker image if requested
if [ "$REBUILD_IMAGE" = true ] || [ ! "$(docker images -q ${IMAGE} 2> /dev/null)" ]; then
    echo_info "Building Docker image '${IMAGE}'..."
    (cd $BASE_DIR/docker && docker buildx build -t ${IMAGE} -f ./build.Dockerfile .) || {
        echo_error "Failed to build Docker image"
        exit 1
    }
else
    echo_info "Using existing Docker image '${IMAGE}'"
fi

# Checkout ungoogled-chromium submodule if not present
if [ ! -n "$(ls -A ${BASE_DIR}/${GIT_SUBMODULE} 2>/dev/null)" ]; then
    echo_info "Initializing git submodules..."
    git submodule update --init --recursive || {
        echo_error "Failed to initialize git submodules"
        exit 1
    }
fi

# Create persistent directories for build artifacts
echo_info "Setting up persistent volumes..."
PERSISTENT_DIR="${BASE_DIR}/.persistent"
mkdir -p "${PERSISTENT_DIR}/build"
mkdir -p "${PERSISTENT_DIR}/ccache"
mkdir -p "${PERSISTENT_DIR}/download_cache"

# Docker run configuration
DOCKER_RUN_CMD="docker run -it --rm"

# Mount the repository
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -v ${BASE_DIR}:/repo"

# Mount persistent volumes for incremental builds
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -v ${PERSISTENT_DIR}/build:/repo/build"
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -v ${PERSISTENT_DIR}/ccache:/home/ubuntu/.ccache"
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -v ${PERSISTENT_DIR}/download_cache:/repo/build/download_cache"

# Set environment variables for ccache
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -e USE_CCACHE=1"
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -e CCACHE_DIR=/home/ubuntu/.ccache"
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -e CCACHE_MAXSIZE=50G"
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -e CCACHE_COMPRESS=1"

# Use the host's CPU count for parallel builds
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} -e NINJA_JOBS=$(nproc)"

# Add the image and command
DOCKER_RUN_CMD="${DOCKER_RUN_CMD} ${IMAGE}"

# Determine which build script to use
if [ -f "${BASE_DIR}/build-incremental.sh" ]; then
    BUILD_SCRIPT="/repo/build-incremental.sh"
    echo_info "Using incremental build script"
else
    BUILD_SCRIPT="/repo/build.sh"
    echo_warn "Incremental build script not found, falling back to original build.sh"
fi

# Execute build within docker container
BUILD_START=$(date)
echo_info "Starting Docker build at ${BUILD_START}"

if [ -n "$CLEAN_BUILD" ]; then
    echo_warn "Performing clean build..."
    # For clean build, we need to clear the persistent directories
    echo_info "Clearing persistent build artifacts..."
    rm -rf "${PERSISTENT_DIR}/build/src"
    rm -rf "${PERSISTENT_DIR}/build/.markers"
    rm -rf "${PERSISTENT_DIR}/build/domsubcache.tar.gz"
    # Keep ccache and download cache even on clean builds
fi

# Show disk usage of persistent directories
echo_info "Persistent storage usage:"
du -sh "${PERSISTENT_DIR}"/* 2>/dev/null | sed 's|'"${PERSISTENT_DIR}"'/||' | while read size dir; do
    echo "  - $(basename $dir): $size"
done

# Run the build
${DOCKER_RUN_CMD} /bin/bash -c "${BUILD_SCRIPT} ${CLEAN_BUILD}"
BUILD_EXIT_CODE=$?

BUILD_END=$(date)
echo_info "Docker build completed at ${BUILD_END}"
echo_info "Started at: ${BUILD_START}"
echo_info "Ended at:   ${BUILD_END}"

# Calculate and display build time
START_SECONDS=$(date -d "${BUILD_START}" +%s)
END_SECONDS=$(date -d "${BUILD_END}" +%s)
DURATION=$((END_SECONDS - START_SECONDS))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))
echo_info "Total build time: ${MINUTES} minutes and ${SECONDS} seconds"

# Show final disk usage
echo_info "Final persistent storage usage:"
du -sh "${PERSISTENT_DIR}"/* 2>/dev/null | sed 's|'"${PERSISTENT_DIR}"'/||' | while read size dir; do
    echo "  - $(basename $dir): $size"
done

# Show ccache statistics if available
if [ -d "${PERSISTENT_DIR}/ccache" ]; then
    echo_info "Checking ccache statistics..."
    docker run --rm -v ${PERSISTENT_DIR}/ccache:/home/ubuntu/.ccache ${IMAGE} \
        /bin/bash -c "ccache --show-stats 2>/dev/null || echo 'ccache stats not available'"
fi

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo_info "Build completed successfully!"
    echo_info "Binaries are located in: ${PERSISTENT_DIR}/build/src/out/Default/"
    echo ""
    echo_info "To run Chrome:"
    echo "  ${PERSISTENT_DIR}/build/src/out/Default/chrome"
else
    echo_error "Build failed with exit code ${BUILD_EXIT_CODE}"
    exit $BUILD_EXIT_CODE
fi
