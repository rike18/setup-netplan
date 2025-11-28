#!/usr/bin/python3

import ipaddress
import argparse
import yaml
import os
import subprocess
import time

def bring_iface_up(iface: str):
    try:
        subprocess.run(
            ["ip", "link", "set", iface, "up"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False
        )
    except Exception:
        pass


def get_iface_speed(iface: str) -> int | None:
    speed_path = f"/sys/class/net/{iface}/speed"
    if not os.path.isfile(speed_path):
        return None

    try:
        with open(speed_path, "r") as f:
            speed = f.read().strip()
        return int(speed)
    except Exception:
        return None


def detect_interfaces(target_speed: int, limit: int = None) -> list[str]:
    found = []

    for net in os.listdir("/sys/class/net"):
        if net == "lo":
            continue

        bring_iface_up(net)
        time.sleep(1)

        speed = get_iface_speed(net)
        if speed == target_speed:
            if net not in found:
                found.append(net)

        if limit and len(found) >= limit:
            break

    return found

parser = argparse.ArgumentParser()
parser.add_argument("--ip-address", required=True, default=None)
args = parser.parse_args()

dir = os.path.dirname(__file__)

netplan_path = "/etc/netplan/"
netplan_cfg_name = "00-installer-config.yaml"

ip = ipaddress.ip_address(args.ip_address)
best_match = ""

network_list = [
    {
        "env": "dev",
        "location": "MSK-1",
        "subnet": "10.97.1.0/24",
        "gateway": "10.97.1.1",
        "vlan": "3"
    },
    {
        "env": "dev",
        "location": "SPB-2",
        "subnet": "10.92.1.0/24",
        "gateway": "10.92.1.1",
        "vlan": "101"   
    },
    {
        "env": "prod",
        "location": "SPB-2",
        "subnet": "10.92.2.0/24",
        "gateway": "10.92.2.1",
        "vlan": "102"   
    },
    {
        "env": "prod",
        "location": "SPB-2",
        "subnet": "10.92.3.0/24",
        "gateway": "10.92.3.1",
        "vlan": "103"   
    },
    {
        "env": "prod",
        "location": "SPB-2",
        "subnet": "10.92.4.0/24",
        "gateway": "10.92.4.1",
        "vlan": "104"   
    },
    {
        "env": "prod",
        "location": "SPB-2",
        "subnet": "10.92.5.0/24",
        "gateway": "10.92.5.1",
        "vlan": "105"   
    },
    {
        "env": "prod",
        "location": "SPB-3",
        "subnet": "10.92.17.0/24",
        "gateway": "10.92.17.1",
        "vlan": "101"   
    },
    {
        "env": "prod",
        "location": "SPB-3",
        "subnet": "10.92.18.0/24",
        "gateway": "10.92.18.1",
        "vlan": "102"   
    },
    {
        "env": "prod",
        "location": "SPB-3",
        "subnet": "10.92.19.0/24",
        "gateway": "10.92.19.1",
        "vlan": "103"   
    },   
    {
        "env": "prod",
        "location": "SPB-3",
        "subnet": "10.92.20.0/24",
        "gateway": "10.92.20.1",
        "vlan": "104"   
    },  
    {
        "env": "prod",
        "location": "SPB-3",
        "subnet": "10.92.21.0/24",
        "gateway": "10.92.21.1",
        "vlan": "105"   
    },   
    {
        "env": "prod",
        "location": "SPB-5",
        "subnet": "10.92.33.0/24",
        "gateway": "10.92.33.1",
        "vlan": "101"   
    },  
    {
        "env": "prod",
        "location": "SPB-5",
        "subnet": "10.92.34.0/24",
        "gateway": "10.92.34.1",
        "vlan": "102"   
    }, 
    {
        "env": "prod",
        "location": "SPB-5",
        "subnet": "10.92.35.0/24",
        "gateway": "10.92.35.1",
        "vlan": "103"   
    },     
    {
        "env": "prod",
        "location": "SPB-5",
        "subnet": "10.92.36.0/24",
        "gateway": "10.92.36.1",
        "vlan": "104"   
    },      
    {
        "env": "prod",
        "location": "SPB-5",
        "subnet": "10.92.37.0/24",
        "gateway": "10.92.37.1",
        "vlan": "105"   
    },
]

subnets = [ipaddress.ip_network(i["subnet"]) for i in network_list]
matches = [net for net in subnets if ip in net]

if matches:
    # Longest Prefix Match
    best_match = max(matches, key=lambda n: n.prefixlen)

for i in network_list:
    if i["subnet"] == str(best_match):
        ip_gateway = i["gateway"]
        vlan = int(i["vlan"])


iface = detect_interfaces(10000, limit=2)

if len(iface) == 2:
    interfaces = iface
else:
    interfaces = detect_interfaces(1000)

print("Detected interfaces:", interfaces)

config_json = {
    "network": {
        "version": 2,
        "renderer": "networkd",
        "ethernets": {
            interfaces[0]: {},
            interfaces[1]: {}
        },
        "bonds": {
            "bond0": {
                "interfaces": interfaces,
                "parameters": {
                    "mode": "802.3ad",
                    "mii-monitor-interval": 1,
                    "lacp-rate": "fast"
                }
            }
        },
        "vlans": {
            f"bond0.{vlan}": {
                "id": vlan,
                "link": "bond0",
                "addresses": [f"{ip}/24"],
                "nameservers": {
                    "addresses": ["8.8.8.8"]
                },
                "routes": [
                    {
                    "to": "default",
                    "via": ip_gateway
                    }
                ]
            }
        }
    }
}
config_yaml = yaml.dump(config_json, sort_keys=False)

if not os.path.exists(netplan_path):
    os.makedirs(netplan_path)

with open(os.path.join(netplan_path, netplan_cfg_name),"w") as f:
    f.write(config_yaml)    
    f.close
