#!/bin/bash

# Parse command line arguments
clean_build=false
clone=false
while getopts "cC" opt; do
    case "${opt}" in
        c) clean_build=true ;;
        C) clone=true ;;
    esac
done

# directories
# ==================================================
root_dir="$(dirname $(readlink -f $0))"
main_repo="${root_dir}/desktop"

build_dir="${root_dir}/build"
download_cache="${build_dir}/download_cache"
src_dir="${build_dir}/src"
markers_dir="${build_dir}/.markers"

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

# Setup ccache
# ==================================================
setup_ccache() {
    if command -v ccache &> /dev/null; then
        echo_info "Setting up ccache..."
        export USE_CCACHE=1
        export CCACHE_DIR="${build_dir}/.ccache"
        export CCACHE_MAXSIZE="50G"
        export CCACHE_COMPRESS=1
        export CCACHE_COMPRESSLEVEL=6

        mkdir -p "${CCACHE_DIR}"
        ccache -M 50G
        ccache --show-stats
    else
        echo_warn "ccache not found. Consider installing it for faster rebuilds."
    fi
}

# Check if patches have been applied
# ==================================================
check_patches_applied() {
    [ -f "${markers_dir}/patches_applied" ] && \
    [ -f "${markers_dir}/domain_substitution_applied" ] && \
    [ -f "${markers_dir}/local_patches_applied" ]
}

# Check if source exists and is valid
# ==================================================
check_source_exists() {
    [ -d "${src_dir}" ] && \
    [ -f "${src_dir}/BUILD.gn" ] && \
    [ -d "${src_dir}/chrome" ]
}

# Clean build if requested
# ==================================================
if $clean_build; then
    echo_warn "Clean build requested. Removing build artifacts..."
    rm -rf "${src_dir}" "${build_dir}/domsubcache.tar.gz" "${markers_dir}"
    # Keep download cache and ccache
    echo_info "Preserving download cache and ccache..."
fi

mkdir -p "${src_dir}" "${download_cache}" "${markers_dir}"

