Param (
    [Parameter(Mandatory = $true)][string]$db_username,
    [Parameter(Mandatory = $true)][string]$db_password,
    [string]$sql_username,
    [string]$sql_password,
    [string]$win_username,
    [string]$win_password,
    [string]$winrm_endpoint,
    [Parameter(Mandatory = $true)][string]$sql_endpoint,
    [Parameter(Mandatory = $true)][string]$db_name,
    [Parameter(Mandatory = $true)][string]$userdata_directory,
    [Parameter(Mandatory = $true)][string]$bucket_backup,
    [string]$snapshot_name,
    [switch]$progress,
    [switch]$quiet = $true
)

if ($quiet) { $quietString = "--quiet" } else { $quietString = "" }

Import-Module $env:MODULES_ROOT\sql.ps1 -Force

if ($progress) {
    Import-Module $env:MODULES_ROOT\timer.ps1 -Force
    $timer = Start-Timer
}

Function Invoke-Command-In-Session ([object]$session, [ScriptBlock]$ScriptBlock, [Object[]]$ArgumentList) {
    if ($session) {
        Invoke-Command -Session $session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    } else {
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
}

$environment_name = "default"

if ($state -match "\.") {
    $arr = $state -split "\."
    $state = $arr[0]
    $environment_name = $arr[1]
}

if ($state -eq "dev") {
    $session = $null
} else {
    if ($progress) { $timer.StartTask("Connecting to $winrm_endpoint") }
    $securePassword =  $(ConvertTo-SecureString -AsPlainText -Force $win_password)
    $credential = $(New-Object System.Management.Automation.PSCredential $win_username, $securePassword)
    $session = New-PSSession -ConnectionUri $winrm_endpoint -Credential $credential
}

if (!$snapshot_name) {
    if ($progress) { $timer.StartTask("Getting recent snapshot") }
    $snapshots = $(aws s3 ls s3://$bucket_backup/) | ? {$_ -match ".json"} | % {$_ -replace ".*\s(\S+)\s*?$", '$1'}
    $snapshot = $snapshots | sort | select -last 1
    $snapshot_name = $snapshot -replace ".json", ""
}

if ($progress) { $timer.StartTask("Downloading userdata from snapshot $snapshot_name into $userdata_directory") }
Invoke-Command-In-Session -Session $session -ScriptBlock {
    param($userdata_directory, $bucket_backup, $snapshot_name, $quietString)
    aws s3 cp s3://$bucket_backup/$snapshot_name.zip "$userdata_directory.zip" $quietString
    Get-Item "$userdata_directory.zip" | Out-Host
} -ArgumentList $userdata_directory, $bucket_backup, $snapshot_name, $quietString

if ($progress) { $timer.StartTask("Decompressing userdata in $userdata_directory") }
Invoke-Command-In-Session -Session $session -ScriptBlock {
    param($userdata_directory)
    md $userdata_directory -Force
    cd $userdata_directory
    del $userdata_directory\* -Recurse -Force
    & 'C:\Program Files\7-Zip\7z.exe' x -y -r -bso0 -bsp0 "$userdata_directory.zip"
    del -Force "$userdata_directory.zip"
} -ArgumentList $userdata_directory

if ($progress) { $timer.StartTask("Delete database $db_name") }
sql_delete_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name

if ($progress) { $timer.StartTask("Restore database $db_name from $snapshot_name.bak") }
rds_restore_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name -db_username $db_username -db_password $db_password -bucket_backup $bucket_backup -snapshot_name "$snapshot_name.bak"

if ($progress) { $timer.StartTask("Recycling app pools") }
Invoke-Command-In-Session -Session $session -ScriptBlock { Get-ChildItem "IIS:\AppPools\" | Restart-WebAppPool }

if ($session) {
    if ($progress) { $timer.StartTask("Disconnecting") }
    Remove-PSSession -Session $session
}

if ($progress) { $timer.Finish() }
