# Tested with OpenVPN v2.5.7

Function Generate-VPN {
    Param (
        [string]$root = "D:/openvpn",

        [string]$proto_server = "tcp4",
        [string]$proto_client = "tcp4",
        [string]$proto_firewall = "TCP",
        [Parameter(Mandatory = $true)][string]$server, # "vpn.example.com"
        [string]$port = "443",
        [string]$subnet_local, # "10.10.0.0 255.255.255.0"
        [string[]]$subnets_remote = @(), # @("10.10.10.0 255.255.255.0")

        [Parameter(Mandatory = $true)][string]$vpn_name, # "home"
        [Parameter(Mandatory = $true)][string[]]$client_names, # @("mobile", "notebook", "laptop")

        [Parameter(Mandatory = $true)][string]$cn, # $server
        [Parameter(Mandatory = $true)][string]$org, # $server
        [Parameter(Mandatory = $true)][string]$ou, # $server
        [Parameter(Mandatory = $true)][string]$country, # "RU"
        [Parameter(Mandatory = $true)][string]$province, # "MO"
        [Parameter(Mandatory = $true)][string]$city, # "Moscow"
        [Parameter(Mandatory = $true)][string]$email, # "user@example.com"

        [string]$dn = "org",
        [string]$algo = "RSA",
        [string]$digest = "SHA256",
        [string]$curve = "secp384r1",
        [int]$key_size = 2048,
        [int]$expire = 3650,

        [switch]$clean
    )

    $_bin = "$root/bin"
    $_config = "$root/config"
    $_client = "$root/client"
    $_easy_rsa = "$root/easy-rsa"

    $_pki = "$_easy_rsa/pki"
    $_certs = "$_pki/certs_by_serial"
    $_issued = "$_pki/issued"
    $_private = "$_pki/private"
    $_renewed = "$_pki/renewed"
    $_reqs = "$_pki/reqs"
    $_revoked = "$_pki/revoked"

    $_extensions_client = "$_easy_rsa/x509-types/client"
    $_extensions_server = "$_easy_rsa/x509-types/server"
    $_cnf = (Get-Item $_easy_rsa/openssl-*.cnf).FullName

    [Environment]::SetEnvironmentVariable("EASYRSA_PKI", $_pki, "Process")
    [Environment]::SetEnvironmentVariable("PKCS11_MODULE_PATH", "dummy", "Process")
    [Environment]::SetEnvironmentVariable("PKCS11_PIN", "dummy", "Process")

    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_CN", $cn, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_ORG", $org, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_OU", $ou, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_COUNTRY", $country, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_PROVINCE", $province, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_CITY", $city, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_REQ_EMAIL", $email, "Process")

    [Environment]::SetEnvironmentVariable("EASYRSA_DN", $dn, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_ALGO", $algo, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_DIGEST", $digest, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_CURVE", $curve, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_KEY_SIZE", $key_size, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_CA_EXPIRE", $expire, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_CERT_EXPIRE", $expire, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_CRL_DAYS", $expire, "Process")

    $subject = "/C=$country/ST=$province/L=$city/O=$org/OU=$ou/CN"
    $utf8 = New-Object System.Text.UTF8Encoding $false

    Function GetServerPassword {
        return GetPassword "VPN server password"
    }

    Function GetClientPassword($client_name) {
        return GetPassword "VPN client password ($client_name)"
    }

    Function GetPassword($title) {
        $min_length = 4
        $max_length = 1023
        $password = ""

        while ($password.Length -lt $min_length -or $password.Length -gt $max_length) {
            $password = ReadPassword -prompt "Enter $title ($min_length ... $max_length characters)"
        }

        return $password
    }

    Function ReadPassword ($prompt) {
        Write-Host $prompt": " -ForegroundColor Yellow -NoNewline
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host -AsSecureString)))
    }

    Function EmbedKey($name, $file) {
        $content = (Get-Content $file) -join "`n"
        return @("<$name>", $content, "</$name>")
    }

    Function GenerateCert ($name, $extfile, $cert_password) {
        $ca_password = $vpn_server_password
        if (!$cert_password) { $cert_password = $vpn_server_password }
        & $_bin/openssl req -passout "pass:$cert_password" -utf8 -new -newkey rsa:2048 -keyout $_private/$name.key -out $_reqs/$name.req -config $_cnf -subj "$subject=$name"
        & $_bin/openssl ca -days $expire -passin "pass:$ca_password" -utf8 -batch -in $_reqs/$name.req -out $_issued/$name.crt -extfile $extfile -config $_cnf
    }

    Write-Host "Starting..." -ForegroundColor Green

    $vpn_server_password = GetServerPassword

    if ($clean) {
        if (Test-Path $_pki) { Remove-Item $_pki -Recurse -Force }
        if (Test-Path $_client) { Remove-Item $_client -Recurse -Force }
    }

    if (!(Test-Path $_pki)) { New-Item $_pki -Type Directory | Out-Null }
    if (!(Test-Path $_certs)) { New-Item $_certs -Type Directory | Out-Null }
    if (!(Test-Path $_issued)) { New-Item $_issued -Type Directory | Out-Null }
    if (!(Test-Path $_private)) { New-Item $_private -Type Directory | Out-Null }
    if (!(Test-Path $_renewed)) { New-Item $_renewed -Type Directory | Out-Null }
    if (!(Test-Path $_reqs)) { New-Item $_reqs -Type Directory | Out-Null }
    if (!(Test-Path $_revoked)) { New-Item $_revoked -Type Directory | Out-Null }
    if (!(Test-Path $_config)) { New-Item $_config -Type Directory | Out-Null }
    if (!(Test-Path $_client)) { New-Item $_client -Type Directory | Out-Null }

    if (!(Test-Path $_pki/index.txt)) {
        if (Test-Path $_easy_rsa/index.txt.start) { Copy-Item $_easy_rsa/index.txt.start $_pki/index.txt }
        else { [System.IO.File]::WriteAllText("$_pki/index.txt", "", $utf8) }
    }

    if (!(Test-Path $_pki/serial)) {
        if (Test-Path $_easy_rsa/serial.start) { Copy-Item $_easy_rsa/serial.start $_pki/serial }
        else { [System.IO.File]::WriteAllText("$_pki/serial", "01", $utf8) }
    }

    if (!(Test-Path $_private/ta.key)) {
        Write-Host "Generating static key..." -ForegroundColor Green
        & $_bin/openvpn --genkey secret $_private/ta.key
    }

    if (!(Test-Path $_pki/ca.crt)) {
        Write-Host "Generating CA certificate..." -ForegroundColor Green
        & $_bin/openssl genrsa -out $_private/ca.key -aes256 -passout "pass:$vpn_server_password" $key_size
        & $_bin/openssl req -days $expire -passin "pass:$vpn_server_password" -new -utf8 -x509 -key $_private/ca.key -keyout $_private/ca.key -out $_pki/ca.crt -config $_cnf -subj "$subject=$cn"
    }

    if (!(Test-Path $_issued/$vpn_name.crt)) {
        Write-Host "Generating server certificate [$vpn_name]..." -ForegroundColor Green
        $altNameType = "DNS"
        if ($cn -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $altNameType = "IP" }
        $_extensions_server_tmp = "$_pki/extensions.server.tmp"
        Copy-Item $_extensions_server $_extensions_server_tmp
        [System.IO.File]::AppendAllText($_extensions_server_tmp, "subjectAltName = $($altNameType):$cn", $utf8)
        GenerateCert -name $vpn_name -extfile $_extensions_server_tmp
        Remove-Item $_extensions_server_tmp
    }

    $client_names | ? { !(Test-Path $_issued/$_.crt) } | % {
        $client_name = $_
        Write-Host "Generating client certificate [$client_name]..." -ForegroundColor Green
        $vpn_client_password = GetClientPassword $client_name
        GenerateCert -name $client_name -extfile $_extensions_client -cert_password $vpn_client_password
    }

    if (!(Test-Path $_pki/crl.pem)) {
        Write-Host "Generating revoke file..." -ForegroundColor Green
        & $_bin/openssl ca -gencrl -crldays $expire -utf8 -out $_pki/crl.pem -passin "pass:$vpn_server_password" -config $_cnf

        if (!(Test-Path $_issued/revoke.crt)) {
            Write-Host "Generating revoked certificate..." -ForegroundColor Green
            $revoke_password = "password"
            GenerateCert -name revoke -extfile $_extensions_client -cert_password $revoke_password
        }
    }

    Get-ChildItem $_issued/*.crt | % { $_.Name -replace '\.crt$', ''} | % {
        $cert_name = $_
        if ($vpn_name -eq $cert_name) { return }
        if ($client_names.Contains($cert_name)) { return }
        Write-Host "Revoke certificate [$cert_name]..." -ForegroundColor Green
        & $_bin/openssl ca -revoke $_issued/$_.crt -passin "pass:$vpn_server_password" -config $_cnf
        Get-Content $_pki/ca.crt, $_pki/crl.pem | Set-Content $_pki/$cert_name.revoke.pem
        & $_bin/openssl verify -CAfile $_pki/$cert_name.revoke.pem -crl_check $_issued/$cert_name.crt
        Remove-Item $_pki/$cert_name.revoke.pem
        Move-Item $_issued/$cert_name.crt $_revoked
    }

    Write-Host "Generating server config..." -ForegroundColor Green
    $config = @()
    $config += "tls-server"
    $config += "dev tun"
    $config += "proto $proto_server"
    $config += "server $subnet_local"
    $config += "port $port"
    $config += "persist-key"
    $config += "persist-tun"
    $config += "tun-mtu 1500"
    $config += "mssfix"
    $config += "cipher AES-256-GCM"
    $config += "auth $digest"
    $config += "auth-nocache"
    $config += "dh none"
    $config += "verb 3"
    $config += "mute 10"
    $config += "topology subnet"
    if ($proto_server -match "udp") { $config += "explicit-exit-notify 1" }
    $config += "keepalive 10 60"
    $config += "max-clients 10"
    $config += "status status.log"
    $config += "log openvpn.log"
    if ($subnets_remote) {
        $config += $subnets_remote | % { "push `"route $_`"" }
    }
    $config += EmbedKey -name "ca" -file "$_pki/ca.crt"
    $config += EmbedKey -name "cert" -file "$_issued/$vpn_name.crt"
    $config += EmbedKey -name "key" -file "$_private/$vpn_name.key"
    $config += EmbedKey -name "tls-crypt" -file "$_private/ta.key"
    $config += EmbedKey -name "crl-verify" -file "$_pki/crl.pem"
    [System.IO.File]::WriteAllText("$_config/$vpn_name.ovpn", ($config -join "`n"), $utf8)

    $client_names | % {
        $client_name = $_
        Write-Host "Generating client config [$client_name]..." -ForegroundColor Green
        New-Item -Type Directory -Force "$_client/$client_name" | Out-Null
        $config = @()
        $config += "client"
        $config += "tls-client"
        $config += "dev tun"
        $config += "proto $proto_client"
        $config += "remote $server $port"
        $config += "persist-key"
        $config += "persist-tun"
        $config += "tun-mtu 1500"
        $config += "mssfix"
        $config += "cipher AES-256-GCM"
        $config += "auth $digest"
        $config += "auth-nocache"
        $config += "verb 3"
        $config += "mute 10"
        $config += "dhcp-option DNS 8.8.8.8"
        $config += "dhcp-option DNS 8.8.4.4"
        $config += "route-delay 3"
        $config += "script-security 2"
        $config += "remote-cert-tls server"
        $config += "mute-replay-warnings"
        $config += "resolv-retry infinite"
        $config += "ping 10"
        $config += "ping-restart 60"
        $config += EmbedKey -name "ca" -file "$_pki/ca.crt"
        $config += EmbedKey -name "cert" -file "$_issued/$client_name.crt"
        $config += EmbedKey -name "key" -file "$_private/$client_name.key"
        $config += EmbedKey -name "tls-crypt" -file "$_private/ta.key"
        $config_filename = "$_client/$client_name/$vpn_name.ovpn"
        [System.IO.File]::WriteAllText($config_filename, ($config -join "`n"), $utf8)
        Write-Host "`t$config_filename"
    }

    Write-Host "Updating firewall rule..." -ForegroundColor Green
    $firewall_rule_name = "OpenVPN Server"
    if (!(Get-NetFirewallRule | ? {$_.Name -eq $firewall_rule_name })) { New-NetFirewallRule -Name $firewall_rule_name -DisplayName $firewall_rule_name }
    Set-NetFirewallRule -Name $firewall_rule_name -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol ($proto_firewall -replace "\d", "") -LocalPort $port

    Write-Host "Done!" -ForegroundColor Green
}
