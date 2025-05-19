#!/usr/bin/env fish

# Block some VM from the rebuild command
set NO_REBUILD "alpine-lab"

# Default settings - can be overridden by project params.fish
set CONNECT "qemu:///system"
set DOMAIN "debian-lab"
set SNAPSHOT "base"
set SSH_USER "root"
set SSH_KEY "~/.ssh/id_cluster"
set PROJECTS_DIR "./projects" # Define the projects directory
set CLOUD_INIT_DIR "./cloud-init" # Define the cloud-init directory
set VM_IMAGE "/mnt/data/virt-images/debian-12-genericcloud-amd64.qcow2"
set VM_MEMORY "6000"
set VM_DISK "20"
set SEED_ISO "/mnt/data/virt-images/seed.iso"

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

# Load project params if they exist
function load_project_params
    set -l project $argv[1]
    set project_params "$PROJECTS_DIR/$project/params.fish"
    if test -f $project_params
        source $project_params
    end
end

# Execute a project-specific task if defined in params.fish
function execute_project_command
    set -l command $argv[1]
    set -l project $argv[2]
    set -l command_args $argv[3..-1]

    if functions -q project_task_$command
        log_step "Executing project-specific custom command for $project: $command"

        # Make sure we're in the project directory
        set -l orig_dir (pwd)
        cd "$PROJECTS_DIR/$project"

        # Execute the function with arguments
        eval "project_task_$command $command_args"

        # Return to original directory
        cd $orig_dir
        return 0
    end

    return 1
end

