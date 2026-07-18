FROM openmandriva/cooker:latest

# 1. Optimize DNF configuration
RUN mkdir -p /etc/dnf && \
    echo "max_parallel_downloads=10" >> /etc/dnf/dnf.conf && \
    echo "fastestmirror=1" >> /etc/dnf/dnf.conf

# 2. Upgrade the entire base system first
RUN dnf clean all && dnf upgrade -y --refresh

# 3. Install build dependencies
RUN dnf install -y \
  git dkms rpm-build rpmdevtools createrepo_c dnf-plugins-core \
  gcc clang make autogen autoconf automake libtool slibtool \
  lib64uuid-devel lib64blkid-devel lib64z-devel lib64tirpc-devel \
  lib64openssl-devel lib64udev-devel lib64lz4-devel lib64zstd-devel \
  lib64elfutils-devel lib64aio-devel lib64attr-devel lib64ffi-devel \
  lib64atomic-devel python3-devel wget pinentry ccache gnupg2

# 4. Workaround for GCC 16 packaging bug on OpenMandriva Cooker:
# Create a dummy libatomic_asneeded.so linker script to satisfy compiler requirements
RUN echo "INPUT ( AS_NEEDED ( /usr/lib64/libatomic.so.1 ) )" > /usr/lib64/libatomic_asneeded.so
