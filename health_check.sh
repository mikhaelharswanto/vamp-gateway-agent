#!/usr/bin/env bash

function validate_backends() {
    down_services=`curl -s "http://127.0.0.1:1988/;csv;norefresh" | grep DOWN | wc -l`
    if [ "x$down_services" == "x0" ]; then
        echo 'true'
    else
        echo 'false'
    fi
}

if [ "x`validate_backends`" == "xfalse" ]; then
    exit -1
else
    exit 0
fi
