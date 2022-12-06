<#
    1. Установить OpenVPN, при установке нажать "Customize" и отметить все галки, включая "OpenVPN Service" и "OpenSSL Utilities"
    2. Отредактировать переменные ниже:
        - "root", "server", "port", "vpn_name", "client_names", "clean" - обязательно задать свои
        - если clean установлен в $true, происходит генерация всего с нуля, если $false - только генерируются новые (недостающие) сертификаты и конфиги, например если был добавлен новый клиент в client_names
        - eсли будут обнаружены клиентские сертификаты, не включённые в client_names, они будут отозваны
    3. Запустить файл vpn-generate-launcher.cmd двойным кликом
#>

<#
    1. Install OpenVPN from Windows installer https://openvpn.net/community-downloads/ - during install, click "Customize" and check "OpenVPN Service" and "OpenSSL Utilities"
    2. Customize variables below:
        - variables are important to change are: "root", "server", "port", "vpn_name", "client_names", "clean"
        - clean if set to $true, will re-generate everything from scratch, otherwise will generate any missing items, i. e. if new client was added to client_names
        - if client certificates are detected that are nor in client_names, they will be revoked
    3. Launch file vpn-generate-launcher.cmd by double-click
#>

Import-Module vpn-generate.ps1 -Force

$root = "C:/Program Files/OpenVPN" <# Where OpenVPN installed #>
$proto_server = "tcp4"
$proto_client = "tcp4"
$proto_firewall = "TCP"
$server = "vpn.example.com" <# Domain name or IP address of VPN server #>
$port = "443" <# Desired port #>
$subnet_local = "10.10.10.0 255.255.255.0"
$subnets_remote = $null
$vpn_name = "home" <# Desired label of vpn server and vpn connection #>
$client_names = @("mobile", "notebook", "laptop") <# List of clients #>
$cn = $server
$org = $server
$ou = $server
$country = "RU"
$province = "Moscow"
$city = "Moscow"
$email = "user@example.com"
$dn = "org"
$algo = "RSA"
$digest = "SHA256"
$curve = "secp384r1"
$key_size = 2048
$expire = 3650
$clean = $true

Generate-VPN `
    -root           $root `
    -proto_server   $proto_server `
    -proto_client   $proto_client `
    -proto_firewall $proto_firewall `
    -server         $server `
    -port           $port `
    -subnet_local   $subnet_local `
    -subnets_remote $subnets_remote `
    -vpn_name       $vpn_name `
    -client_names   $client_names `
    -cn             $cn `
    -org            $org `
    -ou             $ou `
    -country        $country `
    -province       $province `
    -city           $city `
    -email          $email `
    -dn             $dn `
    -algo           $algo `
    -digest         $digest `
    -curve          $curve `
    -key_size       $key_size `
    -expire         $expire `
    -clean:$clean
