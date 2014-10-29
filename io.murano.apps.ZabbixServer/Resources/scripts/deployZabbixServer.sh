#!/bin/bash

SERVER='localhost'
DB_NAME="$1"
DB_USER="$2"
DB_PASS="$3"
HOSTNAME="$4"

echo "DB_NAME=${DB_NAME}"
echo "DB_USER=${DB_USER}"
echo "DB_PASS=${DB_PASS}"

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

log "Install Zabbix dependencies"

log $(apt-get install -y debconf-utils build-essential snmp libsnmp-dev snmpd libcurl4-openssl-dev)

# All parameters that can be configured http://paste.openstack.org/show/123122/

log "Setting up debconf promt parameters"
# General settings
echo "zabbix-server-mysql zabbix-server-mysql/db/app-user string ${DB_USER}" | debconf-set-selections
echo "zabbix-server-mysql zabbix-server-mysql/app-password-confirm password ${DB_PASS}" | debconf-set-selections
echo "zabbix-server-mysql zabbix-server-mysql/password-confirm password ${DB_PASS}" | debconf-set-selections
echo "zabbix-server-mysql zabbix-server-mysql/db/dbname	string	${DB_NAME}" | debconf-set-selections

# MySQL application settings for zabbix-server-mysql
echo "mysql-server mysql-server/root_password password ${DB_PASS}" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password ${DB_PASS}" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password password ${DB_PASS}" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password ${DB_PASS}" | debconf-set-selections

echo "zabbix-server-mysql zabbix-server-mysql/mysql/app-pass password ${DB_PASS}" | debconf-set-selections
echo "zabbix-server-mysql zabbix-server-mysql/mysql/admin-pass password ${DB_PASS}" | debconf-set-selections
echo "zabbix-server-mysql zabbix-server-mysql/dbconfig-install boolean true" | debconf-set-selections
echo "zabbix-server-mysql zabbix-server-mysql/database-type select mysql" | debconf-set-selections

echo "zabbix-frontend-php zabbix-frontend-php/mysql/app-pass password ${DB_PASS}" | debconf-set-selections
echo "zabbix-frontend-php zabbix-frontend-php/pgsql/app-pass password ${DB_PASS}" | debconf-set-selections
echo "zabbix-frontend-php zabbix-frontend-php/database-type select mysql" | debconf-set-selections
echo "zabbix-frontend-php zabbix-frontend-php/password-confirm password ${DB_PASS}" | debconf-set-selections
echo "zabbix-frontend-php zabbix-frontend-php/mysql/admin-pass password ${DB_PASS}" | debconf-set-selections
echo "zabbix-frontend-php zabbix-frontend-php/app-password-confirm password ${DB_PASS}" | debconf-set-selections
echo "zabbix-frontend-php zabbix-frontend-php/mysql/admin-user string root" | debconf-set-selections


wget http://repo.zabbix.com/zabbix/2.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_2.4-1+trusty_all.deb

dpkg -i zabbix-release_2.4-1+trusty_all.deb
apt-get update

log $(apt-get install -y mysql-server zabbix-server-mysql zabbix-frontend-php)


log "Editing Zabbix-server config"

echo "DBName=${DB_NAME}" >>/etc/zabbix/zabbix_server.conf
echo "DBHost=${SERVER}" >>/etc/zabbix/zabbix_server.conf
echo "DBPassword=${DB_PASS}" >>/etc/zabbix/zabbix_server.conf
echo "DBUser=${DB_USER}" >>/etc/zabbix/zabbix_server.conf

cd /usr/share/zabbix-server-mysql/
gunzip *.gz

log "Setting up MySQL database"

mysql -u root -p ${DB_PASS}  << EOF

create user "${DB_USER}"@"localhost" identified by "${DB_PASS}";
create database ${DB_NAME};
use zabbix;
insert into users (alias, name, surname, passwd, type) values ("'${DB_USER}'", "'${DB_USER}'", 'Administrator', md5("'${DB_PASS}'"), 3 );
grant all privileges on ${DB_NAME}.* to ${DB_USER}@localhost;
flush privileges;

quit;
EOF

mysql -u ${DB_USER} -p ${DB_PASS} < schema.sql
mysql -u ${DB_USER} -p ${DB_PASS} < images.sql
mysql -u ${DB_USER} -p ${DB_PASS} < data.sql

log "Installing and setting Zabbix Web Interface"
log $(apt-get install -y php5 php5-gd php5-mysql firefox)


echo "post_max_size = 16M" >>/etc/php5/apache2/php.ini
echo "max_execution_time = 300" >>/etc/php5/apache2/php.ini
echo "max_input_time = 300" >>/etc/php5/apache2/php.ini
echo "date.timezone = UTC" >>/etc/php5/apache2/php.ini

php_conf=$(mktemp)

cat << EOF >> "$php_conf"
<?php
// Zabbix GUI configuration file
global \$DB;

\$DB["TYPE"]                     = 'MYSQL';
\$DB["SERVER"]                   = '${SERVER}';
\$DB["PORT"]                     = '0';
\$DB["DATABASE"]                 = '${DB_NAME}';
\$DB["USER"]                     = '${DB_USER}';
\$DB["PASSWORD"]                 = '${DB_PASS}';
// SCHEMA is relevant only for IBM_DB2 database
\$DB["SCHEMA"]                   = '';

\$ZBX_SERVER                     = '${SERVER}';
\$ZBX_SERVER_PORT                = '10051';
\$ZBX_SERVER_NAME                = '${HOSTNAME}';

\$IMAGE_FORMAT_DEFAULT   = IMAGE_FORMAT_PNG;
?>
EOF

cat "$php_conf" >>/usr/share/zabbix/conf/zabbix.conf.php

rm "$php_conf"

# Copy the example apache config to the /etc/apache2/conf-available/ directory to make Zabbix and Apache work together.
cp /usr/share/doc/zabbix-frontend-php/examples/apache.conf /etc/apache2/conf-available/zabbix.conf
a2enconf zabbix.conf
a2enmod alias
service apache2 restart


service zabbix-server restart
#zabbix_server -c /etc/zabbix/zabbix_server.conf -R config_cache_reload

add_fw_rule '-I INPUT 1 -p tcp -m tcp --dport 10051 -j ACCEPT -m comment --comment "by murano, Zabbix"'