#!/bin/bash

####################
# Helper functions #
####################

info() {
  echo "$(tput setaf 4)$1$(tput sgr 0)"
}

error() {
  echo "$(tput setaf 1)$1$(tput sgr 0)"
}

success() {
  echo "$(tput setaf 2)$1$(tput sgr 0)"
}

warning() {
  echo "$(tput setaf 3)$1$(tput sgr 0)"
}

highlight() {
  echo "$(tput setaf 6)$1$(tput sgr 0)"
}

prompt_yes_no() {
  default_reply="y"
  if [[ "$default_reply" == "y" ]]; then
    yes_no="Y/n"
  else
    yes_no="y/N"
  fi

  read -n 1 -r -p "$(tput setaf 4)$1 [$yes_no]:$(tput sgr 0) " reply
  if [[ -n "$reply" ]]; then
    echo
  fi
  if [[ ${reply:-$default_reply} =~ ^[Yy]$ ]]; then
    return 0
  fi
  return 1
}

prompt_string() {
  read -p "$(tput setaf 4)$1 [$2]:$(tput sgr 0) " reply
  echo ${reply:-$2}
}

#########
# Tasks #
#########

#-----------------------
# sudo without password
#-----------------------

if prompt_yes_no "Configure sudo without password prompt?"; then
  cat <<EOF | sudo EDITOR='tee -a' visudo > /dev/null
$USER   ALL=(ALL:ALL) NOPASSWD: ALL
EOF

  success "allowing $USER to call sudo without password"
fi

#-------------------------
# upgrade system packages
#-------------------------

if prompt_yes_no "Upgrade system packages?"; then
  sudo apt update
  sudo apt dist-upgrade -y
  sudo apt upgrade -y wslu

  success "upgraded system packages"
fi

#-----------------------------
# install additional packages
#-----------------------------

if prompt_yes_no "Install additional useful software?"; then
  sudo apt update
  sudo apt install -y --no-install-recommends jq make pkg-config pwgen software-properties-common unzip xdg-utils

  success "installed addtional useful software"
fi

#-------------------------
# manual /etc/resolv.conf
#-------------------------

if prompt_yes_no "Configure custom /etc/resolv.conf configuration?"; then
  sudo tee /etc/wsl.conf > /dev/null <<EOF
[network]
generateResolvConf = false
EOF

  sudo rm -f /etc/resolv.conf
  sudo touch /etc/resolv.conf
  domain=$(prompt_string "Search domain:" "")
  nameservers=$(prompt_string "Enter nameservers:" "1.1.1.1 8.8.8.8")

  for n in $nameservers; do
    sudo tee -a /etc/resolv.conf > /dev/null <<EOF
nameserver $n
EOF
  done

  if [[ -n "$domain" ]]; then
    sudo tee -a /etc/resolv.conf > /dev/null <<EOF
domain $domain
search $domain
EOF
  fi

  success "updated /etc/resolv.conf"
fi

#-------------------
# configure Python3
#-------------------

if prompt_yes_no "Configure Python3 to be default?"; then
  info "install required packages"
  sudo apt update
  sudo apt install -y --no-install-recommends python3-pip python3-setuptools python3-venv

  info "set up binaries"
  sudo update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1
  sudo update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1
fi

#-------------
# install zsh
#-------------

if prompt_yes_no "Install zsh and oh-my-zsh?"; then
  info "install required packages"
  sudo apt update
  sudo apt install -y --no-install-recommends zsh

  info "download and install oh-my-zsh"
  export RUNZSH=no
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

#----------------
# set up systemd
#----------------

if prompt_yes_no "Set up systemd?"; then

  info "store current user name for use in scripts"
  sudo tee /etc/wsl_user > /dev/null <<EOF
$USER
EOF

  info "install required packages"
  sudo apt update
  sudo apt install -y --no-install-recommends daemonize dbus policykit-1

  info "create entry scripts for running systemd"
  sudo tee /usr/bin/start-systemd > /dev/null <<'EOF'
#!/bin/bash

