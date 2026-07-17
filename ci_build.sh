#!/usr/bin/env bash
set -euo pipefail

# 1. Install system dependencies
dnf clean all
dnf install -y \
  git dkms rpm-build rpmdevtools createrepo_c dnf-plugins-core \
  gcc clang make autogen autoconf automake libtool \
  lib64uuid-devel lib64blkid-devel lib64z-devel lib64tirpc-devel \
  lib64openssl-devel lib64udev-devel lib64lz4-devel lib64zstd-devel \
  lib64elfutils-devel lib64aio-devel lib64attr-devel lib64ffi-devel \
  python3-devel wget pinentry ccache gnupg2

# 2. Configure ccache
ccache --max-size=5G
export PATH="/usr/lib64/ccache:$PATH"

# 3. Setup RPM build tree
rpmdev-setuptree
cp -rf SPECS/* ~/rpmbuild/SPECS/
cp -rf SOURCES/* ~/rpmbuild/SOURCES/

# 4. Download kernel source
cd ~/rpmbuild/SOURCES/
wget -q https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.0.tar.xz

# 5. Install spec build deps
dnf builddep -y ~/rpmbuild/SPECS/kernel.spec

# 6. GPG Setup
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    echo "Importing GPG Private Key..."
    echo "$GPG_PRIVATE_KEY" | gpg --batch --import
    echo "%_signature gpg" > ~/.rpmmacros
    echo "%_gpg_name $GPG_KEY_ID" >> ~/.rpmmacros
    echo "%_gpg_path ~/.gnupg" >> ~/.rpmmacros
fi

# 7. Compile Kernel
export PATH="/usr/lib64/ccache:$PATH"
rpmbuild -bb ~/rpmbuild/SPECS/kernel.spec

# 8. Clone and Build ZFS
git clone --depth 1 https://github.com/openzfs/zfs.git ~/zfs-src
cd ~/zfs-src
./autogen.sh

DEVEL_RPM=$(find ~/rpmbuild/RPMS/ -name "kernel-desktop-devel-*.rpm" | head -n 1)
dnf install -y "$DEVEL_RPM"
KVER=$(rpm -qp --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' "$DEVEL_RPM" | tr -d '\n')

./configure --with-linux="/usr/src/linux-$KVER" --disable-pyzfs
make rpm-utils rpm-dkms

# 9. GPG Sign Packages
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
    echo "Signing RPMs..."
    find ~/rpmbuild/RPMS/ ~/zfs-src/ -name "*.rpm" | xargs rpmsign --addsign
fi

# 10. Assemble Repo
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
