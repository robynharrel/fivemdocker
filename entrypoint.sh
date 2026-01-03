#!/bin/bash
cd /home/container

# Parse the startup command provided by Pterodactyl
MODIFIED_STARTUP=$(echo -e ${STARTUP} | sed -e 's/{{/${/g' -e 's/}}/}/g')
echo -e ":/home/container$ ${MODIFIED_STARTUP}"

# Set CPU environment variables from container environment
export QEMU_CPU="${QEMU_CPU:-host}"
export QEMU_CPU_FLAGS="${QEMU_CPU_FLAGS:-+popcnt,+sse4.2,+cx16,+lahf_lm}"

# Log CPU configuration
echo "=== CPU Configuration ==="
echo "QEMU_CPU: $QEMU_CPU"
echo "QEMU_CPU_FLAGS: $QEMU_CPU_FLAGS"
echo ""

# Check for required CPU features
echo "=== Checking CPU Features ==="
./check-cpu.sh 2>/dev/null || echo "CPU check script not found"

# Check if this is a FiveM server
if [[ "${MODIFIED_STARTUP}" == *"fivem"* ]] || [[ "${MODIFIED_STARTUP}" == *"FiveM"* ]] || [ -f "run.sh" ]; then
    echo "=== FiveM Server Detected ==="
    echo "Applying x86-64-v2 CPU bypass..."
    
    # Ensure CPU flags are set
    if ! grep -q popcnt /proc/cpuinfo 2>/dev/null; then
        echo "WARNING: POPCNT not detected in /proc/cpuinfo"
        echo "This may cause: 'The Cfx.re Platform Server requires support for x86-64-v2 instructions'"
        echo "Make sure Docker is running with: --privileged --device /dev/kvm"
    fi
    
    # Check for and set up FiveM
    if [ -f "run.sh" ]; then
        chmod +x run.sh alpine 2>/dev/null
        echo "FiveM found, ensuring proper permissions..."
    fi
fi

echo ""
echo "=== Starting Server ==="

# Run the server
exec env QEMU_CPU="${QEMU_CPU}" QEMU_CPU_FLAGS="${QEMU_CPU_FLAGS}" ${MODIFIED_STARTUP}