# based on https://github.com/shayne/wsl2-hacks

# get pid of systemd
SYSTEMD_PID=$(pgrep -xo systemd)

if [[ -z ${SYSTEMD_PID} ]]; then
    # start systemd
    /usr/bin/daemonize -l "${HOME}/.systemd.lock" /usr/bin/unshare -fp --mount-proc /lib/systemd/systemd --system-unit=basic.target

    # wait for systemd to start
    retries=50
    while [[ -z ${SYSTEMD_PID} && $retries -ge 0 ]]; do
        (( retries-- ))
            sleep .1
            SYSTEMD_PID=$(pgrep -xo systemd)
    done

    if [[ $retries -lt 0 ]]; then
        >&2 echo "Systemd timed out; aborting."
        exit 1
    fi
fi
EOF
  sudo chmod +x /usr/bin/start-systemd

  sudo tee /usr/bin/execute-in-systemd > /dev/null <<'EOF'
#!/bin/bash

# based on https://github.com/shayne/wsl2-hacks

# get pid of systemd
SYSTEMD_PID=$(pgrep -xo systemd)

# if we're already in the systemd environment
if [[ "${SYSTEMD_PID}" -eq "1" ]]; then
    "$@"
fi

if [[ -z ${SYSTEMD_PID} ]]; then
    source /usr/bin/start-systemd
fi

# enter systemd namespace
/usr/bin/nsenter -t "${SYSTEMD_PID}" -m -p --wd="${PWD}" -S "${SUDO_UID}" -G "${SUDO_GID}" "${@}"
EOF
  sudo chmod +x /usr/bin/execute-in-systemd

  success "finished setting up systemd"
fi

#-----------------------
# install native Docker
#-----------------------

if prompt_yes_no "Install native Docker?"; then
  if [[ ! -f /usr/bin/execute-in-systemd ]]; then
    error "systemd must be set up"
  else
    info "install required packages"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    sudo apt update
    sudo execute-in-systemd sudo apt install -y --no-install-recommends docker-ce docker-ce-cli containerd.io

    info "allow using Docker without sudo"
    sudo usermod -aG docker $USER
    warning "you need to log in again to be able to use Docker without sudo"

    sudo tee /usr/local/bin/docker-enable-arm-build > /dev/null <<EOF
docker run --privileged --rm docker/binfmt:a7996909642ee92942dcd6cff44b9b95f08dad64
systemctl restart docker
docker buildx ls
EOF
    sudo chmod +x /usr/local/bin/docker-enable-arm-build

    mkdir -p ${HOME}/.docker
    cat > ${HOME}/.docker/config.json <<EOF
{
  "experimental": "enabled"
}
EOF

    info "finished installing Docker"
  fi
fi

#----------------------------
# display useful information
#----------------------------

echo
echo
echo

if [[ -f /usr/bin/execute-in-systemd ]]; then
  info "run the following command to start systemd, or add it to your .bashrc or .zshrc"
  highlight "sudo start-systemd"
  echo
  info "use the following command to execute commands in systemd namespace (e.g. to restart Docker)"
  highlight "sudo execute-in-systemd <command>"
  echo
  info "to restart a systemd service (e.g. Docker) use"
  highlight "sudo execute-in-systemd sudo systemctl restart docker"
  echo
  echo
fi

if [[ -f /usr/local/bin/docker-enable-arm-build ]]; then
    info "use the following command to enable cross-platform Docker builds using buildx"
    highlight "sudo execute-in-systemd sudo docker-enable-arm-build"
    highlight "docker buildx ls"
    echo
    echo
fi

info "add the following lines to your .bashrc or .zshrc to set the remote XServer to your Windows IP address"
echo
echo "export LIBGL_ALWAYS_INDIRECT=Yes"
echo 'export DISPLAY=$(netsh.exe interface ip show address "vEthernet (WSL)" | awk '"'"'/IP[^:]+:/ {print $2}'"'"' | tr -d '"'"'\r'"'"'):0'
echo
echo
success "finished setting up WSL"
echo
