#! /usr/bin/env bash

# 目前仅仅适用于do/centos7服务器的初装

# 使用淘宝源：ALI_SOURCE=1

declare basepath=$(cd `dirname "$0"`; pwd)
cd "$basepath"
source functions/core.bash

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
# 设置yum：1、卸载包时自动清除依赖；2、开启自动更新；3、安装常用yum插件
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
# 1、安装常用包；2、更新现有包
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
# 设置root密码
function do_rootpwd()
{
  passwd root
}

# 关闭selinux
function do_selinux()
{
  if [[ $# = 1 ]]; then
    declare file="/etc/selinux/config"; declare re="\s*0\s*=\s*\w*"
    set_value "$re" "0" "SELINUX=$1" "$file"
  fi
}

# *5
# 设置安全ssh：1、默认8322端口；2、不允许空密码；3、ssh自动重连；4、禁止其他登录方式；5、安装防火墙允许ssh
function do_ssh()
{
  do_selinux "permissive"
  do_pwdlogin "yes"

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
# 设置一般用户：1、添加用户david；2、配置ssh仅允许一般用户登录
function do_david()
{
  declare file="/etc/ssh/sshd_config"; declare re="\s*0\s+\w+\s*"
  set_value "$re" "0" "PermitRootLogin no" "$file"

  adduser david
  passwd david
}

# *7
# 安装ban
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
# function do_shadowsocks()
# {
#   curl -sSL "https://copr.fedoraproject.org/coprs/librehat/shadowsocks/repo/epel-7/librehat-shadowsocks-epel-7.repo" -o "/etc/yum.repos.d/librehat-shadowsocks-epel-7.repo"
#   yum update -y
#   yum install shadowsocks-libev -y
#   cat > /etc/shadowsocks-libev/config.json <<EOF
# {
#   "server":"0.0.0.0",
#   "server_port":8688,
#   "local_address":"127.0.0.1",
#   "local_port":1080,
#   "password":"bkbabydppwd",
#   "timeout":60,
#   "method":"aes-256-cfb",
#   "fast_open":true
# }
# EOF
#   go_serv "shadowsocks-libev"
#   firewall-cmd --add-port=8688/tcp --permanent
#   firewall-cmd --add-port=8688/udp --permanent
# }
function do_shadowsocks()
{
  cd "$basepath/../docker/shadowsocks"
  docker-compose up sss -d
  docker-compose ps
  cd "$basepath"
  firewall-cmd --add-port=6443/tcp --add-port=6500/udp --permanent
  firewall-cmd --reload
  firewall-cmd --list-all
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
  $basename/commands/ngrok.bash
}

function do_more()
{
  do_ssh
  do_david
  do_ban
  do_docker
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

function do_pwdlogin()
{
  if [[ $# = 1 ]]; then
    declare file="/etc/ssh/sshd_config"; declare re="\s*0\s+\w+\s*"
    set_value "$re" "0" "PasswordAuthentication $1" "$file"
  fi
}

function do_docker()
{
  yum remove -y \
    docker \
    docker-client \
    docker-client-latest \
    docker-common \
    docker-latest \
    docker-latest-logrotate \
    docker-logrotate \
    docker-selinux \
    docker-engine-selinux \
    docker-engine \
    docker-compose

  yum install -y yum-utils \
    device-mapper-persistent-data \
    lvm2
  if [[ $ALI_SOURCE = 1 ]]; then
    declare url=http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
  else
    declare url=https://download.docker.com/linux/centos/docker-ce.repo
  fi
  yum-config-manager --add-repo $url
  yum makecache fast
  yum install docker-ce -y
  go_serv "docker"

  yum install -y \
    python34 \
    python34-devel \
    python34-pip
  pip3 install --upgrade pip
  pip3 install docker-compose
}

# function do_shadowsocks2()
# {
#   declare port_s=8388
#   declare port_k=8389
#   declare password=bkbabydppwd
#   docker rm ss -f
#   docker run -dt \
#               --name ss \
#               -p $port_s:$port_s \
#               -p $port_k:$port_k/udp \
#               mritd/shadowsocks \
#               -s "-s 0.0.0.0 -p $port_s -m aes-256-cfb -k $password --fast-open" \
#               -k "-t 127.0.0.1:$port_s -l :$port_k -mode fast2" \
#               -x
#   firewall-cmd --add-port=$port_s/tcp --permanent
#   firewall-cmd --add-port=$port_k/udp --permanent
#   firewall-cmd --reload
# }

# *0
function do_help()
{
  declare name=$(basename $0)
  cat << HELP
Usage: [sudo] $name [action]

Actions:
    help           Print this help.
    hostname       Set the hostname.
    yum            Set the yum.
    update         Install the update.
    rootpwd        Set the password of root user.
    selinux        enforcing | permissive | disabled
    ssh            Set the ssh.
    david          Create new user named david.（要记得上传david的ssh）
    ban            Install the fail2ban.
    conf           Setting conf.
    shadowsocks    Install the shadowsocks.
    dev            Install the enviroment of dev.
    supervisor     Install the Supervisor.
    obfsshd        Install obfuscated-openssh.
    go             Install golang.
    ngrokd         Install ngrokd.

    normal         yum + update + rootpwd + ssh + david + ban
    pwdlogin       yes | no
    docker         Install docker.

This command help you init the VPS on DO.

Important!
    1. The actions must follow the order above.
    2. You need to be root to perform this command. (sudo)

For example:
    sudo $0 yum update

HELP
}

# main


if [[ $# = 0 ]]; then
  do_help
elif [[ $1 = "conf" ]]; then
  set_value "$2" "$3" "$4" "$5"
elif [[ $1 = "selinux" ]]; then
  do_selinux "$2"
elif [[ $1 = "pwdlogin" ]]; then
  do_pwdlogin "$2"
else
  for action in $@; do
    do_$action
    cd "$basepath"
  done
fi
