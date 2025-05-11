import os
import re

import requests
from pyinfra.api.deploy import deploy
from pyinfra.context import host
from pyinfra.facts.files import Directory, File
from pyinfra.facts.server import Command, Groups, Users
from pyinfra.operations import apk, files, openrc, server

concourse_version = "7.13.1"
CONCOURSE_RELEASE = f"https://github.com/concourse/concourse/releases/download/v{concourse_version}/concourse-{concourse_version}-linux-amd64.tgz"
USER = "atc"
GROUP = "atc"
ETC_DIR = "/etc/concourse"


def get_checksum(asset_url, extension="sha1"):
    """
    Downloads a .sha1 file and extracts the SHA1 sum for a specific filename.

    Args:
        asset_url (str): The URL of the file.
        extension (str): The extension of the checksum file

    Returns:
        str or None: The checksum if found in the <extension> file, otherwise None.
    """
    try:
        response = requests.get(f"{asset_url}.{extension}")
        response.raise_for_status()
        content = response.text.strip()

        filename = os.path.basename(asset_url)
        # Look for a line in the format: <hash> <filename>
        for line in content.splitlines():
            parts = line.split()
            if (
                len(parts) == 2
                and parts[1] == filename
                and re.match(r"^[0-9a-f]{40}$", parts[0])
            ):
                return parts[0]
            # Also handle potential "SHA1(<filename>) = <sha1_hash>" format
            match = re.match(rf"SHA1\({re.escape(filename)}\) = ([0-9a-f]{40})", line)
            if match:
                return match.group(1)

        return None

    except requests.exceptions.RequestException as e:
        print(f"Error downloading SHA1 file: {e}")
        return None


@deploy("Concourse install")
def install_concourse():
    apk.packages(name="add iptables", packages=["iptables"])
    # Enable cgroups v2
    openrc.service(
        name="Enable cgroups v2",
        service="cgroups",
        enabled=True,
        running=True,
    )
    if host.get_fact(Directory, "/usr/local/concourse"):
        current_version = host.get_fact(
            Command, "/usr/local/concourse/bin/concourse --version"
        )
        print(f"Concourse Version: {current_version}")
    else:
        current_version = None

    target = f"/tmp/concourse-{concourse_version}.tgz"

    if current_version != concourse_version:
        files.download(
            name=f"Downloading v{concourse_version}",
            src=CONCOURSE_RELEASE,
            dest=target,
            sha1sum=get_checksum(CONCOURSE_RELEASE, "sha1"),
        )
        files.directory(
            name="Delete previous version", path="/usr/local/concourse", present=False
        )

        extract = server.shell(
            name="Extract",
            commands=[
                f"tar -zxf {target} -C /usr/local",
            ],
        )
        if extract.changed:
            files.file(name="Deleted tgz file", path=target, present=False)


@deploy("Concourse Services")
def setup_services(user: str = USER, group: str = GROUP):
    files.put(
        name="web Init",
        src="assets/concourse-web.initd",
        dest="/etc/init.d/concourse-web",
        mode="755",
    )
    files.put(
        name="web Conf",
        src="assets/concourse-web.confd",
        dest="/etc/conf.d/concourse-web",
        mode="644",
    )
    files.put(
        name="Worker Init",
        src="assets/concourse-worker.initd",
        dest="/etc/init.d/concourse-worker",
        mode="755",
    )
    if group not in host.get_fact(Groups):
        server.shell(
            name=f"{group} group",
            commands=[
                f"grep -q ^{group}: /etc/group || addgroup -S {group}",
            ],
        )
    if user not in host.get_fact(Users):
        server.shell(
            name=f"{user} user",
            commands=[
                f"grep -q ^{user}: /etc/passwd || adduser -S -D -H -g '' -G {user} -h / -s /sbin/nologin {user}"
            ],
        )
    files.directory(
        name="Config directory",
        path=ETC_DIR,
        user=group,
        group=user,
        present=True,
    )


@deploy("First run")
def first_run(group=GROUP, user=USER):
    for key in ["session_signing_key", "tsa_host_key", "authorized_worker_keys"]:
        key_file = f"{ETC_DIR}/{key}"
        if not host.get_fact(File, key_file):
            type = "rsa" if key == "session_signing_key" else "ssh"
            server.shell(
                name=f"Gen: {key}",
                commands=[
                    f"/usr/local/concourse/bin/concourse generate-key -t {type} -f {key_file}"
                ],
            )
            files.file(name=f"Mod: {key}", path=key_file, user=user, group=group)
            if type == "ssh":
                files.file(
                    name=f"Mod: {key}.pub",
                    path=f"{key_file}.pub",
                    user=user,
                    group=group,
                )
    files.line(
        name="First boot with testing user",
        path="/etc/conf.d/concourse-web",
        line='#test_local_user="NO"',
        replace='test_local_user="YES"',
    )
    openrc.service(name="Starting Web", service="concourse-web", running=True)
    server.wait(name="Wait for first launch", port=8080)
    openrc.service(name="Stopping Web", service="concourse-web", running=False)
    files.line(
        name="Revert first boot changes",
        path="/etc/conf.d/concourse-web",
        line='test_local_user="YES"',
        replace='#test_local_user="NO"',
    )


def start_web():
    openrc.service(
        name="Starting Web", service="concourse-web", running=True, enabled=True
    )


def start_worker():
    openrc.service(
        name="Starting worker", service="concourse-worker", running=True, enabled=True
    )
