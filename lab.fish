#!/usr/bin/env fish

set CONNECT "qemu:///system"
set DOMAIN "alpine-lab"
set SNAPSHOT "base"
set SSH_KEY "~/.ssh/id_cluster"

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
    set -l task $argv[1]

    switch "$task"
        case "deploy"
            uv run pyinfra -y inventory.py deploy.py
        case "debug"
            uv run pyinfra -y inventory.py debug-inventory
        case "task"
            uv run pyinfra -y inventory.py $argv[2]
        case "ssh"
            set -l ip (dom_ip)
            ssh -i $SSH_KEY root@$ip $argv[2]

        case "fly-hello"
            set -l ip (dom_ip)
            fly login -t lab -c "http://$ip:8080" -u test -p test
            fly -t lab set-pipeline -p hello-world -c hello.yaml -n
            fly -t lab unpause-pipeline -p hello-world
            fly -t lab trigger-job --job hello-world/hello-world-job --watch
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
        case "*"
            echo "Unknown task: $task"
            return 1
    end
end

if test (count $argv) -lt 1
    echo "Usage: lab.fish <task>"
else
    run_task $argv
end
