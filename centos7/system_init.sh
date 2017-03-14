#! /usr/bin/env bash

# 目前仅仅适用于do/centos7服务器的初装

# -----color list-----

declare -r BK_CODE_PRE="\033["
declare -r BK_CODE_RESET="${BK_CODE_PRE}0m"
# style
declare -r BK_CODE_BOLD="${BK_CODE_PRE}1m"
declare -r BK_CODE_UNDERLINE="${BK_CODE_PRE}4m"
# color
declare -r BK_CODE_RED="${BK_CODE_PRE}31m"
declare -r BK_CODE_GREEN="${BK_CODE_PRE}32m"
declare -r BK_CODE_YELLOW="${BK_CODE_PRE}33m"
declare -r BK_CODE_BLUE="${BK_CODE_PRE}34m"

# -----lib functions-----

# ---for systemd---

function set_serv()
{
  if [[ $# > 0 ]]; then
    systemctl enable $@
    systemctl restart $@
  fi
}

function show_serv()
{
  if [[ $# > 0 ]]; then
    systemctl status $@
  fi
}

function go_serv()
{
  if [[ -n "$1" ]]; then
    set_serv "$1.service"
    show_serv "$1.service"
  fi
}

# ---for configuration---

# get_key "Port 22"
function get_key()
{
  if [[ -n "$1" ]]; then
    echo $(expr "$1" : "\(\w*\)")
  fi
}

# make_re "...0..." "0" "Port 22"
function make_re()
{
  if [[ $# = 3 ]]; then
    declare re="$1"; declare tpl="$2"; declare src="$3"
    declare key=$(get_key $src)
    echo "$re" | sed "s/$tpl/$key/g"
  fi
}

# set_value "...0..." "0" "Port 22" "/etc/ssh/sshd.conf"
function set_value()
{
  if [[ $# = 4 ]]; then
    declare re=$(make_re "$1" "$2" "$3")
    declare new="$3"; declare file="$4"
    declare lines=$(sed -rn "/^$re$/=" "$file"); echo $lines

    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}set $re to $new in $file${BK_CODE_RESET}"

    declare -i i=0; declare cmd
    for l in $lines; do
      ((i++))
      if [[ $i = 1 ]]; then
        cmd="$l c $new"
      else
        cmd="$l d; $cmd"
      fi
    done
    if [[ $i > 0 ]]; then
      echo "sed command: $cmd"
      sed -i.bak "$cmd" "$file"
    else # i=0
      declare lines=$(sed -rn "/^#$re$/=" "$file")
      for l in $lines; do
        ((i++))
        sed -i.bak "$l a $new" "$file"
        break
      done
      if [[ $i = 0 ]]; then
        sed -i.bak "$ a $new" "$file"
      fi
    fi
    grep --color=auto "$re" "$file"
  fi
}

# -----main functions-----

# *1
function do_hostname()
{
    declare new_name="$1"; declare old_name=$(hostname);
    if [[ -z "$new_name" ]]; then
      read new_name
    fi
    if [[ -n "$new_name" && -n "$old_name" ]]; then
      sed -i.bak "s/$old_name/$new_name/g" /etc/hostname
      sed -i.bak "s/$old_name/$new_name/g" /etc/hosts
    fi
}

# *2
function do_yum()
{
  # yum-conf
  set_value "\s*0\s*=\s*\w*" "0" "clean_requirements_on_remove=1" "/etc/yum.conf"
  # yum-cron
  yum install yum-cron -y
  set_value "\s*0\s*=\s*\w*" "0" "apply_updates = yes" "/etc/yum/yum-cron.conf"
  go_serv "yum-cron"
  yum install yum-axelget \
              yum-langpacks \
              yum-plugin-fastestmirror \
              yum-plugin-remove-with-leaves \
              yum-plugin-show-leaves \
              -y
}

# *3
function do_update()
{
  # tmux
  yum install tmux -y # && tmux
  # install deps
  yum install epel-release -y
  yum install bash-completion \
              git \
              vim \
              -y
  yum update -y
  yum clean all
}

# *4
function do_rootpwd()
{
  passwd root
}

# *5
function do_ssh()
{
  declare file="/etc/ssh/sshd_config"; declare re="\s*0\s+\w+\s*"
  set_value "$re" "0" "Port 8322" "$file"
  set_value "$re" "0" "PermitEmptyPasswords no" "$file"
  set_value "$re" "0" "ClientAliveInterval 60" "$file"
  set_value "$re" "0" "ClientAliveCountMax 3" "$file"
  set_value "$re" "0" "GSSAPIAuthentication no" "$file"

  yum install firewalld -y
  go_serv "firewalld"
  firewall-cmd --add-port=8322/tcp --permanent
  firewall-cmd --remove-service=ssh --permanent
}

# *6
function do_david()
{
  declare file="/etc/ssh/sshd_config"; declare re="\s*0\s+\w+\s*"
  set_value "$re" "0" "PermitRootLogin no" "$file"

  adduser david
  passwd david
}

# *7
function do_ban()
{
  yum install fail2ban-firewalld \
              fail2ban-server \
              -y
  cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[DEFAULT]
bantime = 1209600
banaction = firewallcmd-ipset
maxretry = 3

[sshd]
enabled = true
port = 0:65535
EOF
  go_serv "fail2ban"
  fail2ban-client ping
  fail2ban-client status
  fail2ban-client status sshd
}

# *8
function do_shadowsocks()
{
  curl -sSL "https://copr.fedoraproject.org/coprs/librehat/shadowsocks/repo/epel-7/librehat-shadowsocks-epel-7.repo" -o "/etc/yum.repos.d/librehat-shadowsocks-epel-7.repo"
  yum update -y
  yum install shadowsocks-libev -y
  cat > /etc/shadowsocks-libev/config.json <<EOF
{
  "server":"0.0.0.0",
  "server_port":8688,
  "local_address":"127.0.0.1",
  "local_port":1080,
  "password":"bkbabydppwd",
  "timeout":60,
  "method":"aes-256-cfb",
  "fast_open":true
}
EOF
  go_serv "shadowsocks-libev"
  firewall-cmd --add-port=8688/tcp --permanent
  firewall-cmd --add-port=8688/udp --permanent
}

# *9
function do_dev()
{
  yum install gcc \
              automake \
              autoconf \
              libtool \
              make \
              -y
}

# *10
function do_supervisor()
{
  declare file_exec="/usr/bin/supervisord"
  if [[ -x "$file_exec" ]]; then
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Supervisor has been installed.${BK_CODE_RESET}"
  else
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Installing Supervisor...${BK_CODE_RESET}"
    yum install supervisor -y
    go_serv "supervisord"
  fi
}

# *11
function do_obfsshd()
{
  declare file_exec="/usr/local/sbin/sshd"
  declare file_conf="/usr/local/etc/sshd_config"
  declare dir_log="/var/log/obfsshd"

  if [[ -x "$file_exec" ]]; then
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Obfuscated-openssh has been installed.${BK_CODE_RESET}"
  else
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Installing Obfuscated-openssh...${BK_CODE_RESET}"
    yum install zlib-devel \
                openssl-devel \
                -y
    git clone git://github.com/brl/obfuscated-openssh.git
    cd obfuscated-openssh && ./configure && make && make install
  fi

  declare re="\s*0\s+\w+\s*"
  declare pwd=""
  
  echo "Password of obfuscated-openssh:"; read -s pwd
  if [[ -n "$pwd" ]]; then
    set_value "$re" "0" "ObfuscatedPort 8022" "$file_conf"
    set_value "$re" "0" "ObfuscateKeyword $pwd" "$file_conf"
    firewall-cmd --add-port=8022/tcp --permanent
    do_supervisor
    if [[ ! -d "$dir_log" ]]; then
      mkdir "$dir_log"
    fi
    cat > /etc/supervisord.d/obfsshd.ini <<EOF
[program:obfsshd]
command = $file_exec -f $file_conf
user = root
autostart = true
autorestart = true
stdout_logfile = $dir_log/out.log
stderr_logfile = $dir_log/err.log
EOF
    #"$file_exec" -f "$file_conf"
  else
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Password is empty! Stopped!${BK_CODE_RESET}"
  fi
}

# *12
function do_go()
{
  yum install golang curl git make bison gcc glibc-devel -y
  bash < <(curl -sSL https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
  source $HOME/.gvm/scripts/gvm
  # gvm install go1.4
  # gvm use go1.4 --default
  gvm use system --default # 1.6.3
  go get -u github.com/gpmgo/gopm
}

# *13
function do_ngrokd()
{
  declare file_exec="/usr/local/sbin/ngrokd"
  declare dir_log="/var/log/ngrokd"

  if [[ -x "$file_exec" ]]; then
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Ngrok has been installed.${BK_CODE_RESET}"
  else
    echo -e "${BK_CODE_YELLOW}${BK_CODE_BOLD}Installing Ngrok...${BK_CODE_RESET}"
    git clone https://github.com/bkbabydp/ngrok.git
    cd ngrok && make release-server && cp ./bin/ngrokd "$file_exec"
  fi
  
  firewall-cmd --add-port=4443/tcp --permanent
  do_supervisor
  if [[ ! -d "$dir_log" ]]; then
    mkdir "$dir_log"
  fi
  cat > /etc/supervisord.d/ngrokd.ini <<EOF
[program:ngrokd]
command = $file_exec -domain="ngrok.lzw.name" -httpAddr="127.0.0.1:80" -httpsAddr="127.0.0.1:443"
user = root
autostart = true
autorestart = true
stdout_logfile = $dir_log/out.log
stderr_logfile = $dir_log/err.log
EOF
  #"$file_exec" -domain="ngrok.lzw.name" -httpAddr=":8480" -httpsAddr=":8443"
}

function do_more()
{
  do_ssh
  do_david
  do_ban
  do_shadowsocks
}

function do_normal()
{
  do_yum
  do_update
  do_rootpwd
  do_ssh
  do_david
  do_ban
}

function do_enable_pwd_login()
{
  if [[ $# = 1 ]]; then
    declare file="/etc/ssh/sshd_config"; declare re="\s*0\s+\w+\s*"
    set_value "$re" "0" "PasswordAuthentication $1" "$file"
  fi
}

function do_docker()
{
  yum install -y yum-utils
  yum-config-manager --add-repo \
                      https://download.docker.com/linux/centos/docker-ce.repo
  yum makecache fast
  yum install docker-ce -y

  yum install python34 python34-pip -y
  pip3 install --upgrade pip
  pip3 install docker-compose

  go_serv "docker"
}

function do_shadowsocks2()
{
  docker run -dt \
              --name ss \
              -p 6443:6443 \
              mritd/shadowsocks \
              -s "-s 0.0.0.0 -p 8388 -m aes-256-cfb -k bkbabydppwd --fast-open"
}

# *0
function do_help()
{
  declare name=$(basename $0)
  cat << HELP
Usage: [sudo] $name [action]

Actions:
    0. help           Print this help.
    1. hostname       Set the hostname.
    2. yum            Set the yum.
    3. update         Install the update.
    4. rootpwd        Set the password of root user.
    5. ssh            Set the ssh.
    6. david          Create new user named david.
    7. ban            Install the fail2ban.
    7.5. conf         Setting conf.
    8. shadowsocks    Install the shadowsocks.
    9. dev            Install the enviroment of dev.
    10. supervisor    Install the Supervisor.
    11. obfsshd       Install obfuscated-openssh.
    12. go            Install golang.
    13. ngrokd        Install ngrokd.

    14. normal        yum + update + rootpwd + ssh + david + ban
    15. enable_pwd_login yes|no
    16. docker        Install docker.
    17. do_shadowsocks2

This command help you init the VPS on DO.

Important!
    1. The actions must follow the order above.
    2. You need to be root to perform this command. (sudo)

For example:
    sudo $0 yum update

HELP
}

# main
declare basepath=$(cd `dirname "$0"`; pwd)
cd "$basepath"

if [[ $# = 0 ]]; then
  do_help
elif [[ $1 = "conf" ]]; then
  set_value "$2" "$3" "$4" "$5"
elif [[ $1 = "enable_pwd_login" ]]; then
  do_enable_pwd_login "$2"
else
  for action in $@; do
    do_$action
    cd "$basepath"
  done
fi