# Fetch sources if needed
# ==================================================
if ! check_source_exists; then
    echo_info "Fetching Chromium sources..."
    if $clone; then
        "${main_repo}/utils/clone.py" --sysroot amd64 -o "${src_dir}"
    else
        "${main_repo}/utils/downloads.py" retrieve -i "${main_repo}/downloads.ini" -c "${download_cache}"
        "${main_repo}/utils/downloads.py" unpack -i "${main_repo}/downloads.ini" -c "${download_cache}" "${src_dir}"
    fi

    # Mark that we need to apply patches
    rm -f "${markers_dir}"/*
else
    echo_info "Source directory exists. Skipping download/extraction."
fi

mkdir -p "${src_dir}/out/Default"

# Apply patches if needed
# ==================================================
if ! check_patches_applied; then
    echo_info "Applying patches..."

    # Apply c2-browser patches
    if [ ! -f "${markers_dir}/patches_applied" ]; then
        echo_info "Applying c2-browser patches..."
        "${main_repo}/utils/prune_binaries.py" "${src_dir}" "${main_repo}/pruning.list"
        "${main_repo}/utils/patches.py" apply "${src_dir}" "${main_repo}/patches"
        touch "${markers_dir}/patches_applied"
    fi

    # Apply domain substitution
    if [ ! -f "${markers_dir}/domain_substitution_applied" ]; then
        echo_info "Applying domain substitution..."
        "${main_repo}/utils/domain_substitution.py" apply -r "${main_repo}/domain_regex.list" \
            -f "${main_repo}/domain_substitution.list" -c "${build_dir}/domsubcache.tar.gz" "${src_dir}"
        touch "${markers_dir}/domain_substitution_applied"
    fi

    # Apply local patches
    if [ ! -f "${markers_dir}/local_patches_applied" ]; then
        echo_info "Applying local patches..."
        cd "${src_dir}"

        # Use the --oauth2-client-id= and --oauth2-client-secret= switches
        patch -Np1 -i ${root_dir}/use-oauth2-client-switches-as-default.patch
        # disable check for a specific node version
        patch -Np1 -i ${root_dir}/drop-nodejs-version-check.patch

        touch "${markers_dir}/local_patches_applied"
    fi
else
    echo_info "Patches already applied. Skipping patch phase."
fi

cd "${src_dir}"

# Update GN flags (always do this in case flags.gn changed)
# ==================================================
echo_info "Updating GN flags..."
cat "${main_repo}/flags.gn" "${root_dir}/flags.gn" >"${src_dir}/out/Default/args.gn"

# Fix download hosts (only if not done already)
# ==================================================
if [ ! -f "${markers_dir}/hosts_fixed" ]; then
    echo_info "Fixing download hosts..."
    sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' ./build/linux/sysroot_scripts/sysroots.json
    sed -i 's/commondatastorage.9oo91eapis.qjz9zk/commondatastorage.googleapis.com/g' ./tools/clang/scripts/update.py
    touch "${markers_dir}/hosts_fixed"
fi

# Setup prebuilt tools (check if already done)
# ==================================================
if [ ! -f "${markers_dir}/tools_setup" ]; then
    echo_info "Setting up prebuilt tools..."

    # use prebuilt rust
    ./tools/rust/update_rust.py
    # to link to rust libraries we need to compile with prebuilt clang
    ./tools/clang/scripts/update.py
    # install sysroot if according gn flag is set to true
    if grep -q -F "use_sysroot=true" "${src_dir}/out/Default/args.gn"; then
        ./build/linux/sysroot_scripts/install-sysroot.py --arch=amd64
    fi

    touch "${markers_dir}/tools_setup"
else
    echo_info "Prebuilt tools already setup. Skipping..."
fi

# Link to system tools
# ==================================================
if [ ! -L "third_party/node/linux/node-linux-x64/bin/node" ]; then
    echo_info "Linking system Node.js..."
    mkdir -p third_party/node/linux/node-linux-x64/bin
    ln -s /usr/bin/node third_party/node/linux/node-linux-x64/bin/node
fi

# Build
# ==================================================
echo_info "Starting build process..."

_clang_path="${src_dir}/third_party/llvm-build/Release+Asserts/bin"

# Setup ccache wrapper if available
if command -v ccache &> /dev/null; then
    setup_ccache

    # Create ccache wrapper scripts
    wrapper_dir="${build_dir}/.ccache-wrappers"
    mkdir -p "${wrapper_dir}"

    echo "#!/bin/bash" > "${wrapper_dir}/clang"
    echo "exec ccache ${_clang_path}/clang \"\$@\"" >> "${wrapper_dir}/clang"
    chmod +x "${wrapper_dir}/clang"

    echo "#!/bin/bash" > "${wrapper_dir}/clang++"
    echo "exec ccache ${_clang_path}/clang++ \"\$@\"" >> "${wrapper_dir}/clang++"
    chmod +x "${wrapper_dir}/clang++"

    export CC="${wrapper_dir}/clang"
    export CXX="${wrapper_dir}/clang++"
    export AR="${_clang_path}/llvm-ar"
    export NM="${_clang_path}/llvm-nm"
else
    export CC="${_clang_path}/clang"
    export CXX="${_clang_path}/clang++"
    export AR="${_clang_path}/llvm-ar"
    export NM="${_clang_path}/llvm-nm"
fi

export LLVM_BIN="${_clang_path}"

# Set compiler flags
llvm_resource_dir=$("${_clang_path}/clang" --print-resource-dir)
export CXXFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
export CPPFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"
export CFLAGS+=" -resource-dir=${llvm_resource_dir} -B${LLVM_BIN}"

# Build GN if needed
if [ ! -f "out/Default/gn" ]; then
    echo_info "Building GN..."
    ./tools/gn/bootstrap/bootstrap.py -o out/Default/gn --skip-generate-buildfiles
fi

# Generate build files (always regenerate to pick up any changes)
echo_info "Generating build files..."
./out/Default/gn gen out/Default --fail-on-unused-args

# Execute build with ninja
echo_info "Building Chrome (incremental build)..."
BUILD_START=$(date +%s)

# Use all available cores for parallel compilation
NINJA_ARGS="-j$(nproc)"

# Add verbose flag if needed for debugging
# NINJA_ARGS="${NINJA_ARGS} -v"

ninja -C out/Default ${NINJA_ARGS} chrome chrome_sandbox chromedriver

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

echo_info "Build completed in $((BUILD_TIME / 60)) minutes and $((BUILD_TIME % 60)) seconds"

# Show ccache statistics if available
if command -v ccache &> /dev/null; then
    echo_info "ccache statistics:"
    ccache --show-stats
fi
