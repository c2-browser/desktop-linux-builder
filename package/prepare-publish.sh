#!/bin/bash
WORKSPACE_DIR="$HOME/workspace"

BUILD_REPO=ungoogled-software/ungoogled-chromium-portablelinux
PUBLISH_REPO=c2-browser/desktop

# adjust the paths for your file system
PATH_TO_BUILD_REPO="${WORKSPACE_DIR}/${BUILD_REPO}"
PATH_TO_PUBLISH_REPO="${WORKSPACE_DIR}/${PUBLISH_REPO}"

set -eux
REPO_TAG="$(cd ${PATH_TO_BUILD_REPO} && git describe --tags --abbrev=0)"
TAG="${REPO_TAG%.1}"

cd ${PATH_TO_PUBLISH_REPO}
# forced reset to upstream repo
#git checkout master && git pull --rebase
#git fetch upstream
#git reset --hard upstream/master
#git push origin master --force

# use conveninence scripts in c2-browser-binaries repo to produce commits for new binaries
./utilities/submit_github_binary.py --skip-checks --skip-commit --tag ${TAG} --username gxanshu --output config/platforms/linux_portable/64bit/ ${PATH_TO_BUILD_REPO}/c2-browser-${TAG}*.tar.xz
sed -i "s|${PUBLISH_REPO}|${BUILD_REPO}|" ${PATH_TO_PUBLISH_REPO}/config/platforms/linux_portable/64bit/${TAG}.ini

./utilities/submit_github_binary.py --skip-checks --skip-commit --tag ${TAG} --username gxanshu --output config/platforms/appimage/64bit/ ${PATH_TO_BUILD_REPO}/c2-browser-${TAG}*.AppImage
sed -i "s|${PUBLISH_REPO}|${BUILD_REPO}|" ${PATH_TO_PUBLISH_REPO}/config/platforms/appimage/64bit/${TAG}.ini
