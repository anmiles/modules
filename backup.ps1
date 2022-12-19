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
    [Parameter(Mandatory = $true)][string]$bucket_revision,
    [Parameter(Mandatory = $true)][string]$state,
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
    $snapshot_name = (Get-Date).ToUniversalTime().ToString("yyyy.MM.dd_HH.mm.ss")
}

if ($progress) { $timer.StartTask("Compressing userdata in $userdata_directory") }
Invoke-Command-In-Session -Session $session -ScriptBlock {
    param($userdata_directory)
    md $userdata_directory -Force
    cd $userdata_directory
    & 'C:\Program Files\7-Zip\7z.exe' a -y -r -bso0 -bsp0 -mx=0 "$userdata_directory.zip" .
} -ArgumentList $userdata_directory

if ($progress) { $timer.StartTask("Uploading userdata to snapshot $snapshot_name") }
Invoke-Command-In-Session -Session $session -ScriptBlock {
    param($userdata_directory, $bucket_backup, $snapshot_name, $quietString)
    aws s3 cp "$userdata_directory.zip" s3://$bucket_backup/$snapshot_name.zip $quietString
    del -Force "$userdata_directory.zip"
} -ArgumentList $userdata_directory, $bucket_backup, $snapshot_name, $quietString

if ($progress) { $timer.StartTask("Backup database $db_name into $snapshot_name.bak") }
rds_backup_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name -bucket_backup $bucket_backup -snapshot_name "$snapshot_name.bak"

if ($state -eq "web") {
    if ($progress) { $timer.StartTask("Copying JSON $environment_name.json into $snapshot_name.json") }
    aws s3 cp s3://$bucket_revision/$environment_name.json s3://$bucket_backup/$snapshot_name.json $quietString
}

if ($session) {
    if ($progress) { $timer.StartTask("Disconnecting") }
    Remove-PSSession -Session $session
}

if ($progress) { $timer.Finish() }
