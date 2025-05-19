# Lab deployment for PyInfra

Virsh based deployment lab. It evolved from testing PyInfra components to testing more things...

## Prequisites

- UV
- Virsh
  - For Alpine, a based installed with ssh keys injected.
  - Debian is bootstrap from cloud-init
    - We inject s static host key for SSH, see the [user-data](cloud-init/user-data)
  - To reset back to zero, a `base` snapshot.

The IP is discovered automatically and the inventory.py file get's it's target from the environment variable `LAB_TARGET`.

## Testing

A full runthrough can be done using `./lab.fish full <project>`.

A full concourse deployment takes about 70 seconds:
```
Executed in   70.57 secs      fish           external
   usr time  916.55 millis    0.00 millis  916.55 millis
   sys time  267.12 millis    1.01 millis  266.12 millis
```

## Usage

The lab wraps around common activities, split in two categories: VM and project tasks.

./lab.fish <command> [project] <args>

VM commands:
- `ssh [project] [cmd]`: Run a command or SSH in the VM
- `reset [project]`: Reset the VM to the base snapshot
- `start [project]`: Start the VM
- `rebuild [project]`: Rebuild the VM using cloud-init (only Debian)
  - Can also take two optional parameter:
    - `+console` to show the qemu console
    - `+wait` to add a 10 seconds wait at the end (for scripts)

Project commands:
- `debug <project>`: Run pyinfra debug-inventory
- `deploy <project>`: Run pyinfra with deploy.py
- `task <project> <task>`: Run a specific pyinfra task
- `full <project>`: Run a full deployment, including custom _post-*_ tasks.
- `[custom] <project> [args]`: Function present in the project `params.fish` file, named `project_tasks_[custom]`.

## Projects Todo

### Concourse
- [ ] Deployment worker on other nodes
- [ ] Proper identity/Auth for web node
