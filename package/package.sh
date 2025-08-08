#!/bin/bash

CURRENT_DIR=$(dirname $(readlink -f $0))
ROOT_DIR=$(cd ${CURRENT_DIR}/.. && pwd)
BUILD_DIR="${ROOT_DIR}/build"
APP_DIR=${CURRENT_DIR}/c2-browser.AppDir

# Check if c2-browser directory exists, otherwise use default values
if [ -f "${ROOT_DIR}/c2-browser/chromium_version.txt" ]; then
    chromium_version=$(cat ${ROOT_DIR}/c2-browser/chromium_version.txt)
else
    chromium_version="130.0.6723.116"
fi

if [ -f "${ROOT_DIR}/c2-browser/revision.txt" ]; then
    browser_revision=$(cat ${ROOT_DIR}/c2-browser/revision.txt)
else
    browser_revision="1"
fi

APP_NAME="c2-browser"
VERSION="${chromium_version}-${browser_revision}"
ARCH="x86_64"
FILE_PREFIX=$APP_NAME-$VERSION-$ARCH

### create tar.xz package
FILES="chrome
chrome_100_percent.pak
chrome_200_percent.pak
chrome_crashpad_handler
chromedriver
chrome_sandbox
chrome-wrapper
icudtl.dat
libEGL.so
libGLESv2.so
libqt5_shim.so
libqt6_shim.so
libvk_swiftshader.so
libvulkan.so.1
locales/
product_logo_48.png
resources.pak
v8_context_snapshot.bin
vk_swiftshader_icd.json
xdg-mime
xdg-settings"

echo "copying release files and create compressed archive ${FILE_PREFIX}_linux.tar.xz"
mkdir -p ${CURRENT_DIR}/${FILE_PREFIX}_linux
for i in $FILES ; do
    cp -r ${BUILD_DIR}/src/out/Default/$i ${CURRENT_DIR}/${FILE_PREFIX}_linux
done
SIZE="$(du -sk "${FILE_PREFIX}_linux" | cut -f1)"
# Use pv if available, otherwise use plain tar
if command -v pv >/dev/null 2>&1; then
    tar cf - ${FILE_PREFIX}_linux | pv -s"${SIZE}k" | xz > ${FILE_PREFIX}_linux.tar.xz
else
    echo "Creating archive (this may take a while)..."
    tar czf ${FILE_PREFIX}_linux.tar.xz ${FILE_PREFIX}_linux
fi

## create AppImage using appimagetool
rm -rf ${APP_DIR} && mkdir -p ${APP_DIR}/opt/c2-browser/ ${APP_DIR}/usr/share/icons/hicolor/48x48/apps/
mv ${CURRENT_DIR}/${FILE_PREFIX}_linux/* ${APP_DIR}/opt/c2-browser/
cp ${CURRENT_DIR}/c2-browser.desktop ${APP_DIR}
sed -i -e 's|Exec=c2-browser|Exec=AppRun|g' ${APP_DIR}/c2-browser.desktop

cat > ${APP_DIR}/AppRun <<'EOF'
#!/bin/sh
THIS="$(readlink -f "${0}")"
HERE="$(dirname "${THIS}")"
export LD_LIBRARY_PATH="${HERE}"/usr/lib:$PATH
export CHROME_WRAPPER="${THIS}"
"${HERE}"/opt/c2-browser/chrome "$@"
EOF
chmod a+x ${APP_DIR}/AppRun

cp ${APP_DIR}/opt/c2-browser/product_logo_48.png ${APP_DIR}/usr/share/icons/hicolor/48x48/apps/c2-browser.png
cp ${APP_DIR}/usr/share/icons/hicolor/48x48/apps/c2-browser.png ${APP_DIR}
# download appimagetool if not in PATH or locally present
if ! command -v appimagetool >/dev/null; then
    if [ ! -f ./appimagetool ] ; then
        URL=$(curl -s https://api.github.com/repos/AppImage/appimagetool/releases/latest | jq '.assets[].browser_download_url' | grep x86_64 | sed 's/"//g')
        wget -q --show-progress -O appimagetool $URL && chmod +x appimagetool
    fi
    export PATH=".:$PATH"
fi
# Use appimagetool with --appimage-extract-and-run if running in Docker without FUSE
if [ -f /.dockerenv ]; then
    /usr/local/bin/appimagetool --appimage-extract-and-run -u 'gh-releases-zsync|c2-software|c2-browser-portablelinux|latest|c2-browser-*.AppImage.zsync' ${APP_DIR} ${CURRENT_DIR}/${FILE_PREFIX}.AppImage
else
    APPIMAGETOOL_APP_NAME=$APP_NAME ARCH=$ARCH VERSION=$VERSION appimagetool -u 'gh-releases-zsync|c2-software|c2-browser-portablelinux|latest|c2-browser-*.AppImage.zsync' ${APP_DIR} ${CURRENT_DIR}/${FILE_PREFIX}.AppImage
fi
rm -rf ${CURRENT_DIR}/${FILE_PREFIX}_linux/ ${APP_DIR}

### mv results to root dir if they exist
if [ -f "${CURRENT_DIR}/${FILE_PREFIX}_linux.tar.xz" ]; then
    mv ${CURRENT_DIR}/${FILE_PREFIX}_linux.tar.xz "${ROOT_DIR}"
fi
if [ -f "${CURRENT_DIR}/${FILE_PREFIX}.AppImage" ]; then
    mv ${CURRENT_DIR}/${FILE_PREFIX}.AppImage "${ROOT_DIR}"
fi
if [ -f "${CURRENT_DIR}/${FILE_PREFIX}.AppImage.zsync" ]; then
    mv ${CURRENT_DIR}/${FILE_PREFIX}.AppImage.zsync "${ROOT_DIR}"
fi
