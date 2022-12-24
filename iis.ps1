$ErrorActionPreference = "Stop"
$debug = $true

# Check that WebAdministration module is installed on the server
Get-Command "Get-WindowsFeature" 2>&1 | Out-Null
if ($? -and (Get-WindowsFeature Web-Scripting-Tools).InstallState -ne "Installed") {
    Import-Module ServerManager
    Add-WindowsFeature Web-Scripting-Tools
}

Import-Module WebAdministration

class HostsRecord {
    [string]$ip
    [string]$hostname
    [string]$section_name

    HostsRecord($ip, $hostname, $section_name) {
        $this.ip = $ip
        $this.hostname = $hostname
        $this.section_name = $section_name
    }
}

class HostsFile {
    [HostsRecord[]]$records = @()
    $filename = "$env:windir\System32\drivers\etc\hosts"
    $loaded = $false

    [void]AddRecord($ip, $hostname, $section_name = $null) {
        $this.records = $this.records | ? { !($hostname -and $_.hostname -eq $hostname) }
        $this.records += [HostsRecord]::new($ip, $hostname, $section_name)
    }

    [void]Load() {
        $section_name = $null
        $section_names = $this.records.section_name | Select -Unique
        if (!$section_names) { $section_names = @()}

        (Get-Content $this.filename) | % {
            if ($_ -match "^##\s*(.+?)\s*$") {
                $section_name = $matches[1].ToUpper()
            } else {
                if ($_ -match "^\s*(\S+)\s*(.+?)\s*$" -and !$section_names.Contains($section_name)) {
                    $this.records += [HostsRecord]::new($matches[1], $matches[2], $section_name)
                }
            }
        }

        $this.loaded = $true
    }

    [void]Save() {
        if (!$this.loaded) { $this.Load() }

        $output = @()

        $this.records.section_name | Select -Unique | % {
            $section_name = $_
            $output += "## $section_name"
            
            $this.records | ? { $_.section_name -eq $section_name } | % {
                $output += "$($_.ip)`t$($_.hostname)"
            }
            
            $output += ""
        }

        $output | Out-File $this.filename -Encoding UTF8
    }
}

