# kind+flux project configuration
# Only override what's different from defaults
set DOMAIN "debian-lab"        # Domain name in libvirt
set MEMORY "4000"               # Memory in MB
set DISK_SIZE "20"              # Disk size in GB
#set DISK_ "/mnt/data/virt-images/alpine-3.21-virt-x86_64.qcow2"  # Alpine image

# Kind+Flux specific settings
set KUBERNETES_VERSION "1.28.0"    # Kubernetes version for Kind
set FLUX_VERSION "2.0.0"           # Flux version



# Custom project tasks
function project_task_post-create
    log_step "Post-create task: Setting up Kind and Flux"
    if not virsh_cmd domstate | grep -q running
        log_error "VM '$DOMAIN' is not running."
        return 1
    end

    # Get VM IP with error checking
    set -l ip (dom_ip)
    if test -z "$ip"; or not string match -qr '^\d+\.\d+\.\d+\.\d+$' "$ip"
        log_error "Could not get valid IP address for VM '$DOMAIN'."
        return 1
    end
    set -l command_args "kind create cluster && kubectl cluster-info && kubectl get nodes"
    log_cmd "ssh $SSH_USER@$ip $command_args"
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args
end
