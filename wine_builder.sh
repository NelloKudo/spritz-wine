#!/usr/bin/env bash

set -euo pipefail

Info() {
    echo -e '\033[1;34m'"WineBuilder:\033[0m $*"
}

Error() {
    echo -e '\033[1;31m'"WineBuilder:\033[0m $*"
    exit 1
}

## ------------------------------------------------------------
##                  Configuration
## ------------------------------------------------------------

_configuration() {
    # Toggle to enable/disable Wine-Staging.
    USE_STAGING="${USE_STAGING:-false}"
    STAGING_ARGS="${STAGING_ARGS:-"--all"}"

    # Toggle to enable/disable Wine-tkg.
    USE_TKG="${USE_TKG:-false}"

    # Toggle to enable/disable Wine-CachyOS.
    USE_CACHY="${USE_CACHY:-true}"

    # Toggle to enable/disable Wine-Valve.
    USE_VALVE="${USE_VALVE:-false}"

    # Set your custom build name here:
    BUILD_NAME="${BUILD_NAME:-spritz-wine-cachyos}"

    # Wine version settings
    WINE_VERSION=''
    STAGING_VERSION=''
    WINE_BRANCH="${WINE_BRANCH:-}"
    RELEASE_VERSION='11'
    PATCHSET=''

    # Build configuration
    # You can change the default value by changing the value after :-
    USE_WOW64="${1:-true}"
    BUILD_FONTS="${2:-false}"
    DEBUG="${3:-false}"
    USE_LLVM_MINGW="${4:-false}"

    # Wine links
    WINE_URL="https://github.com/wine-mirror/wine.git"
    STAGING_URL="https://github.com/wine-staging/wine-staging.git"
    
    # Fallback links
    WINE_FALLBACK_URL="https://gitlab.winehq.org/wine/wine.git"
    STAGING_FALLBACK_URL="https://gitlab.winehq.org/wine/wine-staging.git"

    # Other links
    WINE_TKG_URL="https://github.com/Kron4ek/wine-tkg"
    WINE_CACHY_URL="https://github.com/CachyOS/wine-cachyos"
    WINE_VALVE_URL="https://github.com/ValveSoftware/wine"

    # tkg/cachy/valve settings
    for variant in tkg cachy valve; do
        use_flag="USE_${variant^^}"
        url_var="WINE_${variant^^}_URL"

        if [ "${!use_flag}" = "true" ]; then
            USE_STAGING="false"
            WINE_URL="${!url_var}"
        fi
    done
}

## ------------------------------------------------------------
##                  Build Functions
## ------------------------------------------------------------

