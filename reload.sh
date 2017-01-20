#!/usr/bin/env bash

configuration=$1
pid_file=/usr/local/vamp/haproxy.pid
slave_mesos_replacer=/usr/local/vamp/replace_slave_mesos.py

PORTS=()

if [ ! -e ${pid_file} ] ; then
    touch ${pid_file}
fi

function cleanup_previously_blocked() {
    iptables -L -v | grep DROP | grep flags:FIN,SYN,RST,ACK/SYN | while read -r entry ; do
      port=`echo ${entry} | awk {'print $11'} | awk -F: {'print $2'}`
      iptables -w -D INPUT -p tcp --dport ${port} --syn -j DROP
    done
}

function read_haproxy_bind_ports() {
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
    python ${slave_mesos_replacer}
    haproxy -f ${configuration}.mesos -p ${pid_file} -D -st $(cat ${pid_file})
}

trap unblock_traffic EXIT

cleanup_previously_blocked
read_haproxy_bind_ports
block_traffic
sleep 0.1
haproxy_reload
sleep 1
