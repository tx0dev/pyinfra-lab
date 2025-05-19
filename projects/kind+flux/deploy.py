from pyinfra.operations import apt, systemd, files, server
from pyinfra.context import host
from pyinfra.facts.files import File
from operations import debian

KIND_RELEASE = "https://kind.sigs.k8s.io/dl/v0.28.0/kind-linux-amd64"
NERD_RELEASE = "https://github.com/containerd/nerdctl/releases/download/v2.1.1/nerdctl-2.1.1-linux-amd64.tar.gz"

_ = debian.set_timezone()
_ = debian.enable_sid()
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
    packages=["containerd", "runc"],
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
