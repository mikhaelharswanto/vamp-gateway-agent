#!/usr/bin/env bash

haproxy_cfg_file=/usr/local/vamp/haproxy.cfg
hosts_file=/usr/local/vamp/etc/hosts

function update_etc_hosts() {
    if [ -d "$hosts_file" ]; then
        rmdir $hosts_file
    fi
    cat $hosts_file | grep -iv .vamp > $hosts_file
    internal_lb_ip=`nslookup $INTERNAL_LB_DNS | grep Address | awk {'print $3'} | head -1`
    internal_lb_ip=${internal_lb_ip:-172.17.0.1}
    cat ${haproxy_cfg_file}.mesos | grep -i acl | grep -i host | grep port. | awk -v ip="$internal_lb_ip" '{print ip"\t"$5}' > $hosts_file
}
