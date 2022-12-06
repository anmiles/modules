_auth=/etc/openvpn/auth.txt
_config=/etc/openvpn/server
_client=$root/client
_easy_rsa=$root/easy-rsa

_pki=$_easy_rsa/pki
_certs=$_pki/certs_by_serial
_issued=$_pki/issued
_private=$_pki/private
_renewed=$_pki/renewed
_reqs=$_pki/reqs
_revoked=$_pki/revoked

_extensions_client=$_easy_rsa/x509-types/client
_extensions_server=$_easy_rsa/x509-types/server
_cnf=$_easy_rsa/openssl-easyrsa.cnf

export EASYRSA_PKI=$_pki
export PKCS11_MODULE_PATH=dummy
export PKCS11_PIN=dummy

export EASYRSA_REQ_CN=$cn
export EASYRSA_REQ_ORG=$org
export EASYRSA_REQ_OU=$ou
export EASYRSA_REQ_COUNTRY=$country
export EASYRSA_REQ_PROVINCE=$province
export EASYRSA_REQ_CITY=$city
export EASYRSA_REQ_EMAIL=$email

export EASYRSA_DN=$dn
export EASYRSA_ALGO=$algo
export EASYRSA_DIGEST=$digest
export EASYRSA_CURVE=$curve
export EASYRSA_KEY_SIZE=$key_size
export EASYRSA_CA_EXPIRE=$expire
export EASYRSA_CERT_EXPIRE=$expire
export EASYRSA_CRL_DAYS=$expire

subject="/C=$country/ST=$province/L=$city/O=$org/OU=$ou/CN"
client_names_array=$(echo $client_names | tr "," "\n")

GetServerPassword() {
	GetPassword "VPN server password"
}

GetClientPassword() {
	GetPassword "VPN client password ($1)"
}

