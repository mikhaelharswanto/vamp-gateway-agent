#!/usr/bin/env bash

configuration=$1
pid_file=/usr/local/vamp/haproxy.pid
reload_lock=/usr/local/vamp/reload.lock
slave_mesos_replacer=/usr/local/vamp/replace_slave_mesos.py

PORTS=()

if [ ! -e ${pid_file} ] ; then
    touch ${pid_file}
fi

function create_reload_lock() {
    while [ -e ${reload_lock} ]; do
        echo "waiting for reload lock..."
        sleep .1
    done
    echo 1 > ${reload_lock}
}

function remove_reload_lock() {
    rm ${reload_lock}
}

function exit_cleanup() {
    unblock_traffic
    remove_reload_lock
}

function cleanup_previously_blocked() {
    iptables -L -v | grep DROP | grep flags:FIN,SYN,RST,ACK/SYN | while read -r entry ; do
      port=`echo ${entry} | awk {'print $11'} | awk -F: {'print $2'}`
      iptables -w -D INPUT -p tcp --dport ${port} --syn -j DROP
    done
}

function read_haproxy_bind_ports() {
    src_config=${configuration}
    if [ -e "${configuration}.prev" ]; then
        src_config="${configuration}.prev"
    fi
    regex='^\s*bind 0\.0\.0\.0:([0-9]+)$'
    while read line
    do
        if [[ ${line} =~ $regex ]]
        then
            port="${BASH_REMATCH[1]}"
            PORTS+=(${port})
        fi
    done < "${configuration}"
}

function block_traffic() {
    # for zero downtime HAProxy reload: http://engineeringblog.yelp.com/2015/04/true-zero-downtime-haproxy-reloads.html
    # and for this implementation also: https://github.com/mesosphere/marathon-lb/blob/master/service/haproxy/run
    for i in "${PORTS[@]}"; do
      iptables -w -I INPUT -p tcp --dport ${i} --syn -j DROP
    done
}

function unblock_traffic() {
    for i in "${PORTS[@]}"; do
      iptables -w -D INPUT -p tcp --dport ${i} --syn -j DROP
    done
}

function haproxy_reload() {
    haproxy -f ${configuration}.mesos -p ${pid_file} -D -sf $(cat ${pid_file})
}

function save_configuration_file() {
    cp ${configuration} ${configuration}.prev
}

trap exit_cleanup EXIT

create_reload_lock
cleanup_previously_blocked
read_haproxy_bind_ports
python ${slave_mesos_replacer}
block_traffic
sleep 0.6
haproxy_reload
sleep 0.5
save_configuration_file