# Function to show help information
function show_help
    set -l project $argv[1]
    echo "Usage:"
    echo "  lab.fish <command> [project] [args]         # For project tasks"
    echo ""

    if test -n "$project"
        echo "Project `$project` commands:"
    else
        echo "VM Management commands (pass project to operate against its targets):"
        echo "  rebuild      - Destroys and rebuilds the VM via cloud-init"
        echo "  reset        - Reverts the VM to the base snapshot"
        echo "  start        - Starts the VM and waits for SSH"
        echo "  ssh [cmd]    - SSH into the VM. Runs command if provided."
        echo "  stop         - Gracefully shuts down the VM"
        echo ""
        echo "Project commands (require project):"
    end
    echo "  deploy <project>      - Runs pyinfra deploy.py"
    echo "  debug <project>       - Runs pyinfra debug-inventory"
    echo "  task <project> <args> - Runs a specific pyinfra task by name"
    echo "  full <project>        - Runs reset, start, deploy on a project"

    if not test -n "$project"
        echo "Available projects in '$PROJECTS_DIR':"
        ls -d $PROJECTS_DIR/*/ 2>/dev/null | sed "s|$PROJECTS_DIR/||;s|/||"
    else
        load_project_params $project
        for func in (functions -a | grep -E "^project_task")
            set -l task_name (string replace "project_task_" "" $func)
            echo "  $task_name     -  Custom command"
        end
    end
end


# Main script execution
if test (count $argv) -lt 1
    # Show help right away
    show_help ""
    exit 0
else if test "$argv[1]" = "help"
    # Special case for help command
    if test (count $argv) -ge 2
        # Show help for specific project
        set -l project $argv[2]
        if test -d "$PROJECTS_DIR/$project"
            # Clean up any existing custom tasks
            for func in (functions -a | grep "^project_task_")
                functions -e $func
            end

            # Show help with the project
            show_help $project
        else
            log_error "Project '$project' not found in '$PROJECTS_DIR'."
            return 1
        end
    else
        # Show general help
        show_help ""
    end
else
    # Check for required dependencies
    set -l missing_deps
    for cmd in virsh nc uv ssh virt-install genisoimage
        if ! command -v $cmd > /dev/null 2>&1
            log_error "Error: Required command '$cmd' not found in PATH." > /dev/stderr
            set missing_deps yes
        end
    end

    if test -n "$missing_deps"
        log_error "Please install the missing dependencies and try again." > /dev/stderr
        exit 1
    end

    # Define all available commands
    set -l vm_commands rebuild reset start ssh stop
    set -l project_commands deploy debug task full
    set -l command $argv[1]

    # Handle VM management commands
    if contains $command $vm_commands
        # For VM-specific tasks, call the corresponding function directly
        set -l command_args $argv[2..-1]

        # Check if second argument is a project, and if so, load its params
        if test (count $argv) -ge 2; and test -d "$PROJECTS_DIR/$argv[2]"
            set command_args $argv[3..-1]
            load_project_params $argv[2]
        end

        switch "$command"
            case "rebuild"
                log_step "Preparing to rebuild VM..."
                # Check if the VM is in the NO_REBUILD list
                if contains $DOMAIN $NO_REBUILD
                    log_error "VM '$DOMAIN' is not allowed to be rebuilt."
                    return 1
                end

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

                # Check for optional parameters in command argument
                set -l console_mode false
                set -l wait false
                for arg in $command_args
                    if test "$arg" = "+console"
                        set console_mode true
                        log_info "Console mode enabled"
                        break
                    end
                    if test "$arg" = "+wait"
                        set wait true
                        log_info "Wait mode enabled"
                        break
                    end
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

                # Format command in a cleaner way for display
                set -l virt_opts
                set -a virt_opts "--connect $CONNECT"
                set -a virt_opts "--name $DOMAIN"
                set -a virt_opts "--memory $VM_MEMORY"
                set -a virt_opts "--os-variant name=debian13"
                set -a virt_opts "--nographics --import"
                set -a virt_opts "--disk=size=$VM_DISK,backing_store=$VM_IMAGE"
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
                # Not taking a snapshot if we do rebuild. kinda pointless.
                #log_step "Taking base snapshot..."
                #log_cmd "virsh snapshot-create-as $DOMAIN --name $SNAPSHOT"
                #virsh_cmd snapshot-create-as --name $SNAPSHOT --description "Base snapshot after fresh install"
                if test "$wait" = "true"
                    log_step "Waiting 10 seconds for stabilisation"
                    sleep 10
                end
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

                set -l ip (dom_ip)
                log_info "IP: $ip"
                echo -n "  Waiting for SSH..."
                while not check_host_up $ip 22
                    echo -n "."
                    sleep 0.5
                end
                log_success "VM is ready"
            case "stop"
                log_step "Stopping VM..."
                log_cmd "virsh shutdown $DOMAIN"
                virsh_cmd shutdown
            case "ssh"
                log_step "Connecting to VM via SSH..."

                # First check if VM exists and is running
                if not domain_exists
                    log_error "VM '$DOMAIN' does not exist."
                    return 1
                end

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

                log_cmd "ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args"
                ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args
        end
    # Handle project-related commands
    else if contains $command $project_commands
        # These commands require a project name
        if test (count $argv) -lt 2
            log_error "Command '$command' requires a project name"
            echo "Usage: lab.fish $command <project> [args]" >&2
            return 1
        end

        # Get project and arguments
        set -l project $argv[2]
        set -l command_args $argv[3..-1]

        # Validate project exists
        set -l project_path "$PROJECTS_DIR/$project"
        if not test -d "$project_path"
            log_error "Project '$project' not found in '$PROJECTS_DIR'."
            return 1
        end

        # Load project-specific parameters
        load_project_params $project

        # Check for VM IP if needed
        set -xg LAB_TARGET (dom_ip)
        if test -z "$LAB_TARGET"; or not string match -qr '^\d+\.\d+\.\d+\.\d+$' "$LAB_TARGET"
            log_error "Could not get valid IP address for VM '$DOMAIN'."
            return 1
        end

        # Change directory
        set -l orig_dir (pwd)
        set -x PYTHONPATH (realpath ".")
        cd $project_path
        # Otherwise use the built-in commands
        switch "$command"
            case "deploy"
                uv run pyinfra -y inventory.py deploy.py
            case "debug"
                uv run pyinfra -y inventory.py debug-inventory
            case "task"
                uv run pyinfra -y inventory.py $command_args
            # Full run
            case "full"
                # First reset the VM
                if domain_exists
                    log_step "Reverting to base snapshot..."
                    log_cmd "virsh snapshot-revert $SNAPSHOT"
                    virsh_cmd "snapshot-revert" $SNAPSHOT
                    log_success "VM reverted to base snapshot"
                end

                # Start the VM
                log_step "Starting VM..."
                log_cmd "virsh start $DOMAIN"
                virsh_cmd "start"
                echo -n "  Waiting for VM to start..."
                while not virsh_cmd domstate | grep -q running
                    echo -n "."
                    sleep 1
                end

                set -l ip (dom_ip)
                log_info "IP: $ip"
                echo -n "  Waiting for SSH..."
                while not check_host_up $ip 22
                    echo -n "."
                    sleep 0.5
                end
                log_success "VM is ready"

                # Deploy
                uv run pyinfra -y inventory.py deploy.py

                if test $status -eq 0
                    log_success "PyInfra deployment completed successfully"
                else
                    log_error "PyInfra deployment failed."
                    return 1
                end

                cd $orig_dir
                # Check if the project has any post-* custom tasks from params.fish
                for func in (functions -a | grep -E "^project_task_post")
                    set -l task_name (string replace "project_task_" "" $func)
                    execute_project_command $task_name $project
                end
            case "*"
                log_error "Unknown project command: $command"
                return 1
        end
        cd $orig_dir
    else
        # Handle project-specific tasks or unknown command
        # Get project and arguments
        set -l project $argv[2]
        set -l command_args $argv[3..-1]

        # Validate project exists
        set -l project_path "$PROJECTS_DIR/$project"
        if not test -d "$project_path"
            log_error "Project '$project' not found in '$PROJECTS_DIR'."
            return 1
        end

        # First check if this is a project-specific custom task defined in params.fish
        # Clear any existing custom task functions to avoid interference
        for func in (functions -a | grep "^project_task_")
            functions -e $func
        end

        # Load project params and look for custom tasks
        load_project_params $project

        if execute_project_command $command $project $command_args
            log_success "Ran command '$command'."
            return 0
        else
            # Not a recognized command
            log_error "Unknown command: $command"
            show_help ""
            return 1
        end
    end
end