Function ClearIISRecords {
    if ($debug) { Write-Host "Get-WebBinding | Remove-WebBinding" }
    Get-WebBinding | Remove-WebBinding
    if ($debug) { Write-Host "Get-ChildItem `"IIS:\Sites\`" | Remove-Item -Recurse" }
    Get-ChildItem "IIS:\Sites\" | Remove-Item -Recurse
    if ($debug) { Write-Host "Get-ChildItem `"IIS:\AppPools\`" | Remove-Item -Recurse" }
    Get-ChildItem "IIS:\AppPools\" | Remove-Item -Recurse
}

Function CreateWebsite($name, $directory, $persistent = $false) {
    if (!$(Get-ChildItem "IIS:\AppPools\" | Where-Object {$_.Name -eq $name})) {
        if ($debug) { Write-Host "New-WebAppPool -Name $name" }
        $pool = New-WebAppPool -Name $name
        
        if ($persistent) {
            if ($debug) { Write-Host "Set-ItemProperty (`"IIS:\AppPools\$name`") -Name processModel.idleTimeout -value ( [TimeSpan]::FromMinutes(0))" }
            Set-ItemProperty ("IIS:\AppPools\$name") -Name processModel.idleTimeout -value ( [TimeSpan]::FromMinutes(0))
        }
    }

    if (!$(Get-ChildItem "IIS:\Sites\" | Where-Object {$_.Name -eq $name})) {
        if ($debug) { Write-Host "New-Item -Type Directory $directory -Force" }
        $directory = New-Item -Type Directory $directory -Force
        if ($debug) { Write-Host "New-Website -Name $name -PhysicalPath $directory -ApplicationPool $name" }
        $website = New-Website -Name $name -PhysicalPath $directory -ApplicationPool $name
        if ($debug) { Write-Host "Get-WebBinding -Name $name | Remove-WebBinding" }
        $binding = Get-WebBinding -Name $name | Remove-WebBinding
    }
}

Function RemoveWebsite($name) {
    if ($(Get-ChildItem "IIS:\Sites\" | Where-Object {$_.Name -eq $name})) {
        if ($debug) { Write-Host "Get-WebBinding -Name $name | Remove-WebBinding" }
        $binding = Get-WebBinding -Name $name | Remove-WebBinding
        if ($debug) { Write-Host "Remove-Website -Name $name" }
        $website = Remove-Website -Name $name 
    }

    if ($(Get-ChildItem "IIS:\AppPools\" | Where-Object {$_.Name -eq $name})) {
        if ($debug) { Write-Host "Remove-WebAppPool -Name $name" }
        $pool = Remove-WebAppPool -Name $name
    }
}

Function RemoveBindings($url, $name = $null) {
    if ($debug) { Write-Host "Get-WebBinding -HostHeader $url | Where {`$_.Name -eq `"$name`" -or !`"$name`"} | Remove-WebBinding" }
    $binding = Get-WebBinding -HostHeader $url | Where {$_.Name -eq $name -or $name -eq $null} | Remove-WebBinding
}

Function CreateBinding($name, $url, $ip_address, $protocol, $port){
    if ($debug) { Write-Host "Get-WebBinding -Name $name -Protocol $protocol -Port $port -IPAddress $ip_address -HostHeader $url" }
    if ((Get-WebBinding -Name $name -Protocol $protocol -Port $port -IPAddress $ip_address -HostHeader $url).Length -eq 0) {
        if ($debug) { Write-Host "New-WebBinding -Name $name -Protocol $protocol -Port $port -IPAddress $ip_address -HostHeader $url" }
        $binding = New-WebBinding -Name $name -Protocol $protocol -Port $port -IPAddress $ip_address -HostHeader $url
    }
}

Function CreateBindingsForProtocolPort($name, $url, $public_ip, $local_ip, $protocol, $port){
    if ($public_ip -ne $null) { CreateBinding -name $name -url $url -ip_address $public_ip -protocol $protocol -port $port }
    if ($local_ip -ne $null) { CreateBinding -name $name -url $url -ip_address $local_ip -protocol $protocol -port $port }
}

Function CreateBindingsForWebsite($name, $url, $public_ip, $local_ip, $http, $https, $hosts = $null, $hosts_section = $null, $port = $null){
    $http_port = switch($port){ $null {80} default {$port} }
    $https_port = switch($port){ $null {443} default {$port} }
    if ($http) { CreateBindingsForProtocolPort -name $name -url $url -public_ip $public_ip -local_ip $local_ip -protocol http -port $http_port }
    if ($https) { CreateBindingsForProtocolPort -name $name -url $url -public_ip $public_ip -local_ip $local_ip -protocol https -port $https_port }
    if ($hosts -and $hosts_section) { $hosts.AddRecord($local_ip, $url, $hosts_section) }
}

Function EnsureWebsiteStarted($name) {
    if ($debug) { Write-Host "Get-Website -Name $name | Where {`$_.State -eq `"Started`"}" }

    if (!$(Get-Website -Name $name | Where {$_.State -eq "Started"}))
    {
        if ($debug) { Write-Host "Start-WebSite -Name $name" }
        $website = Start-WebSite -Name $name
    }
}

Function StartAppPool($name) {
    Get-ChildItem "IIS:\AppPools\" | ? { $_.Name -eq "clean.anmiles.net" } | Start-WebAppPool
}

Function StopAppPool($name) {
    Get-ChildItem "IIS:\AppPools\" | ? { $_.Name -eq "clean.anmiles.net" } | Stop-WebAppPool
}

Function CreateIISRecord ($name, $url, $directory, $public_ip, $local_ip, $http, $https, $persistent = $false, $hosts = $null, $hosts_section = $null, $port = $null) {
    CreateWebsite -name $name -directory $directory -persistent $persistent
    CreateBindingsForWebsite -name $name -url $url -public_ip $public_ip -local_ip $local_ip -http $http -https $https -hosts $hosts -hosts_section $hosts_section -port $port
    EnsureWebsiteStarted -name $name
}

Function MoveWebsite ($url, $new_name) {
    $bindings = @{}

    Get-Website | Where {$_.Name -eq $url} | foreach {
        $name = $_.Name

        Get-WebBinding -Name $name | foreach {
            $bindings[$_.bindingInformation] = $_
            if ($debug) { Write-Host "Remove-WebBinding -BindingInformation $($_.bindingInformation) -Name $name" }
            Remove-WebBinding -BindingInformation $_.bindingInformation -Name $name
        }
    }

    $bindings.Values | foreach {
        $array = $_.bindingInformation -split ":"
        $protocol = $_.protocol
        $ipAddress = $array[0]
        $port = $array[1]
        $hostHeader = $array[2]
        if ($debug) { Write-Host "New-WebBinding -Name $new_name -Protocol $protocol -Port $port -IPAddress $ipAddress -HostHeader $hostHeader" }
        New-WebBinding -Name $new_name -Protocol $protocol -Port $port -IPAddress $ipAddress -HostHeader $hostHeader
    }

    EnsureWebsiteStarted -name $new_name
}

Function PingWebsite ($name, $web_protocol, $monitoring, $headers) {
    Start-Sleep 1
    if ($debug) { Write-Host "(wget `"${web_protocol}://${name}`" -UseBasicParsing -Headers $headers).Content -notmatch $monitoring" }

    do {
        $success = $false

        try {
            $success = (wget "${web_protocol}://${name}" -Headers $headers -UseBasicParsing).Content -match $monitoring
            if (!$success) { Write-Host "Monitoring string '$moniroting' not detected in page source" }
        } catch [System.Net.WebException] {
            # TODO Notify about this: action needed to get website working
            Write-Host $_.Exception -ForegroundColor Red
        }

        if (!$success) {
            if ($debug) { Write-Host "Still waiting..." }
            Start-Sleep 5
        }
    } while (!$success)
}
