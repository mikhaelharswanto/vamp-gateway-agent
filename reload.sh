#!/usr/bin/env bash

configuration=$1
pid_file=/usr/local/vamp/haproxy.pid

if [ ! -e ${pid_file} ] ; then
    touch ${pid_file}
fi

function haproxy_reload() {
    haproxy -f ${configuration} -p ${pid_file} -D -st $(cat ${pid_file})
}

function validate_sockets() {
    observed_nof_sockets=`ls /usr/local/vamp/*.sock | grep -iv haproxy.log.sock | wc -l`
    expected_nof_sockets=`cat /usr/local/vamp/haproxy.cfg | grep bind | grep .sock | uniq | wc -l`
    if [ "x$observed_nof_sockets" == "x$expected_nof_sockets" ]; then
        echo 'true'
    else
        echo 'false'
    fi
}

PORTS=()

regex='^\s*bind 0\.0\.0\.0:([0-9]+)$'
while read line
do
    if [[ ${line} =~ $regex ]]
    then
        port="${BASH_REMATCH[1]}"
        PORTS+=(${port})
    fi
done < "${configuration}"

# for zero downtime HAProxy reload: http://engineeringblog.yelp.com/2015/04/true-zero-downtime-haproxy-reloads.html
# and for this implementation also: https://github.com/mesosphere/marathon-lb/blob/master/service/haproxy/run

for i in "${PORTS[@]}"; do
  iptables -w -I INPUT -p tcp --dport ${i} --syn -j DROP
done

sleep 0.1

haproxy_reload
if [ "x`validate_sockets`" == "xfalse" ]; then
    kill 1
fi

for i in "${PORTS[@]}"; do
  iptables -w -D INPUT -p tcp --dport ${i} --syn -j DROP
done

sleep 1
