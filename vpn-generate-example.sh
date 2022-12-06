: '
    1. Отредактировать переменные ниже:
        - "root", "server", "port", "vpn_name", "client_names", "clean" - обязательно задать свои
        - если clean установлен, происходит генерация всего с нуля, если нет - только генерируются новые (недостающие) сертификаты и конфиги, например если был добавлен новый клиент в client_names
        - если будут обнаружены клиентские сертификаты, не включённые в client_names, они будут отозваны
    2. Запустить файл vpn-generate-example.sh  двойным кликом
'

: '
    1. Customize variables below:
        - variables are important to change are: "root", "server", "port", "vpn_name", "client_names", "clean"
        - clean if set, will re-generate everything from scratch, otherwise will generate any missing items, i. e. if new client was added to client_names
        - if client certificates are detected that are nor in client_names, they will be revoked
    2. Launch file vpn-generate-example.sh by double-click
'

root="$HOME/openvpn"
proto_server="udp"
proto_client="udp"
proto_firewall="udp"
server="vpn.example.com" # Domain name or IP address of VPN server
port=443 # Desired port
subnet_local="10.10.10.0 255.255.255.0"
subnets_remote=
vpn_name="home" # Desired label of vpn server and vpn connection
client_names="mobile,notebook,laptop" # List of clients separated by comma
cn=$server
org=$server
ou=$server
country="RU"
province="Moscow"
city="Moscow"
email="user@example.com"
dn="org"
algo="RSA"
digest="SHA256"
curve="secp384r1"
key_size=2048
expire=3650
clean=

root="$root" \
proto_server="$proto_server" \
proto_client="$proto_client" \
proto_firewall="$proto_firewall" \
server="$server" \
port=$port \
subnet_local="$subnet_local" \
subnets_remote="$subnets_remote" \
vpn_name="$vpn_name" \
client_names="$client_names" \
cn="$cn" \
org="$org" \
ou="$ou" \
country="$country" \
province="$province" \
city="$city" \
email="$email" \
dn="$dn" \
algo="$algo" \
digest="$digest" \
curve="$curve" \
key_size=$key_size \
expire=$expire \
clean=$clean \
./vpn-generate.sh
