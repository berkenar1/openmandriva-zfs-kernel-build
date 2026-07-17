#!/usr/bin/env bash
set -euo pipefail

# 1. Configure ccache
ccache --max-size=5G
export PATH="/usr/lib64/ccache:$PATH"

# 2. Setup RPM build tree
rpmdev-setuptree
cp -rf SPECS/* ~/rpmbuild/SPECS/
cp -rf SOURCES/* ~/rpmbuild/SOURCES/

# 3. Download kernel source
cd ~/rpmbuild/SOURCES/
wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.tar.xz

# 4. Install spec build deps (system is already upgraded, so this is fast and clean)
dnf builddep -y ~/rpmbuild/SPECS/kernel.spec

# 5. GPG Setup
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    echo "Importing GPG Private Key..."
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import
    echo "%_signature gpg" > ~/.rpmmacros
    echo "%_gpg_name $GPG_KEY_ID" >> ~/.rpmmacros
    echo "%_gpg_path ~/.gnupg" >> ~/.rpmmacros
fi

# 6. Compile Kernel
export PATH="/usr/lib64/ccache:$PATH"
rpmbuild -bb ~/rpmbuild/SPECS/kernel.spec

# 7. Clone and Build ZFS
git clone --depth 1 https://github.com/openzfs/zfs.git ~/zfs-src
cd ~/zfs-src
./autogen.sh

DEVEL_RPM=$(find ~/rpmbuild/RPMS/ -name "kernel-desktop-devel-*.rpm" | head -n 1)
dnf install -y "$DEVEL_RPM"
KVER=$(rpm -qp --queryformat '%{VERSION}-%{RELEASE}.%ARCH\n' "$DEVEL_RPM" | tr -d '\n' || true)
if [ -z "$KVER" ]; then
    # Fallback to listing modules folder
    KVER=$(ls -1t /lib/modules/ | head -n 1)
fi

./configure --with-linux="/usr/src/linux-$KVER" --disable-pyzfs
make rpm-utils rpm-dkms

# 8. GPG Sign Packages
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    echo "Signing RPMs..."
    find ~/rpmbuild/RPMS/ ~/zfs-src/ -name "*.rpm" | xargs rpmsign --addsign
fi

# 9. Assemble Repo
cd /workspace
mkdir -p repo/x86_64
find ~/rpmbuild/RPMS/ ~/zfs-src/ -name "*.rpm" -exec cp {} repo/x86_64/ \;
cp repomd.xml.key repo/x86_64/ || true

# Create index
createrepo_c repo/x86_64/

# Sign metadata
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    echo "Signing repository metadata..."
    gpg --batch --yes --detach-sign --armor repo/x86_64/repodata/repomd.xml
fi

echo "Repository build completed successfully!"
