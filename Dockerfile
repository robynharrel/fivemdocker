FROM --platform=$TARGETOS/$TARGETARCH debian:bookworm-slim

LABEL author="Michael Parker" maintainer="parker@pterodactyl.io"
LABEL org.opencontainers.image.source="https://github.com/darksaid98/yolks"
LABEL org.opencontainers.image.licenses=MIT

ENV DEBIAN_FRONTEND noninteractive

# Environment variables for CPU bypass
ENV QEMU_CPU=host
ENV QEMU_CPU_FLAGS="+popcnt,+sse4.2,+cx16,+lahf_lm,+sse4a,+abm,+aes,+avx,+avx2,+bmi1,+bmi2,+fma,+f16c,+rdrand,+xsave,+xsaveopt"

# Create container user
RUN useradd -m -d /home/container -s /bin/bash container
RUN ln -s /home/container/ /nonexistent
ENV USER=container HOME=/home/container

## Update base packages
RUN apt update && apt upgrade -y

## Install dependencies including KVM/QEMU tools
RUN apt install -y \
    gcc g++ libgcc-12-dev libc++-dev gdb libc6 git git-lfs wget curl tar zip unzip binutils xz-utils \
    liblzo2-2 cabextract iproute2 net-tools netcat-traditional telnet libatomic1 libsdl1.2debian libsdl2-2.0-0 \
    libfontconfig1 icu-devtools libunwind8 libssl-dev sqlite3 libsqlite3-dev libmariadb-dev-compat libduktape207 \
    locales ffmpeg gnupg2 apt-transport-https software-properties-common ca-certificates liblua5.3-0 libz3-dev \
    libzadc4 rapidjson-dev tzdata libevent-dev libzip4 libprotobuf32 libfluidsynth3 procps libstdc++6 tini jq \
    file qemu-system-x86 qemu-user-static qemu-utils libvirt-clients libvirt-daemon-system cpu-checker virtinst \
    bridge-utils kmod

## Install additional CPU utilities
RUN apt install -y cpuid dmidecode hwloc numactl

## Configure Git Lfs
RUN git lfs install

## Configure locale
RUN update-locale lang=en_US.UTF-8 && dpkg-reconfigure --frontend noninteractive locales

# Temp fix for libicu66.1 for RAGE-MP and libssl1.1 for fivem and many more
# Add KVM/QEMU CPU configuration
RUN if [ "$(uname -m)" = "x86_64" ]; then \
        # Install CPU microcode updates
        apt install -y intel-microcode amd64-microcode; \
        \
        # Install legacy libs
        wget http://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu66_66.1-2ubuntu2.1_amd64.deb && \
        wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.0g-2ubuntu4_amd64.deb && \
        dpkg -i libicu66_66.1-2ubuntu2.1_amd64.deb && \
        dpkg -i libssl1.1_1.1.0g-2ubuntu4_amd64.deb && \
        rm libicu66_66.1-2ubuntu2.1_amd64.deb libssl1.1_1.1.0g-2ubuntu4_amd64.deb; \
        \
        # Create QEMU CPU configuration
        mkdir -p /etc/qemu && \
        echo 'allow all' > /etc/qemu/bridge.conf && \
        echo '#!/bin/bash' > /usr/local/bin/fix-cpu.sh && \
        echo 'export QEMU_CPU="host"' >> /usr/local/bin/fix-cpu.sh && \
        echo 'export QEMU_CPU_FLAGS="+popcnt,+sse4.2,+cx16,+lahf_lm,+sse4a,+abm,+aes,+avx,+avx2,+bmi1,+bmi2,+fma,+f16c"' >> /usr/local/bin/fix-cpu.sh && \
        echo 'echo "Forcing CPU: \$QEMU_CPU"' >> /usr/local/bin/fix-cpu.sh && \
        echo 'echo "CPU Flags: \$QEMU_CPU_FLAGS"' >> /usr/local/bin/fix-cpu.sh && \
        chmod +x /usr/local/bin/fix-cpu.sh; \
    fi

# ARM64 specific fixes
RUN if [ ! "$(uname -m)" = "x86_64" ]; then \
        wget http://ports.ubuntu.com/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_arm64.deb && \
        dpkg -i libssl1.1_1.1.1f-1ubuntu2_arm64.deb && \
        rm libssl1.1_1.1.1f-1ubuntu2_arm64.deb; \
    fi

WORKDIR /home/container

# Create CPU verification script
RUN cat > /home/container/check-cpu.sh << 'EOF'
#!/bin/bash
echo "=== CPU Information ==="
echo "Host Architecture: $(uname -m)"
echo "CPU Model: $(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "CPU Cores: $(nproc)"
echo ""
echo "=== CPU Flags ==="
grep flags /proc/cpuinfo | head -1 | tr ' ' '\n' | grep -v "^$" | sort
echo ""
echo "=== Checking x86-64-v2 Instructions ==="
if grep -q popcnt /proc/cpuinfo; then
    echo "✓ POPCNT: Supported"
