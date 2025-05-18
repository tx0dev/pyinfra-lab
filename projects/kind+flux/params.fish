# kind+flux project configuration
# Only override what's different from defaults
set DOMAIN "debian-lab"        # Domain name in libvirt
set MEMORY "4000"               # Memory in MB
set DISK_SIZE "20"              # Disk size in GB
#set DISK_ "/mnt/data/virt-images/alpine-3.21-virt-x86_64.qcow2"  # Alpine image

# Kind+Flux specific settings
set KUBERNETES_VERSION "1.28.0"    # Kubernetes version for Kind
set FLUX_VERSION "2.0.0"           # Flux version
