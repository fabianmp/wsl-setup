# Script for WSL 2 Initialization

Script for basic setup of WSL 2 with native Docker and ZSH.
The script is interactive and each step may be skipped (although some steps may require a previous step to install requirements).

Using systemd in WSL 2 and the required scripts are based on https://github.com/shayne/wsl2-hacks.

## Running the Script

```sh
bash <(curl -s https://raw.githubusercontent.com/fabianmp/wsl-setup/master/setup_wsl.sh)
```

## Suggested settings in .bashrc or .zshrc

```sh
sudo start-systemd
export LIBGL_ALWAYS_INDIRECT=Yes
export DISPLAY=$(netsh.exe interface ip show address "vEthernet (WSL)" | awk '/IP[^:]+:/ {print $2}' | tr -d '\r'):0
```
