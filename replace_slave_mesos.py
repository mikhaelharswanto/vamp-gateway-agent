import os
import socket
import subprocess
from tempfile import NamedTemporaryFile

HAPRXOY_CFG_FILE = '/usr/local/vamp/haproxy.cfg'
HAPRXOY_CFG_MESOS_FILE = '/usr/local/vamp/haproxy.cfg.mesos'
HAPRXOY_CFG_ERROR_FILE = '/usr/local/vamp/haproxy.cfg.error'
HAPROXY_VALIDATE_SCRIPT = '/usr/local/vamp/validate.sh'


def get_slave_mesos_ip_addresses():
    return socket.gethostbyname_ex('slave.mesos')[2]


def replace_slave_mesos_hostname_with_ip(haproxy_cfg_file, ip_addresses, host_keyword='slave.mesos'):
    def process_rule_with_ip(idx, ip_address, weight):
        replaced = rule_line.replace(host_keyword, ip_address)
        if 'weight' not in replaced:
            replaced = '%s weight %s' % (replaced, weight)
        split = replaced.split(' ')
        server_id_idx = 3
        split[server_id_idx] = '%s-%s' % (split[server_id_idx], idx)
        return ' '.join(split)

    output = []
    with open(haproxy_cfg_file, 'r') as haproxycfg:
        for rule_line in haproxycfg:
            rule_line = rule_line.rstrip()
            if host_keyword not in rule_line:
                output.append(rule_line)
                continue

            output.append(process_rule_with_ip(0, '127.0.0.1', 99))
            for idx, ip in enumerate(ip_addresses):
                output.append(process_rule_with_ip(idx + 1, ip, 1))
    return output


def validate_cfg(haproxy_cfg_file):
    return subprocess.call([HAPROXY_VALIDATE_SCRIPT, haproxy_cfg_file]) == 0


def write_to_temp_file(lines):
    haproxy_cfg_temp = NamedTemporaryFile(delete=False)
    with open(haproxy_cfg_temp.name, 'w') as outputcfg:
        for line in lines:
            outputcfg.write(line + '\n')
    return haproxy_cfg_temp


if __name__ == '__main__':
    ip_addresses = get_slave_mesos_ip_addresses()
    output_lines = replace_slave_mesos_hostname_with_ip(HAPRXOY_CFG_FILE, ip_addresses)
    temp_file = write_to_temp_file(output_lines)
    if validate_cfg(temp_file.name):
        subprocess.call(['cp', temp_file.name, HAPRXOY_CFG_MESOS_FILE])
    else:
        subprocess.call(['cp', temp_file.name, HAPRXOY_CFG_ERROR_FILE])
    os.unlink(temp_file.name)