_staging_patcher() {
    Info "Applying Wine-Staging patches..."

    local staging_patcher
    if [ -f "wine-staging-${WINE_VERSION}/patches/patchinstall.sh" ]; then
        staging_patcher=("${BUILD_DIR}/wine-staging-${WINE_VERSION}/patches/patchinstall.sh"
            DESTDIR="${BUILD_DIR}/wine")
    else
        staging_patcher=("${BUILD_DIR}/wine-staging-${WINE_VERSION}/staging/patchinstall.py")
    fi

    cd "${BUILD_DIR}/wine" || Error "Failed to change to wine source directory"

    # Apply staging overrides if they exist
    if find "${patches_dir}/staging-overrides" -name "*spatch" -print0 -quit | grep . >/dev/null; then
        for override in "${patches_dir}"/staging-overrides/*; do
            base=$(basename "${override}")
            dest=$(find "${BUILD_DIR}/wine-staging-${WINE_VERSION}/patches/" -name "${base%.spatch}*")
            cp "${override}" "${dest}"
        done
        Info "Applied staging patch overrides"
    fi

    if [ -n "${STAGING_ARGS}" ]; then
        "${staging_patcher[@]}" --no-autoconf ${STAGING_ARGS}
    else
        "${staging_patcher[@]}" --no-autoconf --all
    fi || Error "Failed to apply Wine-Staging patches"
}

_custompatcher() {
    patchlist=()

    pattern=("(" "(" "-regex" ".*\.patch")

    # Add specific branches behavior in here if needed

    pattern+=(")" ")")

    mapfile -t patchlist_tmp < <(find "${patches_dir}" -type f "${pattern[@]}" | LC_ALL=C sort -f)

    patchlist+=("${patchlist_tmp[@]}")

    for patch in "${patchlist[@]}"; do
        [ -f "${patch}" ] || continue
        Info "Applying patch: $(basename "${patch}")"
        patch -Np1 -i "${patch}" &>>"${WINE_ROOT}/patches.log" || \
            Error "Failed to apply patch: ${patch}"
    done

    ## Clean up .orig files if patches succeeded
    find "${BUILD_DIR}/wine"/ -iregex ".*orig" -execdir rm '{''}' '+' || true

    ## Restore Wine original logo
    rm "${BUILD_DIR}/wine/dlls/user32/resources/oic_winlogo.ico"
    rm "${BUILD_DIR}/wine/dlls/user32/resources/oic_winlogo.svg"
    cp -rf ${WINE_ROOT}/assets/* "${BUILD_DIR}/wine/dlls/user32/resources"
}

build_wine() {
    Info "Starting Wine build process..."

    # Setup reproducible build and ensure ccache works
    export SOURCE_DATE_EPOCH=0

    # Prepare build environment
    cd "${BUILD_DIR}"
    rm -rf build64
    mkdir -p build64
    cd build64

    export PKG_CONFIG_LIBDIR="/usr/local/x86_64/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
    export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
    export x86_64_CC="${CROSSCC_X64}"
    export i386_CC="${CROSSCC_X32}"
    export CROSSCC="${CROSSCC_X64}"

    WINE_64_BUILD_OPTIONS+=(--with-mingw="${x86_64_CC}")
    WINE_32_BUILD_OPTIONS+=(--with-mingw="${i386_CC}")

    if [ -f "/usr/local/lib/libunwind.a" ] && [ -f "/usr/local/lib/liblzma.a" ]; then
        export UNWIND_CFLAGS=""
        export UNWIND_LIBS="-L/usr/local/lib/ -static-libgcc -l:libunwind.a -l:liblzma.a"
    fi

    # Configure and build 64-bit
    "${BUILD_DIR}/wine/configure" "${WINE_BUILD_OPTIONS[@]}" "${WINE_64_BUILD_OPTIONS[@]}"
    make -j$(($(nproc) + 1))

    unset UNWIND_CFLAGS UNWIND_LIBS

    # Build 32-bit if not WoW64
    if [ "${USE_WOW64}" != "true" ]; then
        export PKG_CONFIG_LIBDIR="/usr/local/i386/lib/i386-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/lib/i386-linux-gnu/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
        export PKG_CONFIG_PATH="${PKG_CONFIG_LIBDIR}"
        export CROSSCC="${CROSSCC_X32}"

        # export I386_LIBS="-latomic" required for older fsync

        cd "${BUILD_DIR}"
        rm -rf build32
        mkdir build32
        cd build32

        "${BUILD_DIR}/wine/configure" "${WINE_BUILD_OPTIONS[@]}" "${WINE_32_BUILD_OPTIONS[@]}"
        make -j$(($(nproc) + 1))
    fi

    unset SOURCE_DATE_EPOCH
}

package_wine() {
    Info "Packaging Wine build..."

    cd "${BUILD_DIR}"

    if [ "${DEBUG}" != "true" ]; then INSTALL_TYPE="install-lib"; else INSTALL_TYPE="install"; fi

    INSTALLCMD=(
        prefix="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"
        libdir="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib"
        dlldir="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib/wine"
        "${INSTALL_TYPE}"
    )

    # Install 32-bit if not WoW64
    if [ "${USE_WOW64}" != "true" ]; then
        cd "${BUILD_DIR}/build32"
        make -j$(($(nproc) + 1)) "${INSTALLCMD[@]}"
    fi

    # Install 64-bit
    cd "${BUILD_DIR}/build64"
    make -j$(($(nproc) + 1)) "${INSTALLCMD[@]}"

    ln -srf "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib"{,64}
    ln -srf "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib"{,32}

    if [ ! -f "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/bin/wine ] && [ -f "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/bin/wine64 ]; then
        ln -srf "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/bin/wine{64,}
    fi

    if [ ! -f "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/bin/wine64 ] && [ -f "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/bin/wine ]; then
        ln -srf "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/bin/wine{,64}
    fi

    if [ "${DEBUG}" != "true" ]; then
        Info "Stripping debug symbols from libraries"
        find "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib/" \
            -type f '(' -iname '*.a' -o -iname '*.dll' -o -iname '*.so' -o -iname '*.sys' -o -iname '*.drv' -o -iname '*.exe' ')' \
            -print0 | xargs -0 strip -s 2>/dev/null || true
    fi

    rm -rf "${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"/{include,share/{applications,man}}

    # Create final package
    cd "${BUILD_DIR}"
    [ -z "${RELEASE_VERSION}" ] && RELEASE_VERSION="1"

    mv "${BUILD_OUT_TMP_DIR}" "${BUILD_NAME}"

    FINAL_DIR="${BUILD_NAME}${EXTRA_NAME:-}-${WINE_VERSION}-${RELEASE_VERSION}"
    ARCHIVE_NAME="${FINAL_DIR}-x86_64.tar.xz"

    mv "${BUILD_NAME}" "${FINAL_DIR}"

    Info "Creating and compressing ${ARCHIVE_NAME}..."
    tar -cJf \
        "${ARCHIVE_NAME}" \
        --xattrs --numeric-owner --owner=0 --group=0 "${FINAL_DIR}"

    mv "${ARCHIVE_NAME}" "${WINE_ROOT}"
}

## ------------------------------------------------------------
##                      Build Setup
## ------------------------------------------------------------

build_setup() {
    EXTRA_NAME=""
    if [ "${USE_STAGING}" = "true" ]; then EXTRA_NAME+="-staging"; fi
    if [ "${USE_WOW64}" = "true" ]; then EXTRA_NAME+="-wow64"; fi
    if [ "${DEBUG}" = "true" ]; then EXTRA_NAME+="-debug"; fi
    BUILD_OUT_TMP_DIR="wine-wb-build"

    # Ensure source directory exists
    mkdir -p "${SOURCE_DIR}"

    WINE_BUILD_OPTIONS=(
        --prefix="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}"
        --disable-tests
        --disable-winemenubuilder
        --disable-win16
        --with-x
        --with-gstreamer
        --with-ffmpeg
        --with-wayland
        --without-oss
        --without-coreaudio
        --without-cups
        --without-sane
        --without-gphoto
        --without-pcsclite
        --without-pcap
        --without-capi
        --without-v4l2
        --without-netapi
        --disable-msv1_0
        --disable-lsteamclient
    )

    if [ "${DEBUG}" = "true" ]; then
        WINE_BUILD_OPTIONS+=(--enable-build-id)
    fi

    WINE_64_BUILD_OPTIONS=(
        --libdir="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib"
    )

    # Configure WoW64 build options
    if [ "${USE_WOW64}" = "true" ]; then
        WINE_64_BUILD_OPTIONS+=(--enable-archs="x86_64,i386")
    else
        WINE_64_BUILD_OPTIONS+=(--enable-win64)
    fi

    WINE_32_BUILD_OPTIONS=(
        --libdir="${BUILD_DIR}/${BUILD_OUT_TMP_DIR}/lib"
        --with-wine64="${BUILD_DIR}/build64"
    )
}

## ------------------------------------------------------------
##                  Compiler Configuration
## ------------------------------------------------------------

compiler_setup() {
    export PKG_CONFIG="pkg-config"

    # Compiler flags
    if [ "$USE_LLVM_MINGW" = "true" ] && [ "$DEBUG" != "true" ]; then # llvm-mingw is a bit broken for debug
        # LLVM-MinGW configuration
        LLVM_MINGW_PATH="/usr/local/llvm-mingw"
        export PATH="${LLVM_MINGW_PATH}/bin:${PATH}"

        export LIBRARY_PATH="${LLVM_MINGW_PATH}/lib:/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14:/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14/32:/usr/lib/gcc-14/lib:/usr/lib/gcc-14/lib32:/usr/lib:/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/usr/local/x86_64/lib/x86_64-linux-gnu:/usr/local/i386/lib/i386-linux-gnu:/usr/local/lib/i386-linux-gnu:/usr/lib/i386-linux-gnu:${LIBRARY_PATH:-}"
        export LD_LIBRARY_PATH="${LLVM_MINGW_PATH}/lib:/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14:/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14/32:/usr/lib/gcc-14/lib:/usr/lib/gcc-14/lib32:/usr/lib:/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/usr/local/x86_64/lib/x86_64-linux-gnu:/usr/local/i386/lib/i386-linux-gnu:/usr/local/lib/i386-linux-gnu:/usr/lib/i386-linux-gnu:${LD_LIBRARY_PATH:-}"

        # Compiler settings
        export CC="ccache gcc"
        export CXX="ccache g++"
        export CROSSCC="ccache x86_64-w64-mingw32-clang"
        export CROSSCC_X32="ccache i686-w64-mingw32-clang"
        export CROSSCXX_X32="ccache i686-w64-mingw32-clang++"
        export CROSSCC_X64="ccache x86_64-w64-mingw32-clang"
        export CROSSCXX_X64="ccache x86_64-w64-mingw32-clang++"
    else #
        if [ -n "$(command -v i686-w64-mingw32-clang)" ]; then
            PATH="${PATH//"$(dirname "$(command -v i686-w64-mingw32-clang)")":/}"
        fi

        GCC_MINGW_PATH="/usr/local/gcc-mingw"
        export PATH="${GCC_MINGW_PATH}/bin:${PATH}"

        export LIBRARY_PATH="/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14:/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14/32:/usr/lib/gcc-14/lib:/usr/lib/gcc-14/lib32:/usr/lib:/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/usr/local/x86_64/lib/x86_64-linux-gnu:/usr/local/i386/lib/i386-linux-gnu:/usr/local/lib/i386-linux-gnu:/usr/lib/i386-linux-gnu:${LIBRARY_PATH:-}"
        export LD_LIBRARY_PATH="/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14:/usr/lib/gcc-14/lib/gcc/x86_64-linux-gnu/14/32:/usr/lib/gcc-14/lib:/usr/lib/gcc-14/lib32:/usr/lib:/usr/lib/x86_64-linux-gnu:/usr/local/lib:/usr/local/lib/x86_64-linux-gnu:/usr/local/x86_64/lib/x86_64-linux-gnu:/usr/local/i386/lib/i386-linux-gnu:/usr/local/lib/i386-linux-gnu:/usr/lib/i386-linux-gnu:${LD_LIBRARY_PATH:-}"

        export CC="ccache gcc"
        export CXX="ccache g++"
        export CROSSCC="ccache x86_64-w64-mingw32-gcc"
        export CROSSCC_X32="ccache i686-w64-mingw32-gcc"
        export CROSSCXX_X32="ccache i686-w64-mingw32-g++"
        export CROSSCC_X64="ccache x86_64-w64-mingw32-gcc"
        export CROSSCXX_X64="ccache x86_64-w64-mingw32-g++"
    fi

    # Flags setup
    if [ "$DEBUG" != "true" ]; then
        _common_cflags="-march=nocona -mtune=core-avx2 -pipe -O2 -fno-strict-aliasing -fwrapv -mfpmath=sse \
                        -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion -w"
        [ "$USE_LLVM_MINGW" = "true" ] && _common_cflags="${_common_cflags} -ffunction-sections -fdata-sections -Wl,--gc-sections"
    else
        _common_cflags="-march=nocona -mtune=core-avx2 -pipe -O2 -ggdb -gdwarf-4 -fvar-tracking-assignments -fno-strict-aliasing -fwrapv -mfpmath=sse \
                        -fno-omit-frame-pointer -mno-omit-leaf-frame-pointer -fdata-sections -ffunction-sections \
                        -Wno-error=incompatible-pointer-types -Wno-error=implicit-function-declaration -Wno-error=int-conversion"
    fi

    _native_common_cflags="-static-libgcc"

    export CPPFLAGS="-D_GNU_SOURCE -D_TIME_BITS=64 -D_FILE_OFFSET_BITS=64 -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -DNDEBUG -D_NDEBUG"
    _GCC_FLAGS="${_common_cflags} ${_native_common_cflags} ${CPPFLAGS}"
    _CROSS_FLAGS="${_common_cflags} ${CPPFLAGS}"
    _LD_FLAGS="${_common_cflags} ${_native_common_cflags} ${CPPFLAGS} -lrt -Wl,-O1,--sort-common,--as-needed"
    _CROSS_LD_FLAGS="${_common_cflags} ${CPPFLAGS} -Wl,-O1,--sort-common,--as-needed,--file-alignment=4096"

    # Compiler and linker flags
    export CFLAGS="${_GCC_FLAGS}"
    export CXXFLAGS="${_GCC_FLAGS}"
    export LDFLAGS="${_LD_FLAGS}"

    export CROSSCFLAGS="${_CROSS_FLAGS}"
    export CROSSCXXFLAGS="${_CROSS_FLAGS}"
    export CROSSLDFLAGS="${_CROSS_LD_FLAGS}"

    export i386_CC="${CROSSCC_X32}"
    export x86_64_CC="${CROSSCC_X64}"
    export i386_CFLAGS="${CROSSCFLAGS}"
    export x86_64_CFLAGS="${CROSSCFLAGS}"
}

## ------------------------------------------------------------
##                  Patch Management
## ------------------------------------------------------------

patch_setup() {
    # Initialize patch logging
    rm -f "${WINE_ROOT}/patches.log"

    if [ -n "${PATCHSET}" ]; then
        Info "Patchset" "${PATCHSET}"
        patches_dir="${WINE_ROOT}/patchset-current"
        rm -rf "${patches_dir}"
        mkdir -p "${patches_dir}"

        if [ "${PATCHSET:0:7}" = "remote:" ]; then
            _git_tag="${PATCHSET:7}"
            cd "${patches_dir}"

            git init
            git config advice.detachedHead false
            git remote add origin "${PATCHSET_REPO}"
            git fetch || Error "Invalid patchset repository URL"

            if [ "${_git_tag}" = "latest" ]; then
                _git_tag="$(git ls-remote --sort=-committerdate --tags origin "${TAG_FILTER}" |
                    head -n1 | cut -f2 | cut -f3 -d'/')"
                Info "Latest patchset tag: ${_git_tag}"
            fi

            git reset --hard "${_git_tag}" || Error "Invalid patchset tag"
        else
            tar xf "$(find "${WINE_ROOT}/osu-misc/" -type f -iregex ".*${PATCHSET}.*")" -C "${patches_dir}" ||
                Error "Invalid patchset specified"
        fi
    else
        patches_dir="${WINE_ROOT}/custompatches"
    fi

    [ -r "${patches_dir}/staging-exclude" ] && STAGING_ARGS+=" $(cat "${patches_dir}/staging-exclude")"
    { [ -r "${patches_dir}/wine-commit" ] && [ -z "${WINE_VERSION}" ] ; } && WINE_VERSION="$(cat "${patches_dir}/wine-commit")"
    { [ -r "${patches_dir}/staging-commit" ] && [ -z "${STAGING_VERSION}" ] ; } && STAGING_VERSION="$(cat "${patches_dir}/staging-commit")"
    return 0
}

## ------------------------------------------------------------
##                Main Execution & Settings
## ------------------------------------------------------------

main() {
    cd "${ORIGPATH}"

    # Base paths
    WINE_ROOT="/wine"
    BUILD_DIR="${WINE_ROOT}/build_wine"
    SOURCE_DIR="${WINE_ROOT}/sources"
    SOURCE_NAME="wine"

    Info "Using release version $RELEASE_VERSION"
    if [ "${DEBUG}" = "true" ]; then
        Info "Enabling debug build.."
    fi

    build_setup
    compiler_setup
    patch_setup

    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"

    # Set up source directories
    Info "Setting up Wine source code..."
    mkdir -p "${SOURCE_DIR}"

    git config --global http.lowSpeedLimit 1000
    git config --global http.lowSpeedTime 600

    # Change source name if the WINE_URL isn't the default or fallback one
    if [[ "$WINE_URL" != "https://github.com/wine-mirror/wine.git" && "$WINE_URL" != "$WINE_FALLBACK_URL" ]]; then
        case "$WINE_URL" in
            "$WINE_TKG_URL")    SOURCE_NAME="wine-tkg" ;;
            "$WINE_CACHY_URL")  SOURCE_NAME="wine-cachy" ;;
            "$WINE_VALVE_URL")  SOURCE_NAME="wine-valve" ;;
            *)                  SOURCE_NAME="wine-custom" ;;
        esac
    fi

    # Initialize/update Wine source
    if [ ! -d "${SOURCE_DIR}/${SOURCE_NAME}/.git" ]; then
        Info "Cloning Wine repository..."
        cd "${SOURCE_DIR}"
        git clone "${WINE_URL}" "${SOURCE_NAME}"
    else
        Info "Updating Wine repository..."
        cd "${SOURCE_DIR}/${SOURCE_NAME}"
        git remote set-url origin "${WINE_URL}"
        git fetch origin
    fi

    # Clean and reset Wine source
    cd "${SOURCE_DIR}/${SOURCE_NAME}"
    git reset --hard HEAD
    git clean -xdf
    git remote update

    # Checkout specific Wine version if specified
    if [ -n "${WINE_VERSION}" ]; then
        Info "Checking out Wine version: ${WINE_VERSION}"
        git fetch --all --tags
        git checkout "${WINE_VERSION}" || Error "Failed to checkout Wine version ${WINE_VERSION}"
    else
        Info "Using latest Wine version"
        (git checkout master && git pull origin master) || Info "Master not found for this repository, using default commit.."
    fi
    WINE_VERSION=$(git describe --tags --abbrev=0 | cut -f2 -d'-')
    Info "Building Wine version: ${WINE_VERSION}"

    # Custom settings for branches
    if [ -n "${WINE_BRANCH}" ]; then
        git switch "${WINE_BRANCH}"
        BUILD_NAME="$BUILD_NAME-$WINE_BRANCH"
    fi

    # Initialize/update Wine-Staging source
    if [ ! -d "${SOURCE_DIR}/wine-staging/.git" ]; then
        Info "Cloning Wine-staging repository..."
        cd "${SOURCE_DIR}"
        git clone "${STAGING_URL}" wine-staging
    else
        Info "Updating Wine-staging repository..."
        cd "${SOURCE_DIR}/wine-staging"
        git remote set-url origin "${STAGING_URL}"
        git fetch origin
    fi

    # Clean and reset Wine-Staging source
    cd "${SOURCE_DIR}/wine-staging"
    git reset --hard HEAD
    git clean -xdf
    git remote update

    # Checkout specific Staging version if specified
    if [ -n "${STAGING_VERSION}" ]; then
        Info "Checking out Wine-Staging version: ${STAGING_VERSION}"
        git fetch --all --tags
        git checkout "${STAGING_VERSION}" || Error "Failed to checkout Wine-Staging version ${STAGING_VERSION}"
    else
        Info "Using latest Wine-Staging version"
        git checkout master
        git pull origin master
    fi

    # Copy sources to build directory
    Info "Preparing build sources..."
    cp -r "${SOURCE_DIR}/${SOURCE_NAME}" "${BUILD_DIR}/wine"
    cp -r "${SOURCE_DIR}/wine-staging" "${BUILD_DIR}/wine-staging-${WINE_VERSION}"

    # Staging section
    [ "$USE_STAGING" = "true" ] && _staging_patcher

    cd "${BUILD_DIR}/wine"
    # Apply custom patches
    _custompatcher

    if [ "${DEBUG}" != "true" ]; then # let wine strip on install
        awk -i inplace '/STRIPPROG=/ { sub(/ %s/, " %s -s") }1' "${BUILD_DIR}/wine/tools/makedep.c"
        # shellcheck disable=SC2016
        sed -i 's|stripcmd=$stripprog|stripcmd="$stripprog -s"|g' "${BUILD_DIR}/wine/tools/install-sh"
    fi

    # Initialize git for make_makefiles
    git config commit.gpgsign false
    git config user.email "wine@build.dev"
    git config user.name "winebuild"
    git init
    git add --all
    git commit -m "makepkg"

    # Generate required files
    [ -e dlls/winevulkan/make_vulkan ] && {
    chmod +x dlls/winevulkan/make_vulkan
    dlls/winevulkan/make_vulkan
    }

    chmod +x tools/make_requests
    tools/make_requests
    [ -e tools/make_specfiles ] && {
        chmod +x tools/make_specfiles
        tools/make_specfiles
    }

    # Only ask for non-cachy/valve builds
    if [[ "$USE_CACHY" == "false" && "$USE_VALVE" == "false" ]]; then
        chmod +x tools/make_makefiles
        tools/make_makefiles
    fi

    autoreconf -fiv
    # Build and package
    build_wine
    package_wine

    Info "Build completed successfully!"
}

## Script options:
# Option 1: wow64 (empty/default = true)
# Option 2: fonts (empty/default = true)
# Option 3: debug (empty/default = false)
# Option 4: llvm-mingw (empty/default = false)

ORIGPATH="${PWD:-$(pwd)}"
_configuration "$@"

Info "Building Spritz-Wine:"
main "$@"
