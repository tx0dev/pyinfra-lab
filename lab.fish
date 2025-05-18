#!/usr/bin/env fish

set CONNECT "qemu:///system"
set DOMAIN "debian-lab"
set SNAPSHOT "base"
set SSH_KEY "~/.ssh/id_cluster"
set PROJECTS_DIR "./projects" # Define the projects directory
set CLOUD_INIT_DIR "./cloud-init" # Define the cloud-init directory
set DISK_BASE "/mnt/data/virt-images/debian-12-genericcloud-amd64.qcow2"
set SEED_ISO "/mnt/data/virt-images/seed.iso"

# Colors for pretty output
# Fish has built-in color support via set_color, so we don't need these
# but keeping them as comments for reference
# set -g CLR_RESET (printf "\033[0m")
# set -g CLR_BOLD (printf "\033[1m")
# set -g CLR_DIM (printf "\033[2m")
# set -g CLR_BLUE (printf "\033[34m")
# set -g CLR_GREEN (printf "\033[32m")
# set -g CLR_YELLOW (printf "\033[33m")
# set -g CLR_RED (printf "\033[31m")

# Pretty output functions
function log_cmd
    set_color -d; echo "▶ $argv";
    set_color normal
end

function log_step
    set_color blue; echo "➜ $argv";
    set_color normal
end

function log_info
    set_color normal; echo "  $argv"
end

function log_success
    set_color green; echo "✓ $argv";
    set_color normal
end

function log_warn
    set_color yellow; echo "⚠ $argv";
    set_color normal
end

function log_error
    set_color red; echo "✗ $argv";
    set_color normal
end


# Wrapper for virsh cli
function virsh_cmd
    set -l cmd $argv[1]
    set -l args $argv[2..-1]
    virsh --connect $CONNECT $cmd --domain $DOMAIN $args
end

# Check if domain exists
function domain_exists
    virsh --connect $CONNECT dominfo $DOMAIN &>/dev/null
    return $status
end

# Check if a host is up, using a specific port
function check_host_up
    if nc -z -w 1 $argv[1] $argv[2] > /dev/null
        return 0
    else
        return 1
    end
end

# Get a domain IP address
function dom_ip
    if not virsh_cmd domstate | grep -q running
        echo "Can't fetch IP, Offline."
        return 1
    end
    set -l ip (virsh_cmd domifaddr | grep -oP '\d+\.\d+\.\d+\.\d+')
    if test -n "$ip"
        echo "$ip"
    else
        echo "Failed to fetch IP."
        return 1
    end
end

# Main runner
function project_task
    set -l project $argv[1]
    set -l task $argv[2]
    set -l task_args $argv[3..]

    # Handle "help" as a special case that doesn't require a project
    if test "$project" = "help"
        show_help ""
        return 0
    end

    # Show project-specific help if no task was provided
    if test -z "$task"
        show_help $project
        return 0
    end

    # For non-help tasks, validate the project exists
    if test "$task" != "help"
        set project_path "$PROJECTS_DIR/$project"
        if not test -d "$project_path"
            echo "Error: Project '$project' not found in '$PROJECTS_DIR'." > /dev/stderr
            return 1
        end
    end

    switch "$task"
        case "deploy"
            set -l orig_dir (pwd)
            set -x PYTHONPATH (realpath ".")
            cd $project_path
            uv run pyinfra -y ../../inventory.py deploy.py
            cd $orig_dir
        case "debug"
            uv run pyinfra -y inventory.py debug-inventory
        case "task"
            uv run pyinfra -y inventory.py $task_args
        # Full run
        case "full"
            project_task $project reset
            project_task $project start
            project_task $project deploy
            if test "$project" = "concourse"
                project_task $project fly-hello
            end
        # Project specific
        case "fly-hello"
            set -l ip (dom_ip)
            fly login -t lab -c "http://$ip:8080" -u test -p test
            fly -t lab set-pipeline -p hello-world -c $project_path/hello.yaml -n
            fly -t lab unpause-pipeline -p hello-world
            fly -t lab trigger-job --job hello-world/hello-world-job --watch

        case "help"
            show_help $project
        case "*"
            echo "Unknown task: $task"
            return 1
    end
end

