from pyinfra.operations import apk, openrc

from operations import alpine

alpine.set_timezone()
alpine.set_repository(version="3.21")
alpine.enable_community_repository()
# alpine.enable_edge_repository()
# alpine.enable_testing_repository()

alpine.install_tooling()

apk.packages(
    name="Install packages",
    packages=[
        "containerd",
        "kind",
        "nerdctl",
        "kubectl",
        "iptables",
    ],
)


openrc.service(
    name="Enable cgroups v2",
    service="cgroups",
    enabled=True,
    running=True,
)
openrc.service(
    name="Enable containerd",
    service="containerd",
    enabled=True,
    running=True,
)
