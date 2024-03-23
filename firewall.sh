#!/bin/bash

# Variaveis locais
ext="eno1"                 # Interface da rede externa
int="enp3s0"               # Interface da rede interna
lnet="192.168.15.0/24"     # endereço da rede local
server="192.168.15.254"    # endereço do servidor


#==  Funcoes para definicao de regras ======================================================#


local(){
    # Funcao para configuracao das regras de firewall para comunicacao local

    # Libera todo o trafego da lo
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A OUTPUT -o lo -j ACCEPT

    # Permite trafego nas portas (80, 443, 53, 123)
        iptables -A INPUT -i $ext -p tcp -m multiport --sports 80,443 -j ACCEPT
        iptables -A INPUT -p udp -m multiport --sports 53,123 -j ACCEPT
        iptables -A OUTPUT -o $ext -p tcp -m multiport --dports 80,443 -j ACCEPT
        iptables -A OUTPUT -p udp -m multiport --dports 53,123 -j ACCEPT

   # Regras DNS e HTTP adicionais
        iptables -A INPUT -d $server -p tcp --sport 80 -j ACCEPT
        iptables -A INPUT -d $server -p tcp --sport 53 -j ACCEPT
        iptables -A INPUT -d $server -p udp --sport 53 -j ACCEPT

        iptables -A INPUT -p udp --dport 53 -j ACCEPT
        iptables -A INPUT -p tcp --dport 53 -j ACCEPT
        iptables -A OUTPUT -p udp --sport 53 -j ACCEPT
        iptables -A OUTPUT -p tcp --sport 53 -j ACCEPT

    # Multicast (5353)
        iptables -A INPUT -p tcp --dport 5353 -j ACCEPT
        iptables -A INPUT -p udp --dport 5353 -j ACCEPT

        iptables -A INPUT -i $ext -d 224.0.0.0/4 -j ACCEPT
        iptables -A OUTPUT -o $ext -d 224.0.0.0/4 -j ACCEPT

        
    # Libera o trafego DHCP
        iptables -A INPUT -p udp --dport 68 -j ACCEPT
        iptables -A OUTPUT -p udp --sport 68 -j ACCEPT
        iptables -A INPUT -p udp --dport 67 -j ACCEPT
        iptables -A OUTPUT -p udp --sport 67 -j ACCEPT

    # Permitir tráfego ICMP de entrada e saída
        iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 5/s -j ACCEPT
        iptables -A OUTPUT -p icmp --icmp-type echo-reply -j ACCEPT
        # Descartar tráfego ICMP de entrada e saída além das regras permitidas acima
        iptables -A INPUT -p icmp -j DROP
        iptables -A OUTPUT -p icmp -j DROP

    # Libera o trafego TCP do Squid (3128)
        iptables -A INPUT -i $int -p tcp --dport 3128 -j ACCEPT
        iptables -A OUTPUT -o $int -p tcp --sport 3128 -j ACCEPT

    # libera total acesso a porta SSH (22)
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A OUTPUT -p tcp --sport 22 -j ACCEPT

    # Libera trafego nas portas do Samba (135, 137, 138, 139 e 445)
        sambaports="135,137,138,139,445"
        iptables -A INPUT -s $lnet -p tcp -m multiport --dports $sambaports -j ACCEPT
        iptables -A INPUT -s $lnet -p udp -m multiport --sports $sambaports -j ACCEPT
        iptables -A OUTPUT -s $lnet -p tcp -m multiport --sports $sambaports -j ACCEPT
        iptables -A OUTPUT -s $lnet -p udp -m multiport --sports $sambaports -j ACCEPT

    # Permite portas para o funcionamento do samba-ad-dc
        samba_ad_dc_tcp="88,135,139,389,445,464,636,1024:5000,49152:65535,3268,3269,5353"
        samba_ad_dc_udp="88,137,138,389,5353"
        iptables -A INPUT -s $lnet -p tcp -m multiport --dports $samba_ad_dc_tcp -j ACCEPT
        iptables -A INPUT -s $lnet -p udp -m multiport --dports $samba_ad_dc_udp -j ACCEPT
        iptables -A OUTPUT -d $lnet -p tcp -m multiport --sports $samba_ad_dc_tcp -j ACCEPT
        iptables -A OUTPUT -d $lnet -p udp -m multiport --sports $samba_ad_dc_udp -j ACCEPT

        iptables -A OUTPUT -p udp --sport 389 -j ACCEPT

    # Regras para permitir conexões relacionadas e estabelecidas
        iptables -A INPUT -p tcp -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A OUTPUT -p tcp -m state --state ESTABLISHED,RELATED -j ACCEPT
}


