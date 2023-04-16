# Autonode

Autonode is a bash script for setting up a new docker swarm, or a new node for your existing docker swarm. Autonode is tested on Ubuntu 22.10 and requires no additional packages to be installed prior to running.

To have Autonode run using values provided by a config file such as autonode.conf, make the script executable, run it as root, and specify your config with '-init *config*':
> sudo su

> chmod +x autonode.sh

> ./autonode.sh -init autonode.conf

To input values manually while Autonode runs, simply make the script executable and run it as root:
> sudo su

> chmod +x autonode.sh

> ./autonode.sh

Project is actively monitored at https://git.cliffhouse.games, mirrored to https://github.com/imthegm/autonode

For support, email kris@cliffhouse.games or join the Cliffhouse Games discord server at https://discord.cliffhouse.games

Enjoy!