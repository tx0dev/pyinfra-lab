from io import StringIO
from pyinfra.operations import apt, systemd, files, server
from pyinfra.context import host
from pyinfra.facts.files import File
from pyinfra.facts.hardware import Ipv4Addrs
from operations import debian

KIND_RELEASE = "https://kind.sigs.k8s.io/dl/v0.28.0/kind-linux-amd64"
NERD_RELEASE = "https://github.com/containerd/nerdctl/releases/download/v2.1.1/nerdctl-2.1.1-linux-amd64.tar.gz"

ips = host.get_fact(Ipv4Addrs)["enp1s0"]
conf = StringIO(
    f"""kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  apiServerAddress: "{ips[0]}"
  apiServerPort: 6443
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 443
    hostPort: 443
    protocol: TCP
  - containerPort: 80
    hostPort: 80
    protocol: TCP
- role: worker
  extraPortMappings:
  - containerPort: 443
    hostPort: 8443
    protocol: TCP
  - containerPort: 80
    hostPort: 8080
    protocol: TCP
"""
)


_ = debian.set_timezone()
enable_sid = debian.enable_sid()
if enable_sid.changed:
    _ = apt.update()
_ = debian.install_tooling()

_ = apt.packages(
    name="Install packages",
    packages=[
        "containernetworking-plugins",
        "kubernetes-client",
        "iptables",
    ],
)
_ = apt.packages(
    name="Install containerd and runc from sid",
    packages=[
        "containerd",
        "runc",
        "kubernetes-client",
    ],
    extra_install_args="-t sid",
)

_ = systemd.service(
    name="Enable containerd",
    service="containerd",
    enabled=True,
    running=True,
)
_ = files.download(
    name="Download KIND",
    src=KIND_RELEASE,
    dest="/usr/local/bin/kind",
    mode="0755",
)

if not host.get_fact(File, "/usr/local/bin/nerdctl"):
    _ = files.download(
        name="Download NerdCTL",
        src=NERD_RELEASE,
        dest="/tmp/nerdctl.tar.gz",
    )
    _ = server.shell(
        name="Extract NerdCTL",
        commands=[
            "tar -xf /tmp/nerdctl.tar.gz -C /usr/local/bin",
            "chmod +x /usr/local/bin/nerdctl",
        ],
    )


_ = files.put(
    name="Put KIND config",
    src=conf,
    dest="/root/kind-cfg.yaml",
)