GetPassword() {
	min_length=4
	max_length=1023
	password=

	while [ ${#password} -lt $min_length ] || [ ${#password} -gt $max_length ]; do
		Ask "Enter $1 ($min_length ... $max_length characters): "
		read -s password
		echo "" >&2
	done

	echo $password
}

EmbedKey() {
	name=$1
	file=$2
	echo -e "<$name>\n$(cat $file)\n</$name>"
}

GenerateCert() {
	name=$1
	extfile=$2
	cert_password=$3
	[ -z "$cert_password" ] && cert_password=$vpn_server_password
	ca_password=$vpn_server_password

	openssl req -passout "pass:$cert_password" -utf8 -new -newkey rsa:2048 -keyout $_private/$name.key -out $_reqs/$name.req -config $_cnf -subj "$subject=$name"
	openssl ca -days $expire -passin "pass:$ca_password" -utf8 -batch -in $_reqs/$name.req -out $_issued/$name.crt -extfile $extfile -config $_cnf
}

Ask() {
	echo -en "\e[33;1m$1\e[0m" >&2
}

Out() {
	echo -e "\e[32;1m$1\e[0m" >&2
}

for package in openvpn easy-rsa; do
	dpkg -s $package > /dev/null || (Out "Installing $package..." && sudo apt install -y $package);
done

Out "Starting..."

if [ ! -d $root ]; then
	mkdir $root
fi

if [ ! -d $_easy_rsa ]; then
	mkdir $_easy_rsa
	ln -s /usr/share/easy-rsa/* $_easy_rsa
	sudo chmod 700 $_easy_rsa
fi

if [ $clean ]; then
	[ -d $_pki ] && rm -rf $_pki
	[ -d $_client ] && rm -rf $_client
fi

if [ ! -d $_client ]; then
	mkdir $_client
	sudo chmod 700 $_client
fi

[ -d $_pki ] || mkdir $_pki
[ -d $_certs ] || mkdir $_certs
[ -d $_issued ] || mkdir $_issued
[ -d $_private ] || mkdir $_private
[ -d $_renewed ] || mkdir $_renewed
[ -d $_reqs ] || mkdir $_reqs
[ -d $_revoked ] || mkdir $_revoked

if [ ! -f $_pki/index.txt ]; then
	if [ -f $_easy_rsa/index.txt.start ]; then
		cp $_easy_rsa/index.txt.start $_pki/index.txt
	else
		touch $_pki/index.txt
	fi
fi

if [ ! -f $_pki/serial ]; then
	if [ -f $_easy_rsa/serial.start ]; then
		cp $_easy_rsa/serial.start $_pki/serial
	else
		echo "01" > $_pki/serial
	fi
fi

Out "Getting server password..."
vpn_server_password=$(GetServerPassword)
sudo touch $_auth
sudo chmod 600 $_auth
echo $vpn_server_password | sudo tee $_auth > /dev/null

if [ ! -f $_private/ta.key ]; then
	Out "Generating static key..."
	openvpn --genkey --secret $_private/ta.key
fi

if [ ! -f $_pki/ca.crt ]; then
	Out "Generating CA certificate..."
	openssl genrsa -out $_private/ca.key -aes256 -passout "pass:$vpn_server_password" $key_size
	dd if=/dev/urandom of=$_pki/.rnd bs=256 count=1
	openssl req -days $expire -passin "pass:$vpn_server_password" -new -utf8 -x509 -key $_private/ca.key -keyout $_private/ca.key -out $_pki/ca.crt -config $_cnf -subj "$subject=$cn"
fi

if [ ! -f $_issued/$vpn_name.crt ]; then
	Out "Generating server certificate [$vpn_name]..."
	altNameType="DNS"
	[[ $cn =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && altNameType="IP"
	_extensions_server_tmp=$_pki/extensions.server.tmp
	cp $_extensions_server $_extensions_server_tmp
	echo "subjectAltName = $altNameType:$cn" >> $_extensions_server_tmp
	GenerateCert $vpn_name $_extensions_server_tmp
	rm $_extensions_server_tmp
fi

for client_name in $client_names_array; do
	if [ ! -f $_issued/$client_name.crt ]; then
		Out "Generating client certificate [$client_name]..."
		vpn_client_password=$(GetClientPassword $client_name)
		GenerateCert $client_name $_extensions_client $vpn_client_password
	fi
done

if [ ! -f $_pki/crl.pem ]; then
	Out "Generating revoke file..."
	openssl ca -gencrl -crldays $expire -utf8 -out $_pki/crl.pem -passin "pass:$vpn_server_password" -config $_cnf

	if [ ! -f $_issued/revoke.crt ]; then
		Out "Generating revoked certificate..."
		revoke_password="password"
		GenerateCert revoke $_extensions_client $revoke_password
	fi
fi

for cert_name in $(find $_issued/*.crt -type f -exec basename {} .crt \;); do
	if [[ "$vpn_name" == "$cert_name" ]]; then continue; fi
	if [[ "${client_names_array[*]}" =~ "${cert_name}" ]]; then continue; fi
	Out "Revoke certificate [$cert_name]..."
	openssl ca -revoke $_issued/$cert_name.crt -passin "pass:$vpn_server_password" -config $_cnf
	cat $_pki/ca.crt $_pki/crl.pem > $_pki/$cert_name.revoke.pem
	openssl verify -CAfile $_pki/$cert_name.revoke.pem -crl_check $_issued/$cert_name.crt
	rm $_pki/$cert_name.revoke.pem
	mv $_issued/$cert_name.crt $_revoked
done

Out "Generating server config..."
config=()
config+=("tls-server")
config+=("dev tun")
config+=("proto $proto_server")
config+=("server $subnet_local")
config+=("port $port")
config+=("persist-key")
config+=("persist-tun")
config+=("tun-mtu 1500")
config+=("mssfix")
config+=("cipher AES-256-GCM")
config+=("auth $digest")
config+=("auth-nocache")
config+=("dh none")
config+=("verb 3")
config+=("mute 10")
config+=("topology subnet")
[[ "$proto_server" =~ "udp" ]] && config+=("explicit-exit-notify 1")
config+=("keepalive 10 60")
config+=("max-clients 10")
config+=("user nobody")
config+=("group nogroup")
config+=("askpass $_auth")
config+=("ifconfig-pool-persist /var/log/openvpn/ipp.txt")
if [[ ! -z "$subnets_remote" ]]; then
	for subnet in $(echo $subnets_remote | tr "," "\n"); do
		config+=("push \"route {}\"");
	done
fi
config+=("$(EmbedKey "ca" "$_pki/ca.crt")")
config+=("$(EmbedKey "cert" "$_issued/$vpn_name.crt")")
config+=("$(EmbedKey "key" "$_private/$vpn_name.key")")
config+=("$(EmbedKey "tls-crypt" "$_private/ta.key")")
config+=("$(EmbedKey "crl-verify" "$_pki/crl.pem")")
printf "%s\n" "${config[@]}" | sudo tee $_config/$vpn_name.conf > /dev/null

for client_name in $client_names_array; do
	Out "Generating client config [$client_name]..."
	mkdir -p "$_client/$client_name"
	config=()
	config+=("client")
	config+=("tls-client")
	config+=("dev tun")
	config+=("proto $proto_client")
	config+=("remote $server $port")
	config+=("persist-key")
	config+=("persist-tun")
	config+=("tun-mtu 1500")
	config+=("mssfix")
	config+=("cipher AES-256-GCM")
	config+=("auth $digest")
	config+=("auth-nocache")
	config+=("verb 3")
	config+=("mute 10")
	config+=("dhcp-option DNS 8.8.8.8")
	config+=("dhcp-option DNS 8.8.4.4")
	config+=("redirect-gateway def1 bypass-dhcp")
	config+=("nobind")
	config+=("route-delay 3")
	config+=("script-security 2")
	config+=("remote-cert-tls server")
	config+=("mute-replay-warnings")
	config+=("resolv-retry infinite")
	config+=("ping 10")
	config+=("ping-restart 60")
	config+=("$(EmbedKey "ca" "$_pki/ca.crt")")
	config+=("$(EmbedKey "cert" "$_issued/$client_name.crt")")
	config+=("$(EmbedKey "key" "$_private/$client_name.key")")
	config+=("$(EmbedKey "tls-crypt" "$_private/ta.key")")
	config_filename=$_client/$client_name/$vpn_name.ovpn
	touch $config_filename
	sudo chmod 700 $config_filename
	printf "%s\n" "${config[@]}" | tee $config_filename > /dev/null
	echo -e "\t$config_filename"
done

Out "Updating firewall rule..."
sudo sed -i -e 's/.*net.ipv4.ip_forward.*/net.ipv4.ip_forward=1/' /etc/sysctl.conf
sudo sysctl -p
default_interface=$(route | grep '^default' | grep -o '[^ ]*$')
gateway=$(echo $subnet_local | awk '{print $1}')
netmask=$(echo $subnet_local | awk '{print $2}')
prefix=0
x=0$( printf '%o' ${netmask//./ } )
while [ $x -gt 0 ]; do let prefix+=$((x % 2)) 'x>>=1'; done
cidr=$gateway/$prefix
sudo grep --quiet "#openvpn" /etc/ufw/before.rules || sudo sed -i -e "1i #openvpn\n*nat\n:POSTROUTING ACCEPT [0:0]\n-A POSTROUTING -s $cidr -o $default_interface -j MASQUERADE\nCOMMIT\n" /etc/ufw/before.rules
sudo sed -i -e 's/.*DEFAULT_FORWARD_POLICY.*/DEFAULT_FORWARD_POLICY="ACCEPT"/' /etc/default/ufw
sudo ufw allow $port/$proto_firewall
if sudo ufw status | grep "Status: active"; then
	sudo ufw disable
	sudo ufw --force enable
else
	Ask "Firewall was disabled. Please review firewall rules below and make sure that your current SSH port is allowed. Otherwise don't enable firewall to not lost your ssh connection forever:"
	echo ""
	sudo ufw show added
	Ask "Do you want to enable it (yes/no)? "
	read answer
	echo ""
	if [[ "$answer" == "yes" ]]; then
		sudo ufw --force enable
	else
		echo "Firewall is not enabled"
	fi
fi

Out "Starting service..."
sudo systemctl -f enable openvpn-server@$vpn_name.service
sudo systemctl restart openvpn-server@$vpn_name.service
sleep 1
sudo systemctl status openvpn-server@$vpn_name.service

Out "Done!"
