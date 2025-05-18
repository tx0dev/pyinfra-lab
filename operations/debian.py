from pyinfra.api.deploy import deploy
from pyinfra.api.operation import operation
from pyinfra.operations import apt, files
# pyright: reportPrivateUsage=none, reportUnknownParameterType=none


@operation()
def set_timezone(zone: str = "America/Toronto"):
    """
    Set the timezone

    + zone: the timezone to set
    """
    yield from files.link._inner(
        path="/etc/localtime",
        target=f"/etc/zoneinfo/{zone}",
        present=True,
        symbolic=True,
    )


@deploy("Install tooling")
def install_tooling():
    _ = apt.packages(
        name="Install tools",
        packages=["neovim", "curl", "jq"],
    )
