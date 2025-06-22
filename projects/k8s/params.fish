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
    log_step "Post-create task: Create KIND cluster"
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
    set -l command_args "kind create cluster --config /root/kind-cfg.yaml && kubectl cluster-info && kubectl get nodes"
    log_cmd "ssh $SSH_USER@$ip $command_args"
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args
end

function project_task_post-flux
    log_step "Post-flux task: Install Flux"

    # Get VM IP with error checking
    set -l ip (dom_ip)
    if test -z "$ip"; or not string match -qr '^\d+\.\d+\.\d+\.\d+$' "$ip"
        log_error "Could not get valid IP address for VM '$DOMAIN'."
        return 1
    end

    set -l command_args "curl -s https://fluxcd.io/install.sh | bash"
    log_cmd "ssh $SSH_USER@$ip $command_args"
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args
end

function project_task_fetch-kubecfg
    set -l ip (dom_ip)
    if test -z "$ip"; or not string match -qr '^\d+\.\d+\.\d+\.\d+$' "$ip"
        log_error "Could not get valid IP address for VM '$DOMAIN'."
        return 1
    end
    set -l command_args "kubectl config view --raw"
    log_cmd "ssh $SSH_USER@$ip $command_args"
    begin
        set -l IFS
        set kubeconf (ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args)
    end
    set replace ".clusters[0].cluster.server = \"https://$ip:6443\""
    echo $kubeconf | yq e $replace - | tee ~/.kube/kind.config
end
function project_task_delete-cluster
    set -l ip (dom_ip)
    if test -z "$ip"; or not string match -qr '^\d+\.\d+\.\d+\.\d+$' "$ip"
        log_error "Could not get valid IP address for VM '$DOMAIN'."
        return 1
    end
    set -l command_args "kind delete cluster"
    log_cmd "ssh $SSH_USER@$ip $command_args"
    ssh -i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=10 $SSH_USER@$ip $command_args
end

function project_task_local-bootstrap
    set -xg KUBECONFIG ~/.kube/kind.config
    pwd
    flux bootstrap git --url=ssh://git.tx0.foo:23231/flux-lab.git --branch=main --private-key-file=../../secrets/flux-lab.key --path=clusters/kind
    kubectl -n flux-system create secret docker-registry regcred \
        --docker-username=flux \
        --docker-password=sdgfralwwG15dsr7X0Dz --docker-server=registry.tx0.foo
    cat ../../secrets/age.key |
        kubectl create secret generic sops-age \
          --namespace=flux-system \
          --from-file=age.agekey=/dev/stdin
end