else
    echo "✗ POPCNT: NOT Supported"
fi
if grep -q sse4_2 /proc/cpuinfo; then
    echo "✓ SSE4.2: Supported"
else
    echo "✗ SSE4.2: NOT Supported"
fi
if grep -q cx16 /proc/cpuinfo; then
    echo "✓ CMPXCHG16B: Supported"
else
    echo "✗ CMPXCHG16B: NOT Supported"
fi
if grep -q lahf_lm /proc/cpuinfo; then
    echo "✓ LAHF/SAHF: Supported"
else
    echo "✗ LAHF/SAHF: NOT Supported"
fi
echo ""
echo "=== QEMU Environment ==="
echo "QEMU_CPU: ${QEMU_CPU:-not set}"
echo "QEMU_CPU_FLAGS: ${QEMU_CPU_FLAGS:-not set}"
EOF
RUN chmod +x /home/container/check-cpu.sh

# Create FiveM specific startup script
RUN cat > /home/container/start-fivem.sh << 'EOF'
#!/bin/bash

# Force CPU configuration for FiveM
export QEMU_CPU="${QEMU_CPU:-host}"
export QEMU_CPU_FLAGS="${QEMU_CPU_FLAGS:-+popcnt,+sse4.2,+cx16,+lahf_lm,+sse4a,+abm,+aes,+avx,+avx2}"

echo "=========================================="
echo "FiveM Server Startup"
echo "=========================================="
echo "CPU Configuration:"
echo "  QEMU_CPU: $QEMU_CPU"
echo "  QEMU_CPU_FLAGS: $QEMU_CPU_FLAGS"
echo ""

# Run CPU check
./check-cpu.sh

echo ""
echo "If you see 'NOT Supported' for any x86-64-v2 instructions,"
echo "you need to run Docker with these flags:"
echo "  --privileged --device /dev/kvm --env QEMU_CPU=host"
echo ""
echo "=========================================="
echo "Starting FiveM..."
echo "=========================================="

# Check if FiveM files exist
if [ -f "run.sh" ]; then
    # Set proper permissions
    chmod +x run.sh alpine 2>/dev/null || true
    
    # Check for server.cfg
    if [ ! -f "server.cfg" ]; then
        echo "Creating default server.cfg..."
        cat > server.cfg << 'CFGEOF'
endpoint_add_tcp "0.0.0.0:30120"
endpoint_add_udp "0.0.0.0:30120"
sv_hostname "Docker FiveM Server"
sv_maxclients 32
# sv_licenseKey "YOUR_LICENSE_KEY"
ensure mapmanager
ensure chat
ensure spawnmanager
ensure sessionmanager
ensure basic-gamemode
ensure hardcap
ensure rconlog
CFGEOF
    fi
    
    # Start FiveM
    exec ./run.sh +exec server.cfg
else
    echo "ERROR: FiveM not found!"
    echo ""
    echo "To setup FiveM:"
    echo "1. Download fx.tar.xz from:"
    echo "   https://runtime.fivem.net/artifacts/fivem/build_proot_linux/master/"
    echo "2. Extract: tar xf fx.tar.xz"
    echo "3. Restart the container"
    echo ""
    echo "Sleeping for manual intervention..."
    sleep infinity
fi
EOF
RUN chmod +x /home/container/start-fivem.sh

STOPSIGNAL SIGINT

COPY --chown=container:container ./entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Modify entrypoint to handle CPU configuration
RUN cat >> /entrypoint.sh << 'EOF'

# CPU fix injection
if [ -n "$QEMU_CPU" ]; then
    echo "Applying CPU configuration: $QEMU_CPU"
    export QEMU_CPU
fi
if [ -n "$QEMU_CPU_FLAGS" ]; then
    echo "Applying CPU flags: $QEMU_CPU_FLAGS"
    export QEMU_CPU_FLAGS
fi

# Check for KVM
if [ -e /dev/kvm ]; then
    echo "KVM device found: /dev/kvm"
    chmod 666 /dev/kvm 2>/dev/null || true
else
    echo "WARNING: /dev/kvm not found. CPU acceleration may be limited."
    echo "Run Docker with: --device /dev/kvm"
fi

# Check CPU capabilities
if [ -x "$(command -v cpuid)" ]; then
    echo "Checking CPU features with cpuid..."
    cpuid | grep -i "popcnt\|sse4\|avx\|aes" | head -10
fi

# For FiveM specifically
if [ -f "/home/container/start-fivem.sh" ] && [ -f "/home/container/run.sh" ]; then
    echo "Starting FiveM with CPU bypass..."
    exec /home/container/start-fivem.sh
fi
EOF

ENTRYPOINT ["/usr/bin/tini", "-g", "--"]
CMD ["/entrypoint.sh"]
