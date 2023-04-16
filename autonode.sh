#!/bin/bash 

####
# Examine environment, define valid inputs, declare variables
##
if ! command -v docker &> /dev/null; then
  docker_installed=false
else
  docker_installed=true
fi
if ! command -v ssh &> /dev/null; then
  openssh_installed=false
else
  openssh_installed=true
fi
# IP validation working for IPV4
ip_valid='^(0*(1?[0-9]{1,2}|2([0-4][0-9]|5[0-5]))\.){3}'
ip_valid+='0*(1?[0-9]{1,2}|2([‌​0-4][0-9]|5[0-5]))$'
# Swarm token validation not working
# swarm_token_valid='SWMTKN.*[A-Za-z0-9]+.*[A-Za-z0-9]+.*\b(?:(?:2(?:[0-4][0-9]|5[0-5])|[0-1]?[0-9]?[0-9])\.){3}(?:(?:2([0-4][0-9]|5[0-5])|[0-1]?[0-9]?[0-9]))\b.*[0-9]+'
swarm_token_valid='^SWMTKN.{80}([0-9]{1,3}\.){3}([0-9]{1,3}):[0-9]{1,5}$'
port_valid='[0-9]+'
swarm_ip_addresses=()
new_swarm=false
nfs_setup=false
enable_ssh=false
nfsclient_installed=false
####
# Detect init file if given, verify that it exists, and set quiet_install to true or false
##
if [[ "$1" == "-init" ]]; then
    INPUT_FILE="$2"
    if ! [[ -f "$INPUT_FILE" ]]; then
        echo "Error: File not found: $INPUT_FILE"
        exit 1
    fi
    source "$INPUT_FILE"
    quiet_install=true
    if [[ -z "$log_file"]]; then
      log_file=install.log
    fi
    exec &> >(tee -a "$log_file")
else
  quiet_install=false
  exec &> >(tee -a "install.log")
fi
#
####
# Allow the user to customize the install if not running quiet install,
##
if [ "$quiet_install"=false ]; then
  while true; do
    read -p "Do you want to initiate a new Docker Swarm? (y/n) " new_swarm_opt
    if ([ $new_swarm_opt == "y" ] || [ $new_swarm_opt == "Y" ] || [ $new_swarm_opt == "n" ] || [ $new_swarm_opt == "N" ]); then
      break
    else
      echo "Invalid input. Please try again."
    fi
  done
  if ([ $new_swarm_opt == "y" ] || [ $new_swarm_opt == "Y" ]); then
    new_swarm=true
  else
    new_swarm=false
  fi
  if [[ "$new_swarm" = true ]]; then
    while true; do
      read -p "Enter the IP address of this node: " node_ip_address
      if  [[ $node_ip_address =~ $ip_valid ]]; then
        break
      else
        echo "Invalid input. Please try again."
      fi
    done
  else
    read -p "Enter Docker Swarm token, including manager IP and port: " swarm_token
# Swarm token input validation WIP
#    while true; do
#      read -p "Enter Docker Swarm token, including manager IP and port: " swarm_token
#      if [[ "$swarm_token" =~ "$swarm_token_valid" ]]; then
#        break
#      else
#        echo "Invalid input. Please try again."
#      fi
#    done
  fi 
  while true; do
    read -p "Enter a docker swarm node IP address to whitelist in UFW (or press enter to continue): " swarm_ip_address
    if [[ $swarm_ip_address =~ $ip_valid ]]; then
      swarm_ip_addresses+=("$swarm_ip_address")
    elif [[ -z "$swarm_ip_address" ]]; then
      break
    else
      echo "Invalid input. Please try again."
    fi
  done
  while true; do
    read -p "Would you like to install/enable OpenSSH on this host? (y/n) " enable_ssh_opt
    if ([ "$enable_ssh_opt" == "y" ] || [ "$enable_ssh_opt" == "Y" ] || [ "$enable_ssh_opt" == "n" ] || [ "$enable_ssh_opt" == "N" ]); then
      break
    else
      echo "Invalid input. Please try again."
    fi
  done
  if ([ "$enable_ssh_opt" == "Y" ] || [ "$enable_ssh_opt" == "y" ]); then
    enable_ssh=true
  fi
