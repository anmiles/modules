Function Generate-VPN {
    Param (
        [string]$root = "D:/openvpn",

        [string]$proto_server = "tcp4",
        [string]$proto_client = "tcp4",
        [string]$proto_firewall = "TCP",
        [Parameter(Mandatory = $true)][string]$address, # "vpn.example.com"
        [string]$port = "443",
        [string]$subnet_local, # "10.10.0.0 255.255.255.0"
        [string[]]$subnets_remote = @(), # @("10.10.10.0 255.255.255.0")

        [Parameter(Mandatory = $true)][string]$server_name, # "home"
        [Parameter(Mandatory = $true)][string[]]$client_names, # @("mobile", "notebook", "laptop")
        [string]$revoke_crt = "revokecrt",

        [Parameter(Mandatory = $true)][string]$cn, # $server_name
        [Parameter(Mandatory = $true)][string]$org, # $server_name
        [Parameter(Mandatory = $true)][string]$ou, # $server_name
        [Parameter(Mandatory = $true)][string]$country, # "RU"
        [Parameter(Mandatory = $true)][string]$province, # "MO"
        [Parameter(Mandatory = $true)][string]$city, # "Moscow"
        [Parameter(Mandatory = $true)][string]$email, # "user@example.com"

        [string]$dn = "org",
        [string]$digest = "sha512",
        [int]$key_size = 2048,
        [int]$key_days = 3650,
        [int]$crl_days = 3650,

        [switch]$regenerate_all_keys
    )

    $_bin = "$root/bin"
    $_config = "$root/config"
    $_client = "$root/client"
    $_easy_rsa = "$root/easy-rsa"
    $_keys = "$_easy_rsa/keys"
    $_private = "$_keys/private"
    $_certs = "$_keys/certs_by_serial"
    $_extensions_client = "$_easy_rsa/x509-types/client"
    $_extensions_server = "$_easy_rsa/x509-types/server"

    [Environment]::SetEnvironmentVariable("HOME", $root, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_PKI", $_keys, "Process")
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
    [Environment]::SetEnvironmentVariable("EASYRSA_DIGEST", $digest, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_KEY_SIZE", $key_size, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_CERT_EXPIRE", $key_days, "Process")
    [Environment]::SetEnvironmentVariable("EASYRSA_CRL_DAYS", $crl_days, "Process")

    $_cnf = (Get-Item $_easy_rsa/openssl-*.cnf).FullName

    $subject = "/C=$country/ST=$province/L=$city/O=$org/OU=$ou/CN"

    $vpn_server_pass = $null
    $vpn_client_pass = $null

    Write-Host "Starting..." -ForegroundColor Green

    if ((Test-Path $_keys) -and $regenerate_all_keys) {
        Remove-Item $_keys -Recurse -Force
    }

    if (!(Test-Path $_keys)) { New-Item $_keys -Type Directory | Out-Null }
    if (!(Test-Path $_private)) { New-Item $_private -Type Directory | Out-Null }
    if (!(Test-Path $_certs)) { New-Item $_certs -Type Directory | Out-Null }

    if (!(Test-Path $_keys/index.txt)) {
        if (Test-Path $_easy_rsa/index.txt.start) { Copy-Item $_easy_rsa/index.txt.start $_keys/index.txt }
        else { file "$_keys/index.txt" "" }
    }

    if (!(Test-Path $_keys/serial)) {
        if (Test-Path $_easy_rsa/serial.start) { Copy-Item $_easy_rsa/serial.start $_keys/serial }
        else { file "$_keys/serial" "01" }
    }

    if (!(Test-Path $_keys/ta.key)) {
        Write-Host "Generating static key..." -ForegroundColor Green
        & $_bin/openvpn --genkey secret $_keys/ta.key
    }

    if (!(Test-Path $_keys/dh$key_size.pem)) {
        Write-Host "Generating DH key..." -ForegroundColor Green
        & $_bin/openssl dhparam -out $_keys/dh$key_size.pem $key_size
    }

    if (!(Test-Path $_keys/ca.crt)) {
        Write-Host "Generating CA certificate..." -ForegroundColor Green
        & $_bin/openssl genrsa -out $_private/ca.key -aes256 -passout "pass:$(GetServerPassword)" $key_size
        & $_bin/openssl req -days $key_days -passin "pass:$(GetServerPassword)" -new -utf8 -x509 -key $_private/ca.key -keyout $_private/ca.key -out $_keys/ca.crt -config $_cnf -subj "$subject=$cn"
    }

    Function GenerateCert ($name, $extfile, [switch]$client) {
        $ca_password = GetServerPassword
        $cert_password = GetServerPassword
        if ($client) { $cert_password = GetClientPassword }

        & $_bin/openssl req -passout "pass:$cert_password" -utf8 -new -newkey rsa:2048 -keyout $_keys/$name.key -out $_keys/$name.csr -config $_cnf -subj "$subject=$name"
        & $_bin/openssl ca -days $key_days -passin "pass:$ca_password" -utf8 -batch -in $_keys/$name.csr -out $_keys/$name.crt -extfile $extfile -config $_cnf
    }

    if (!(Test-Path $_keys/crl.pem)) {
        Write-Host "Generating revoke key..." -ForegroundColor Green
        GenerateCert -name $revoke_crt -extfile $_extensions_client -client

        & $_bin/openssl ca -revoke $_keys/$revoke_crt.crt -passin "pass:$(GetServerPassword)" -config $_cnf
        & $_bin/openssl ca -gencrl -crldays $crl_days -utf8 -out $_keys/crl.pem -passin "pass:$(GetServerPassword)" -config $_cnf

        Get-Content $_keys/ca.crt, $_keys/crl.pem | Set-Content $_keys/revoke_test_file.pem
        & $_bin/openssl verify -CAfile $_keys/revoke_test_file.pem -crl_check $_keys/$revoke_crt.crt
        Remove-Item $_keys/revoke_test_file.pem
    }

    if (!(Test-Path $_keys/$server_name.crt)) {
        Write-Host "Generating server certificate [$server_name]..." -ForegroundColor Green
        $altNameType = "DNS"
        if ($cn -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') { $altNameType = "IP" }
        file $_extensions_server_tmp ((file $_extensions_server) + "subjectAltName = $($altNameType):$cn")
        GenerateCert -name $server_name -extfile $_extensions_server_tmp
        Remove-Item $_extensions_server_tmp
    }

    $client_names | ? { !(Test-Path $_keys/$_.crt) } | % {
        $client_name = $_
        Write-Host "Generating client certificate [$client_name]..." -ForegroundColor Green
        GenerateCert -name $client_name -extfile $_extensions_client -client
    }

    Write-Host "Generating server config..." -ForegroundColor Green
    New-Item -Type Directory -Force $_config | Out-Null

    $config = @()
    $config += "dev tun"
    $config += "proto $proto_server"
    $config += "port $port"
    $config += "tls-server"
    $config += "status status.log"
    $config += "log openvpn.log"
    $config += "topology subnet"
    $config += "auth-nocache"
    $config += "cipher AES-128-CBC"
    $config += "data-ciphers AES-128-CBC"
    $config += "persist-key"
    $config += "tun-mtu 1500"
    $config += "mssfix"
    $config += "keepalive 10 120"
    $config += "verb 3"

    if ($subnet_local) {
        $config += "server $subnet_local"
    }

    if ($subnets_remote) {
        $subnets_remote | % {
            $config += "push `"route $_`""
        }
    }

    $config += Embed-Key -name "ca" -file "$_keys/ca.crt"
    $config += Embed-Key -name "cert" -file "$_keys/$server_name.crt"
    $config += Embed-Key -name "key" -file "$_keys/$server_name.key"
    $config += Embed-Key -name "dh" -file "$_keys/dh$key_size.pem"
    $config += Embed-Key -name "tls-auth" -file "$_keys/ta.key"
    $config += Embed-Key -name "crl-verify" -file "$_keys/crl.pem"

    file "$_config/$server_name [server].ovpn" $config -lines

    Write-Host "Generating client config..." -ForegroundColor Green
    New-Item -Type Directory -Force $_client | Out-Null

    $client_names | % {
        New-Item -Type Directory -Force $_client/$_ | Out-Null

        $config = @()
        $config += "client"
        $config += "dev tun"
        $config += "proto $proto_client"
        $config += "remote $address $port"
        $config += "tls-client"
        $config += "route-delay 3"
        $config += "remote-cert-tls server"
        $config += "auth-nocache"
        $config += "cipher AES-128-CBC"
        $config += "data-ciphers AES-128-CBC"
        $config += "tun-mtu 1500"
        $config += "mssfix"
        $config += "ping 10"
        $config += "verb 3"
        $config += "ping-restart 60"
        $config += Embed-Key -name "ca" -file "$_keys/ca.crt"
        $config += Embed-Key -name "cert" -file "$_keys/$_.crt"
        $config += Embed-Key -name "key" -file "$_keys/$_.key"
        $config += Embed-Key -name "tls-auth" -file "$_keys/ta.key"

        file "$_client/$_/$server_name.ovpn" $config -lines
    }

    Write-Host "Updating firewall rule..." -ForegroundColor Green
    $firewall_rule_name = "OpenVPN Server [$server_name]"
    if (!(Get-NetFirewallRule | ? {$_.Name -eq $firewall_rule_name })) { New-NetFirewallRule -Name $firewall_rule_name -DisplayName $firewall_rule_name }
    Set-NetFirewallRule -Name $firewall_rule_name -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol ($proto_firewall -replace "\d", "") -LocalPort $port

    Write-Host "Cleaning up..." -ForegroundColor Green
    Remove-Item $_keys/*.old -Force
    Remove-Item $_keys/*.csr -Force
    Remove-Item $_keys/$revoke_crt.* -Force

    Write-Host "Done!" -ForegroundColor Green
}

Function GetServerPassword {
    return GetPassword "vpn_server_pass" "VPN server password"
}

Function GetClientPassword {
    return GetPassword "vpn_client_pass" "VPN client password"
}

Function GetPassword($variable_name, $title) {
    $min_length = 4
    $max_length = 1023
    $password = (Get-Variable -Scope Script | ? {$_.Name -eq $variable_name}).Value

    while ($password.Length -lt $min_length -or $password.Length -gt $max_length) {
        $password = ReadPassword -prompt "Enter $title ($min_length ... $max_length characters)"
    }

    Set-Variable $variable_name $password -Scope Script
    return $password
}

Function ReadPassword ($prompt) {
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR((Read-Host $prompt -AsSecureString)))
}

Function Embed-Key($name, $file) {
    $content = (Get-Content $file) -join "`r`n"
    $content = $content -replace '([\s\S]*)(?=-----BEGIN)([\s\S]*)(?<=END[^-]*-----)([\s\S]*)', '$2'
    return @("<$name>", $content, "</$name>")
}
