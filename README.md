# Lab deployment for Concourse

Deployment of Concourse using PyInfra on a test VM.

## Prequisites

- UV
- Concourse fly CLI
- Virsh
  - an alpine vm name `alpine-lab`
  - To reset back to zero, a `base` snapshot.

Although the lab.fish file will use dynamic IP, the inventory.py isn't, you'll need to update the IP there.

## Testing

A full runthrough can be done using `time ./lab.fish full`.

Timed:
```
Executed in   70.57 secs      fish           external
   usr time  916.55 millis    0.00 millis  916.55 millis
   sys time  267.12 millis    1.01 millis  266.12 millis
```

Functions in the `lab.fish` file:
- `ssh [cmd]`: Run a command or SSH in the VM
- `debug`: Run pyinfra debug-inventory
- `deploy`: Run pyinfra with deploy.py
- `task [cmd]`: Run arbitrary pyinfra command
- `fly-hello`: Using Fly, login, create the hello pipeline, and trigger it
- `reset`: Reset the VM to the base snapshot
- `start`: Start the VM

## Todo

- [ ] Deployment worker on other nodes
- [ ] Proper identity/Auth for web node
