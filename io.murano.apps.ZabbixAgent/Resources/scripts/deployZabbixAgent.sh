#!/bin/bash

# VARIABLES

PASSWORD="$1"
SERVER="$2"
HOSTNAME="$3"
ADMIN_USER='$4'

# Functions
function include(){
    curr_dir=$(cd $(dirname "$0") && pwd)
    inc_file_path=$curr_dir/$1
    if [ -f "$inc_file_path" ]; then
        . $inc_file_path
    else
        echo -e "$inc_file_path not found!"
        exit 1
    fi
}

# Check for Ubuntu
include "common.sh"

get_os
[[ $? -ne 0 ]] && exit 1
if [[ "$DistroBasedOn" != "debian" ]]; then
    DEBUGLVL=4
    log "ERROR: We are sorry, only \"debian\" based distribution of Linux supported for this service type, exiting!"
    exit 1
fi

log "Installing requirements"
log $(apt-get install -y debconf-utils curl curl-devel)

log "Setting debconf parameters"
echo "zabbix-agent zabbix-agent/server string ${SERVER}" | debconf-set-selections

log "Installing Zabbix Agent"
wget http://repo.zabbix.com/zabbix/2.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_2.4-1+trusty_all.deb
dpkg -i zabbix-release_2.4-1+trusty_all.deb
apt-get update

log $(apt-get install -y zabbix-agent)

log "Editing Zabbix config"

echo "Server=${SERVER}" >>/etc/zabbix/zabbix_agentd.conf
echo "ServerActive=${SERVER}" >>/etc/zabbix/zabbix_agentd.conf
echo "Hostname=${HOSTNAME}" >>/etc/zabbix/zabbix_agentd.conf
echo "EnableRemoteCommands=1" >>/etc/zabbix/zabbix_agentd.conf

log "Restarting Zabbix Agent"
service zabbix-agent restart
#zabbix_agentd -c /etc/zabbix/zabbix_agentd.conf -R config_cache_reload

zabbix_agentd -t "system.cpu.load[all,avg1]"
zabbix_agentd -t "net.if.discovery"

add_fw_rule '-I INPUT 1 -p tcp -m tcp --dport 10050 -j ACCEPT -m comment --comment "by murano, Zabbix"'


log $(curl -i -X POST -H 'Content-Type:application/json' -d'{"jsonrpc": "2.0","method":"user.login","params":{"user":"${ADMIN_USER}","password":"${PASSWORD}"},"id":1}' http://${SERVER}/zabbix/api_jsonrpc.php)
