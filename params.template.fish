# Project parameters template (copy to your project directory as params.fish)

# VM Configuration
set DOMAIN "myproject-lab"          # VM name in libvirt
#set DISK_BASE "/mnt/data/virt-images/debian-12-genericcloud-amd64.qcow2"  # Base image
#set VM_MEMORY "6000"                # Memory in MB
#set VM_DISK "20"                    # Disk size in GB

# Project-specific settings (examples)
# set MY_PORT "8080"
# set MY_USER "test"
# set MY_SECRET "secret123"

# Custom project tasks
# Define functions starting with 'project_task_' to create custom tasks
# These can be executed with: lab.fish <project> <task-name>

# Example: Custom status task
function project_task_status
    # Get VM IP
    set -l ip (dom_ip)
    log_info "Checking service status at $ip"

    # Execute commands on the VM
    ssh -i $SSH_KEY root@$ip "systemctl status nginx"
end