forward(){
    # Funcao para encaminhamento de trafego entre WAN e LAN

    # Libera o trafego entre a INTERNET e a REDE LOCAL
        iptables -A FORWARD -i $ext -p tcp -m multiport --sports 80,443 -d $lnet -j ACCEPT
        iptables -A FORWARD -i $ext -p udp -m multiport --sports 53,123 -d $lnet -j ACCEPT
        iptables -A FORWARD -i $int -p tcp -m multiport --dports 80,443 -s $lnet -j ACCEPT
        iptables -A FORWARD -i $int -p udp -m multiport --dports 53,123 -s $lnet -j ACCEPT

    # Libera o ping entre a INTERNET e a REDE LOCAL
        iptables -A FORWARD -i $int -p icmp --icmp-type 8 -s $lnet -j ACCEPT
        iptables -A FORWARD -o $int -p icmp --icmp-type 0 -d $lnet -j ACCEPT
        iptables -A FORWARD -i $ext -p icmp --icmp-type 0 -d $lnet -j ACCEPT
        iptables -A FORWARD -o $ext -p icmp --icmp-type 8 -s $lnet -j ACCEPT

    # Permitir tráfego ICMP de encaminhamento necessários para o funcionamento normal
        iptables -A FORWARD -p icmp --icmp-type echo-request -m limit --limit 10/s -j ACCEPT
        iptables -A FORWARD -p icmp --icmp-type echo-reply -m limit --limit 10/s -j ACCEPT
        # Descartar tráfego ICMP de encaminhamento além das regras permitidas acima
        iptables -A FORWARD -p icmp -j DROP
}

internet(){
    # Funcao para habilitar o compartilhamento da internet entre as redes

    # Habilita o encaminhamento de IP
    sysctl -w net.ipv4.ip_forward=1

    # Configura NAT para o trafego da LAN para a Internet
    iptables -t nat -A POSTROUTING -s $lnet -o $ext -j MASQUERADE

    # Direcionar navegacao na porta HTTP (80) para a porta do proxy/squid (3128)
    iptables -t nat -A PREROUTING -i $int -p tcp --dport 80 -j REDIRECT --to-port 3128
}


#==  Funcoes de controle  ==================================================================#

default() {
    iptables -N LOGGING
    iptables -A LOGGING -m limit --limit 5/min -j LOG --log-prefix "iptables-denied: " --log-level 7
    iptables -A LOGGING -j DROP

    iptables -A INPUT -j LOGGING
    iptables -A OUTPUT -j LOGGING
    iptables -A FORWARD -j LOGGING

    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
}

iniciar(){
    # Funcao para iniciar o firewall
    local
    forward
    internet
    default
}

parar(){
    # Funcao para parar o firewall
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -F
    iptables -X
}

#==  Script para controle do firewall  =====================================================#


case $1 in
    start|Start|START)iniciar;;
    stop|Stop|STOP)parar;;
    restart|Restart|RESTART)parar;iniciar;;
    ls|listar|list)iptables -nvL;;
    vi|conf)sudo vi /usr/local/sbin/firewall.sh;;
    *)echo "usage:
    firewall.sh [start|stop|restart|list|vi]";;
esac
