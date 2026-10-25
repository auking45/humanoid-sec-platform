# syntax=docker/dockerfile:1
FROM ubuntu:22.04

LABEL maintainer="Antigravity Security Team"
LABEL description="Build and verification environment for NVIDIA Jetson L4T, OP-TEE, fTPM, and QEMU"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base dependencies, build toolchains, cross compilers, and utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    crossbuild-essential-arm64 \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    binutils-aarch64-linux-gnu \
    bison \
    flex \
    bc \
    libssl-dev \
    libelf-dev \
    device-tree-compiler \
    u-boot-tools \
    rsync \
    git \
    curl \
    wget \
    ca-certificates \
    ccache \
    pkg-config \
    libglib2.0-dev \
    libpixman-1-dev \
    # QEMU emulator & virtualization tools
    qemu-system-arm \
    qemu-system-misc \
    qemu-utils \
    # Security, TPM & HSM tools
    softhsm2 \
    opensc \
    gnutls-bin \
    libengine-pkcs11-openssl \
    pkcs11-provider \
    tpm2-tools \
    libtss2-dev \
    libtss2-tctildr0 \
    # Storage & Filesystem tools
    erofs-utils \
    cryptsetup-bin \
    e2fsprogs \
    cpio \
    dosfstools \
    mtools \
    # Python & Testing packages
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-setuptools \
    # Archive extractors
    bzip2 \
    lbzip2 \
    xz-utils \
    unzip \
    tar \
    # General developer tools
    sudo \
    gosu \
    bash-completion \
    nano \
    vim-tiny \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install modern Python testing and cryptographic packages
RUN pip3 install --no-cache-dir \
    pytest \
    pexpect \
    cryptography \
    pyopenssl \
    python-pkcs11

# Configure SoftHSM2 default directories and permissions
RUN mkdir -p /var/lib/softhsm/tokens /etc/softhsm \
    && echo "directories.tokendir = /var/lib/softhsm/tokens" > /etc/softhsm/softhsm2.conf \
    && chmod 777 /var/lib/softhsm/tokens

# Set environment variables for cross-compilation & ccache
ENV ARCH=arm64
ENV CROSS_COMPILE=aarch64-linux-gnu-
ENV CCACHE_DIR=/workspace/.cache/ccache
ENV SOFTHSM2_CONF=/etc/softhsm/softhsm2.conf
ENV PATH="/usr/lib/ccache:${PATH}"

# Workspace directory
WORKDIR /workspace

# Copy entrypoint script
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
