from pyinfra.api.operation import operation
from pyinfra.context import host
from pyinfra.api.deploy import deploy
from pyinfra.facts.files import FindInFile
from pyinfra.operations import files, apk


# Check that the @edge repository is enabled
@operation()
def enable_edge_repository(
    mirror: str = "http://mirror.csclub.uwaterloo.ca", backup: bool = False
):
    """
    Add the @edge APK repositories

    + mirror: the mirror to use
    + backup: whether to create a backup of the file
    """
    file = "/etc/apk/repositories"
    if backup:
        yield f"cp -a {file} {file}.bak"
    for repo in ["main", "community"]:
        yield from files.line._inner(
            path=file,
            line=f"@edge {mirror}/alpine/edge/{repo}",
            present=True,
        )


@operation()
def enable_testing_repository(
    mirror: str = "http://mirror.csclub.uwaterloo.ca", backup: bool = False
):
    """
    Add the @testing APK repositories

    + mirror: the mirror to use
    + backup: whether to create a backup of the file
    """
    file = "/etc/apk/repositories"
    if backup:
        yield f"cp -a {file} {file}.bak"
    yield from files.line._inner(
        path=file,
        line=f"@testing {mirror}/alpine/edge/testing",
        present=True,
    )


@operation()
def enable_community_repository():
    """
    Add the community repositories
    """
    file = "/etc/apk/repositories"
    if host.get_fact(FindInFile, path=file, pattern="^#.*community$"):
        yield f"sed -i '/^#.*community$/s/^#//' {file}"


@operation()
def disable_community_repository():
    """
    Remove the community repositories
    """
    file = "/etc/apk/repositories"
    if host.get_fact(FindInFile, path=file, pattern="^[hf].*community$"):
        yield f"sed -i '/^[hf].*community$/s/^/#/' {file}"


@operation()
def set_repository(
    mirror: str = "http://mirror.csclub.uwaterloo.ca",
    version: str = "3.21",
    backup: bool = False,
):
    """
    Set the APK repositories to the specified mirror and version

    + mirror: the mirror to use
    + version: the version of Alpine Linux
    + backup: whether to create a backup of the file
    """
    file = "/etc/apk/repositories"

    update = False
    if backup:
        yield f"cp -a {file} {file}.bak"

    # Recreate the entry
    for repo in ["main", "community"]:
        # Check if a there's a line for that version
        if not host.get_fact(FindInFile, path=file, pattern=f"v{version}/{repo}"):
            # Set the repo
            yield from files.line._inner(
                path=file,
                line=f"{mirror}/alpine/v{version}/{repo}",
                present=True,
                ensure_newline=True,
            )
            update = True

    # Delete empty lines
    if update:
        yield f"sed -i '/^[[:space:]]*$/d' {file}"


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
    _ = apk.packages(
        name="Install tools",
        packages=["neovim", "curl", "jq"],
    )