# NFS share setup only validates that input is not blank. Need to write input validation for this feature and generally improve input validation in the script.
  while true; do
  read -p "Would you like to setup an NFS share? (y/n) " nfs_setup_opt
    if ([ "$nfs_setup_opt" == "y" ] || [ "$nfs_setup_opt" == "Y" ] || [ "$nfs_setup_opt" == "n" ] || [ "$nfs_setup_opt" == "N" ]); then
      break
    else
     echo "Invalid input. Please try again."
    fi
  done
  if ([ "$nfs_setup_opt" == "Y" ] || [ "$nfs_setup_opt" == "y" ]); then
    nfs_setup=true
  fi  
  if [[ "$nfs_setup" = true ]]; then
    while true; do
      read -p "Please enter the IP or hostname of the NFS server: " nfs_url
      if [[ ! -z "$nfs_url" ]]; then
        break
      else
        echo "Invalid input. Please try again."
      fi
    done
    while true; do
      read -p "Please enter the directory shared by the NFS server: ? " nfs_mount
      if [[ ! -z "$nfs_mount" ]]; then
        break
      else
       echo "Invalid input. Please try again."
      fi
    done
    while true; do
      read -p "Please enter the local mount point for the NFS share: (This directory need not already exist) " local_mount
      if [[ ! -z "$local_mount" ]]; then
        break
      else
        echo "Invalid input. Please try again."
      fi
    done
  fi
  while true; do
    echo "! WARNING ! Enabling the following will cause weird errors if you are using "$nfs_url":"$nfs_mount" for multiple docker daemons!!"
    read -p "Do you want to use this share as the default location for docker containers? (y/n) " nfs_docker_data_opt
    if ([ "$nfs_docker_data_opt" == "y" ] || [ "$nfs_docker_data_opt" == "Y" ] || [ "$nfs_docker_data_opt" == "n" ] || [ "$nfs_docker_data_opt" == "N" ]); then
      break
    else
     echo "Invalid input. Please try again."
    fi
  done
  if ([ "$nfs_docker_data_opt" == "Y" ] || [ "$nfs_docker_data_opt" == "y" ]); then
    nfs_docker_data=true
  fi
fi
#Function to install docker 
install_docker() {
    apt-get update
    apt-get install ca-certificates curl gnupg -y
    mkdir -m 0755 -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    chmod a+r /etc/apt/keyrings/docker.gpg
    apt-get update
    apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y
    docker run hello-world
    if [[ "$quiet_install" = false ]]; then
      echo "Docker is installed, now configuring docker swarm."
    fi  
}
# Function to add all nodes from swarm_ip_addresses to whitelist for docker ports
whitelist_nodes() {
    for swarm_ip_address in "${swarm_ip_addresses[@]}"; do
      if [[ "$quiet_install" = false ]]; then
        echo "Whitelisting IP address in UFW: $ip_address"
      fi
      ufw allow from $swarm_ip_address to any port 2377 comment 'Docker Swarm'
      ufw allow from $swarm_ip_address to any port 4789 comment 'Docker Swarm'
      ufw allow from $swarm_ip_address to any port 7946 comment 'Docker Swarm'
      ufw reload
    done
}
# Function to install & enbable openssh
allow_ssh() {
    if [[ "$openssh_installed" = false ]]; then
      apt-get update
      apt-get install openssh-server -y
    fi
    ufw allow OpenSSH
    ufw reload
}
# Funciton to initialize docker swarm
init_swarm() {
    docker swarm init --advertise-addr $node_ip_address --listen-addr $node_ip_address
    join_token=$(docker swarm join-token -q worker)
    if [[ "$quiet_install" = false ]]; then
      echo "Swarm initiated!"
    fi
}
# Function to join swarm
join_swarm() {
    if [[ "$quiet_install" = false ]]; then
      echo "Joining swarm with the following token: $swarm_token"
    fi
    docker swarm join --token $swarm_token
}
# Function to mount NFS share & set docker data directory
mount_containdir() {
    if [[ "$nfsclient_installed" = false ]]; then
    apt-get update
    apt-get install nfs-common -y
    fi
    mkdir $local_mount
    mount $nfs_url:$nfs_mount $local_mount
    if [[ "$nfs_docker_data" = true ]]; then
      touch /etc/docker/daemon.json
      echo "{ 
        "data-root": "$local_mount"
        }" | tee -a /etc/docker/daemon.json
      systemctl stop docker
      systemctl start docker
    fi
}
####
# Execute functions based on selected parameters.
##
if [[ "$docker_installed" = false ]]; then
install_docker
fi
if [[ "$enable_ssh" = true ]]; then
  allow_ssh
fi
whitelist_nodes
if [[ "$nfs_setup" = true ]]; then
  mount_containdir
fi
if [[ "$new_swarm" = true ]]; then
  init_swarm
else
  join_swarm
fi
read



