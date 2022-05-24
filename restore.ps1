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
    [string]$backup_directory,
    [string]$backup_filename,
    [string]$snapshot_name,
    [switch]$local,
    [switch]$remote,
    [switch]$progress,
    [switch]$skip_database,
    [switch]$skip_userdata
)

"progress was $proress"

$quiet = switch($progress){$true{""} default{"--quiet"}}

"quiet is $quiet"

Import-Module $env:MODULES_ROOT\sql.ps1 -Force

if (!$winrm_endpoint) {
    if (!$backup_filename) { $backup_filename = "$db_name.bak" }
    $backup_path = "$backup_directory\$backup_filename"

    if (Test-Path $backup_path) {
        $created_time = (Get-Item $backup_path).CreationTime

        if ($local -and $remote) {
            throw "Cannot set local and remote switches at the same time"
        }

        if (!$local -and !$remote) {
            $local = confirm "Do you want to just restore local backup that was created at ({{$created_time}})"
        }
    }
}

Function Invoke-Command-In-Session ([object]$session, [ScriptBlock]$ScriptBlock, [Object[]]$ArgumentList) {
    if ($session) {
        Invoke-Command -Session $session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    } else {
        Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }
}

if (!$snapshot_name) {
    $snapshot_name = $(aws s3 ls s3://$bucket_backup/) | where {$_ -match ".json"} | % {$_ -replace ".*\s(\S+)\s*?$", '$1'} | sort | select -last 1
    $snapshot_name = $snapshot_name -replace ".json", ""
}

if (!$skip_userdata -and !$local) {
    if ($winrm_endpoint) {
        Write-Host "Connecting to $winrm_endpoint ..."
        $securePassword =  $(ConvertTo-SecureString -AsPlainText -Force $win_password)
        $credential = $(New-Object System.Management.Automation.PSCredential $win_username, $securePassword)
        $session = New-PSSession -ConnectionUri $winrm_endpoint -Credential $credential
    }

    Write-Host "Downloading userdata from snapshot $snapshot_name into $userdata_directory..."
    Invoke-Command-In-Session -Session $session -ScriptBlock {
        param($userdata_directory, $bucket_backup, $snapshot_name, $quiet)
        Write-Host "Into $userdata_directory.zip"
        aws s3 cp s3://$bucket_backup/$snapshot_name.zip "$userdata_directory.zip" $quiet
        "Get-Item `"$userdata_directory.zip`" | Out-Host"
        Get-Item "$userdata_directory.zip" | Out-Host
        Write-Host "done!"
    } -ArgumentList $userdata_directory, $bucket_backup, $snapshot_name, $quiet

    Write-Host "Decompressing userdata in $userdata_directory ..."
    Invoke-Command-In-Session -Session $session -ScriptBlock {
        param($userdata_directory)
        Write-Host "Create directory $userdata_directory"
        md $userdata_directory -Force
        Write-Host "Go to directory $userdata_directory"
        cd $userdata_directory
        Write-Host "Delete all children from directory $userdata_directory"
        del $userdata_directory\* -Recurse -Force
        Write-Host "Start 7z "
        & 'C:\Program Files\7-Zip\7z.exe' x -y -r -bso0 -bsp0 "$userdata_directory.zip"
        Write-Host "delete zip"
        del -Force "$userdata_directory.zip"
        Write-Host "done!"
    } -ArgumentList $userdata_directory
}

if (!$skip_database) {
    if ($winrm_endpoint) {
        Write-Host "Delete database $db_name..."
        sql_delete_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name
        
        Write-Host "Restore database $db_name from $snapshot_name.bak ..."
        rds_restore_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name -db_username $db_username -db_password $db_password -bucket_backup $bucket_backup -snapshot_name "$snapshot_name.bak"
    } else {
        if (!$local) {
            Write-Host "Downloading database from snapshot $snapshot_name into $backup_path ..."
            aws s3 cp s3://$bucket_backup/$snapshot_name.bak $backup_path $quiet
        }

        Write-Host "Delete database $db_name ..."
        sql_delete_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name
        
        Write-Host "Restore database $db_name from $backup_path ..."
        sql_restore_database -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name -db_username $db_username -db_password $db_password -filename $backup_path
    }
}

Write-Host "Recycling app pools..."
Invoke-Command-In-Session -Session $session -ScriptBlock { Get-ChildItem "IIS:\AppPools\" | Restart-WebAppPool }

Write-Host "Disconnecting..."
if ($session) { Remove-PSSession -Session $session }

Write-Host "Done!"
