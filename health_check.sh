#!/usr/bin/env bash

haproxy_cfg_file=/usr/local/vamp/haproxy.cfg
haproxy_cfg_mesos_file=/usr/local/vamp/haproxy.cfg.mesos
slave_mesos_replacer=/usr/local/vamp/replace_slave_mesos.py
reloader=/usr/local/vamp/reload.sh

function validate_sockets() {
    observed_nof_sockets=`ls /usr/local/vamp/*.sock | grep -iv haproxy.log.sock | wc -l`
    expected_nof_sockets=`cat ${haproxy_cfg_file} | grep bind | grep .sock | uniq | wc -l`
    if [ "x$observed_nof_sockets" == "x$expected_nof_sockets" ]; then
        echo 'true'
    else
        echo 'false'
    fi
}

function refresh_haproxy_mesos() {
    cp ${haproxy_cfg_mesos_file} ${haproxy_cfg_mesos_file}.tmp
    python ${slave_mesos_replacer}
    if [ "x`cat ${haproxy_cfg_mesos_file}.tmp | wc -l`" != "x`cat ${haproxy_cfg_mesos_file} | wc -l`" ]; then
        ${reloader} ${haproxy_cfg_file}
    fi
    rm ${haproxy_cfg_mesos_file}.tmp
}

refresh_haproxy_mesos

if [ "x`validate_sockets`" == "xfalse" ]; then
    exit -1
else
    exit 0
fi
