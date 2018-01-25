#!/bin/bash
set -e

# copy ssh keys for root
if [ -d /.ssh/ ]; then
    rsync -r --delete /.ssh/  /root/.ssh/
fi

# setup ssh-agent
if [ ! -z "$SSH_AUTH_SOCK" ]; then
    # if socket is not available create the new auth session
    if [ ! -S "$SSH_AUTH_SOCK" ]; then
        `ssh-agent -a $SSH_AUTH_SOCK`
        echo $SSH_AGENT_PID > $HOME/.ssh/.auth_pid
    fi
    # add ssh keys to agent
    ssh-add
fi

# wait for /etc/resolv.conf to appear (in docker container)
until [ -s /etc/resolv.conf ]; do
    sleep 1
done

# dirty hack for empty resolv.conf (in docker container)
if [ ! -s /etc/resolv.conf ]; then
    echo "nameserver 192.168.2.1" >> /etc/resolv.conf
fi

# check contents of /etc/resolv.conf
echo "Checking /etc/resolv.conf"
cat /etc/resolv.conf

# source bashrc
source /root/.bashrc

# exec passed command
echo "Running command: $@"
exec "$@"
