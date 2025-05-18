# Concourse project parameters
set DOMAIN "alpine-lab"
set DISK_BASE "/mnt/data/virt-images/alpine-3.21-virt-x86_64.qcow2"
set VM_MEMORY "6000"
set DISK_SIZE "10"

# Concourse specific settings
set CONCOURSE_PORT "8080"
set CONCOURSE_USER "test"
set CONCOURSE_PASSWORD "test"

# Custom project tasks
# Execute fly login and set up hello-world pipeline
function project_task_fly-hello
    # Get VM IP
    set -l ip (dom_ip)
    log_info "Logging into Concourse at $ip:$CONCOURSE_PORT"

    fly login -t lab -c "http://$ip:$CONCOURSE_PORT" -u $CONCOURSE_USER -p $CONCOURSE_PASSWORD
    fly -t lab set-pipeline -p hello-world -c $PROJECTS_DIR/concourse/hello.yaml -n
    fly -t lab unpause-pipeline -p hello-world
    fly -t lab trigger-job --job hello-world/hello-world-job --watch
end

# Check Concourse status via API
function project_task_status
    # Get VM IP
    set -l ip (dom_ip)
    log_info "Checking Concourse status at $ip:$CONCOURSE_PORT"

    curl -s "http://$ip:$CONCOURSE_PORT/api/v1/info" | jq
end