# Function to show help information
function show_help
    set -l project $argv[1]
    echo "Usage:"
    echo "  lab.fish <vm-task> [args]             # For VM management"
    echo "  lab.fish <project> <project-task> [args]  # For project tasks"
    echo ""

    echo "VM Management Tasks (no project required):"
    echo "  rebuild      - Destroys and rebuilds the VM via cloud-init"
    echo "  reset        - Reverts the VM to the base snapshot"
    echo "  start        - Starts the VM and waits for SSH"
    echo "  ssh [cmd]    - SSH into the VM. Runs command if provided."
    echo ""

    if not test -n "$project"
        echo "Available projects in '$PROJECTS_DIR':"
        ls -d $PROJECTS_DIR/*/ 2>/dev/null | sed "s|$PROJECTS_DIR/||;s|/||"
    end
    if test -n "$project"
        echo "Project specific tasks:"
        switch "$project"
            case "concourse"
                echo "  fly-hello    - Sets up and triggers the hello-world pipeline"
        end
        echo ""
    end
    echo "Project Tasks (require project name):"
    echo "  deploy       - Runs pyinfra deploy.py"
    echo "  debug        - Runs pyinfra debug-inventory"
    echo "  task <name>  - Runs a specific pyinfra task by name"
    echo "  full         - Runs reset, start, deploy, and fly-hello"
    echo "  help         - Show this help message"
end

if test (count $argv) -lt 1
    show_help ""
else
    # Check for required dependencies
    set -l missing_deps
    for cmd in virsh nc uv ssh virt-install
        if ! command -v $cmd > /dev/null 2>&1
            echo "Error: Required command '$cmd' not found in PATH." > /dev/stderr
            set missing_deps yes
        end
    end

    if test -n "$missing_deps"
        echo "Please install the missing dependencies and try again." > /dev/stderr
        exit 1
    end

    # Handle VM management commands directly without requiring a project
    set -l vm_tasks rebuild reset start ssh
    set -l arg1 $argv[1]

    if contains $arg1 $vm_tasks
        # For VM-specific tasks, call the corresponding function directly
        set -l task $arg1
        set -l task_args $argv[2..-1]

        switch "$task"
            case "rebuild"
                log_step "Preparing to rebuild VM..."

                # Check for required cloud-init files
                set -l required_files "$CLOUD_INIT_DIR/user-data" "$CLOUD_INIT_DIR/meta-data" "$CLOUD_INIT_DIR/network-config"
                set -l missing_files
                for file in $required_files
                    if not test -f "$file"
                        set missing_files $missing_files $file
                    end
                end

                if test -n "$missing_files"
                    log_error "Required cloud-init files not found:" > /dev/stderr
                    for file in $missing_files
                        echo "  - $file" > /dev/stderr
                    end
                    log_error "Please create these files in '$CLOUD_INIT_DIR' before rebuilding." > /dev/stderr
                    return 1
                end

                log_step "Checking for existing VM..."
                if domain_exists
                    log_info "Domain $DOMAIN exists"

                    # First try to shut down gracefully if running
                    if virsh_cmd domstate | grep -q running
                        log_step "Shutting down the VM..."
                        log_cmd "virsh shutdown $DOMAIN"
                        virsh_cmd shutdown
                        echo -n "  Waiting for VM to shut down..."
                        set -l shutdown_timeout 30
                        for i in (seq $shutdown_timeout)
                            if not virsh_cmd domstate | grep -q running
                                break
                            end
                            echo -n "."
                            sleep 1
                        end

                        # Force destroy if graceful shutdown takes too long
                        if virsh_cmd domstate | grep -q running
                            echo " timeout after $shutdown_timeout seconds"
                            log_warn "Forcing VM destruction"
                            log_cmd "virsh destroy $DOMAIN"
                            virsh_cmd destroy
                            # Verify destroy worked
                            if virsh_cmd domstate | grep -q running
                                log_error "Failed to destroy VM, cannot continue"
                                return 1
                            end
                        else
                            echo " done"
                        end
                    else
                        log_info "VM is already powered off"
                    end

                    # Get list of all snapshots
                    log_step "Checking for snapshots..."
                    set -l snapshots (virsh --connect $CONNECT snapshot-list --domain $DOMAIN --name 2>/dev/null)

                    # Delete all snapshots if they exist
                    if test $status -eq 0 -a -n "$snapshots"
                        log_info "Found snapshots, removing them all..."
                        for snap in $snapshots
                            if test -n "$snap"
                                log_info "Deleting snapshot: $snap"
                                log_cmd "virsh snapshot-delete $DOMAIN $snap"
                                if not virsh_cmd snapshot-delete $snap
                                    log_warn "Failed to delete snapshot '$snap', continuing anyway"
                                end
                            end
                        end
                    else
                        log_info "No snapshots found"
                    end

                    # Undefine the domain
                    log_step "Removing the VM definition..."
                    log_cmd "virsh undefine $DOMAIN --remove-all-storage"
                    if not virsh_cmd undefine --remove-all-storage
                        log_warn "Failed with --remove-all-storage, trying alternative methods"

                        # Try simple undefine
                        log_cmd "virsh undefine $DOMAIN"
                        if not virsh_cmd undefine
                            log_error "Failed to undefine domain, VM may be in an inconsistent state"
                            # Continue anyway since we'll attempt to recreate
                        end
                    end

                    # Verify domain was removed
                    if domain_exists
                        log_error "Domain still exists after undefine attempts"
                        log_warn "Continuing anyway, but VM recreation may fail"
                    else
                        log_success "Domain successfully removed"
                    end
                else
                    log_info "Domain $DOMAIN doesn't exist, nothing to clean up"
                end

                log_step "Creating new VM with cloud-init..."
                log_cmd "genisoimage -output $SEED_ISO -volid cidata ..."
                genisoimage -output $SEED_ISO -volid cidata -joliet -rock $CLOUD_INIT_DIR/user-data $CLOUD_INIT_DIR/meta-data

                # Check if +console was passed as an argument
                set -l console_mode false
                for arg in $task_args
                    if test "$arg" = "+console"
                        set console_mode true
                        log_info "Console mode enabled"
                        break
                    end
                end

                # Format command in a cleaner way for display
                set -l virt_opts
                set -a virt_opts "--connect $CONNECT"
                set -a virt_opts "--name $DOMAIN"
                set -a virt_opts "--memory 6000"
                set -a virt_opts "--os-variant name=debian13"
                set -a virt_opts "--nographics --import"
                set -a virt_opts "--disk=size=20,backing_store=$DISK_BASE"
                set -a virt_opts "--disk=path=$SEED_ISO,readonly=yes"
                set -a virt_opts "--console pty,target_type=serial"

                # Only add --noautoconsole if we're not attaching to console
                if test "$console_mode" = "false"
                    set -a virt_opts "--noautoconsole"
                end

                # Create a clean display version of the command
                set -l cmd_display "virt-install"
                for opt in $virt_opts
                    set cmd_display "$cmd_display $opt"
                end
                log_cmd $cmd_display

                # Execute the command
                eval virt-install $virt_opts

                log_step "Waiting for VM to come online..."
                while not virsh_cmd domstate | grep -q running
                    sleep 1
                end

                echo -n "  Waiting for VM IP..."
                set -l ip ""
                for i in (seq 30)
                    set ip (dom_ip)
                    if test -n "$ip" -a "$ip" != "Failed to fetch IP." -a "$ip" != "Can't fetch IP, Offline."
                        echo " found: $ip"
                        break
                    end
                    echo -n "."
                    sleep 2
                end

                if test -z "$ip" -o "$ip" = "Failed to fetch IP." -o "$ip" = "Can't fetch IP, Offline."
                    echo ""
                    log_error "Could not obtain VM IP address after 60 seconds." > /dev/stderr
                    return 1
                end
                echo -n "  Waiting for SSH..."
                while not check_host_up $ip 22
                    echo -n .
                    sleep 0.5
                end

                log_step "Taking base snapshot..."
                log_cmd "virsh snapshot-create-as $DOMAIN --name $SNAPSHOT"
                virsh_cmd snapshot-create-as --name $SNAPSHOT --description "Base snapshot after fresh install"
                log_success "VM has been rebuilt successfully!"
            case "reset"
                log_step "Reverting to base snapshot..."
                log_cmd "virsh snapshot-revert $DOMAIN $SNAPSHOT"
                virsh_cmd "snapshot-revert" $SNAPSHOT
                log_success "VM reverted to base snapshot"
            case "start"
                log_step "Starting VM..."
                log_cmd "virsh start $DOMAIN"
                virsh_cmd "start"
                echo -n "  Waiting for VM to start..."
                while not virsh_cmd domstate | grep -q running
                    echo -n "."
                    sleep 1
                end
                echo " running"

                set -l ip (dom_ip)
                log_info "IP: $ip"
                echo -n "  Waiting for SSH..."
                while not check_host_up $ip 22
                    echo -n "."
                    sleep 0.5
                end
                echo " up"
                log_success "VM is ready"
            case "ssh"
                log_step "Connecting to VM via SSH..."
                set -l ip (dom_ip)
                log_cmd "ssh -i $SSH_KEY root@$ip $task_args"
                ssh -i $SSH_KEY -o StrictHostKeyChecking=no root@$ip $task_args
        end
    else
        # Split arguments handling based on count
        set -l arg_count (count $argv)

        if test $arg_count -eq 1
            show_help $argv[1]
        else
            # Otherwise pass all arguments to project_task as normal
            project_task $argv
        end
    end
end
