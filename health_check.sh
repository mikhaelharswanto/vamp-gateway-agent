#!/usr/bin/env bash

haproxy_cfg_file=/usr/local/vamp/haproxy.cfg
haproxy_cfg_mesos_file=/usr/local/vamp/haproxy.cfg.mesos
slave_mesos_replacer=/usr/local/vamp/replace_slave_mesos.py
reload_lock=/usr/local/vamp/reload.lock
reloader=/usr/local/vamp/reload.sh

function wait_reload_lock() {
    while [ -e ${reload_lock} ]; do
        echo "waiting for reload lock..."
        sleep .1
    done
}

function validate_sockets() {
    observed_nof_sockets=`ls /usr/local/vamp/*.sock | grep -iv haproxy.log.sock | wc -l`
    expected_nof_sockets=`cat ${haproxy_cfg_file} | grep bind | grep .sock | uniq | wc -l`
    if [ "x$observed_nof_sockets" == "x$expected_nof_sockets" ]; then
        echo 'true'
    else
        echo 'false'
    fi
}

wait_reload_lock
if [ "x`validate_sockets`" == "xfalse" ]; then
    exit -1
else
    exit 0
fi
