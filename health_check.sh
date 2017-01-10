#!/usr/bin/env bash

function validate_sockets() {
    observed_nof_sockets=`ls /usr/local/vamp/*.sock | grep -iv haproxy.log.sock | wc -l`
    expected_nof_sockets=`cat /usr/local/vamp/haproxy.cfg | grep bind | grep .sock | uniq | wc -l`
    if [ "x$observed_nof_sockets" == "x$expected_nof_sockets" ]; then
        echo 'true'
    else
        echo 'false'
    fi
}


if [ "x`validate_sockets`" == "xfalse" ]; then
    exit -1
else
    exit 0
fi
