from io import StringIO
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


@operation()
def enable_sid():
    """
    Enable the sid repository
    """
    yield from apt.repo._inner(
        src="deb http://ftp.ca.debian.org/debian sid main contrib", filename="sid"
    )
    yield from files.put._inner(
        dest="/etc/apt/preferences.d/99-debian-sid",
        src=StringIO("""Package: *
Pin: release a=unstable
Pin-Priority: 10k"""),
    )
    yield from apt.update._inner()


@deploy("Tooling")
def install_tooling():
    _ = apt.packages(
        name="Install tools",
        packages=["neovim", "curl", "jq"],
    )
