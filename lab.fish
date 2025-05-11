#!/usr/bin/env fish

set CONNECT "qemu:///system"
set DOMAIN "alpine-lab"
set SNAPSHOT "base"
set SSH_KEY "~/.ssh/id_cluster"
set PROJECTS_DIR "./projects" # Define the projects directory

# Wrapper for virsh cli
function virsh_cmd
    set -l cmd $argv[1]
    set -l args $argv[2]
    virsh --connect $CONNECT $cmd --domain $DOMAIN $args
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
function run_task
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
        # VM tasks
        case "reset"
            virsh_cmd "snapshot-revert" $SNAPSHOT
        case "start"
            virsh_cmd "start"
            while not virsh_cmd domstate | grep -q running
                sleep 1
            end
            set -l ip (dom_ip)
            echo IP: $ip
            echo -n "Waiting for SSH..."
            while not check_host_up $ip 22
                echo -n .
                sleep 0.5
            end
            echo " up"
        case "ssh"
            set -l ip (dom_ip)
            ssh -i $SSH_KEY root@$ip $task_args
        # PyInfra Deploy
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
            run_task $project reset
            run_task $project start
            run_task $project deploy
            if test "$project" = "concourse"
                run_task $project fly-hello
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
    echo "Usage: lab.fish <project> <task> [args]"
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
    echo "Available tasks:"
    echo "  deploy       - Runs pyinfra deploy.py"
    echo "  debug        - Runs pyinfra debug-inventory"
    echo "  task <name>  - Runs a specific pyinfra task by name"
    echo "  ssh [cmd]    - SSH into the VM. Runs command if provided."
    echo "  reset        - Reverts the VM to the base snapshot"
    echo "  start        - Starts the VM and waits for SSH"
    echo "  full         - Runs reset, start, deploy, and fly-hello"
    echo "  help         - Show this help message"
end

if test (count $argv) -lt 1
    show_help ""
else
    # Check for required dependencies
    set -l missing_deps
    for cmd in virsh nc uv ssh
        if ! command -v $cmd > /dev/null 2>&1
            echo "Error: Required command '$cmd' not found in PATH." > /dev/stderr
            set missing_deps yes
        end
    end

    if test -n "$missing_deps"
        echo "Please install the missing dependencies and try again." > /dev/stderr
        exit 1
    end

    # Split arguments handling based on count
    set -l arg_count (count $argv)

    if test $arg_count -eq 1
        show_help $argv[1]
    else
        # Otherwise pass all arguments to run_task as normal
        run_task $argv
    end
end
