# Lab deployment for PyInfra

Lab solutions to test deployment for different PyInfra components on a test VM.

## Prequisites

- UV
- Virsh
  - A vm name `alpine-lab` or `debian-lab`
  - To reset back to zero, a `base` snapshot.

Although the lab.fish file will use dynamic IP, the inventory.py isn't, you'll need to update the IP there.

## Testing

For Concourse, a full runthrough can be done using `time ./lab.fish full`.

Timed:
```
Executed in   70.57 secs      fish           external
   usr time  916.55 millis    0.00 millis  916.55 millis
   sys time  267.12 millis    1.01 millis  266.12 millis
```

Functions in the `lab.fish` file:
- `ssh [cmd]`: Run a command or SSH in the VM
- `reset`: Reset the VM to the base snapshot
- `start`: Start the VM
- `rebuild`: Rebuild the VM using cloud-init (only Debian)

And project tasks:
- `debug`: Run pyinfra debug-inventory
- `deploy`: Run pyinfra with deploy.py
- `task [cmd]`: Run arbitrary pyinfra command
- `fly-hello`: Using Fly, login, create the hello pipeline, and trigger it

## Todo

- [ ] Deployment worker on other nodes
- [ ] Proper identity/Auth for web node
