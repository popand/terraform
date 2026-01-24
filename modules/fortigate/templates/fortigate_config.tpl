config system global
    set hostname "${hostname}"
    set admin-sport 443
end

config system admin
    edit "admin"
        set password "${admin_password}"
    next
end

config system interface
    edit "port1"
        set alias "public"
        set mode dhcp
        set allowaccess ping https ssh fgfm
    next
    edit "port2"
        set alias "private"
        set mode static
        set ip ${private_ip} ${private_netmask}
        set allowaccess ping
    next
end

config vpn ipsec phase1-interface
    edit "${vpn_name}"
        set interface "port1"
        set peertype any
        set net-device disable
        set proposal aes256-sha256
        set remote-gw ${vpn_peer_ip}
        set psksecret "${vpn_psk}"
    next
end

config vpn ipsec phase2-interface
    edit "${vpn_name}-p2"
        set phase1name "${vpn_name}"
        set proposal aes256-sha256
        set src-subnet ${local_subnet}
        set dst-subnet ${remote_subnet}
    next
end

config firewall address
    edit "local-subnet"
        set subnet ${local_subnet}
    next
    edit "remote-subnet"
        set subnet ${remote_subnet}
    next
end

config firewall policy
    edit 1
        set name "vpn-outbound"
        set srcintf "port2"
        set dstintf "${vpn_name}"
        set srcaddr "local-subnet"
        set dstaddr "remote-subnet"
        set action accept
        set schedule "always"
        set service "ALL"
    next
    edit 2
        set name "vpn-inbound"
        set srcintf "${vpn_name}"
        set dstintf "port2"
        set srcaddr "remote-subnet"
        set dstaddr "local-subnet"
        set action accept
        set schedule "always"
        set service "ALL"
    next
    edit 3
        set name "outbound-nat"
        set srcintf "port2"
        set dstintf "port1"
        set srcaddr "all"
        set dstaddr "all"
        set action accept
        set schedule "always"
        set service "ALL"
        set nat enable
    next
end

config router static
    edit 1
        set dst ${remote_subnet}
        set device "${vpn_name}"
    next
end
