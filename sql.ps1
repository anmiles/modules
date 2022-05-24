Import-Module SqlServer
Import-Module $env:MODULES_ROOT\progress.ps1 -Force

$ErrorActionPreference = "Stop"
$env_prefix = "sqlcmd_invoke_var_"

<#
function sql_connect($db_name, $sql_endpoint, $sql_username, $sql_password) {
    param (
        [Parameter(Mandatory = $true)]$db_name,
        [Parameter(Mandatory = $true)]$sql_endpoint,
        $sql_username,
        $sql_password,
        [Parameter(Mandatory = $true)][scriptblock]$callback
    )
    
    $connection = New-Object System.Data.SqlClient.SQLConnection

    if($sql_username -and $sql_password) {
        $connection.ConnectionString = "Server=$($sql_endpoint);Database=$($db_name);User Id=$($sql_username);Password=$($sql_password);"
    } else {
        $connection.ConnectionString = "Server=$($sql_endpoint);Database=$($db_name);Integrated Security=SSPI;"
    }

    if(-not ($connection.State -like "Open")) {
        try {
            $connection.Open()
        } catch [Exception] {
            throw $_
        }
    }

    $connection.Close()
}
#>

function sql_exec($name, $db_name, $sql_endpoint, $sql_username, $sql_password, $timeout = 3600, $parameters = @{}, $debug = $false) {
    $query = "exec $name"

    $parameters.Keys | foreach {
        $key = $_
        $value = $parameters[$key]

        switch ($value.GetType().Name) {
            "DateTime" { $query += " @$key='`$($env_prefix$key)',"; [Environment]::SetEnvironmentVariable($env_prefix + $key, $value.ToString("yyyy/MM/dd HH:mm:ss"), "Process") }
            "Boolean"  { $query += " @$key=`$($env_prefix$key),";   [Environment]::SetEnvironmentVariable($env_prefix + $key, [int]$value, "Process") }
            "Int32"    { $query += " @$key=`$($env_prefix$key),";   [Environment]::SetEnvironmentVariable($env_prefix + $key, $value, "Process") }
            "Int64"    { $query += " @$key=`$($env_prefix$key),";   [Environment]::SetEnvironmentVariable($env_prefix + $key, $value, "Process") }
            default    { $query += " @$key='`$($env_prefix$key)',"; [Environment]::SetEnvironmentVariable($env_prefix + $key, ($value -replace "'", "''"), "Process") }
        }
    }
    
    $query = $query -replace ",$", ""

    if ($debug) {Write-Host $query}
    return sql_query -query $query -db_name $db_name -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -timeout $timeout
}

function sql_prepare($name, $parameters = @{}) {
    $query = "exec $name"

    $parameters.Keys | foreach {
        $key = $_
        $value = $parameters[$key]

        switch ($value.GetType().Name) {
            "DateTime" { $query += " @$key='$($value.ToString("yyyy/MM/dd HH:mm:ss"))'," }
            "Boolean"  { $query += " @$key=$([int]$value)," }
            "Int32"    { $query += " @$key=$value," }
            "Int64"    { $query += " @$key=$value," }
            default    { $query += " @$key='$($value -replace "'", "''")'," }
        }
    }
    
    $query = $query -replace ",$", ""
    return $query
}

function sql_query($query, $filename, $db_name, $sql_endpoint, $sql_username, $sql_password, $timeout = 3600) {
    $auth = @{}
    if($sql_username) { $auth = @{ UserName = $sql_username; Password = $sql_password } }

    $input = @{}
    
    if ($query) {
        $input = @{ Query = $query }
    } else {
        if ($filename) {
            $input = @{ InputFile = $filename }
        } else {
            throw "Input is not defined: both `$query and `$filename are empty"
        }
    }

    $result = $(Invoke-Sqlcmd -Database $db_name -ServerInstance ($sql_endpoint -replace ":", ",") -MaxCharLength (1 -shl 30) -QueryTimeout $timeout @auth @input)
    return $result
}

function sql_char_limits($table_name, $db_name, $sql_endpoint, $sql_username, $sql_password, $timeout = 3600) {
    return sql_query -query "select c.name as [column],
        case when left(tt.name, 1) = 'n' then c.max_length / 2 else c.max_length end as [limit]
    from sys.columns c
        inner join sys.tables t on t.object_id = c.object_id
        inner join sys.types tt on tt.user_type_id = c.user_type_id
    where t.name = '$table_name'
        and c.max_length > 0
        and tt.name in ('char', 'nchar', 'varchar', 'nvarchar')" -db_name $db_name -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -timeout $timeout
}

function rds_wait($sql_endpoint, $sql_username, $sql_password, $task_id) {
    $progress = Start-Progress -count 100
    $i = 0

    do {
        $result = rds_task_status -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -task_id $task_id
        $status = $result.lifecycle
        $complete = $result.$("% complete")
        if (!$complete) { $complete = '0' }
        $progress.Set([int]$complete, $status)
        Start-Sleep 3
    } while ($status -ne "SUCCESS" -and $status -ne "ERROR" -and $status -ne "CANCELLED")
}

function rds_query($query, $sql_endpoint, $db_name, $sql_username, $sql_password, $wait = $true) {
    $result = sql_query -query $query -sql_endpoint $sql_endpoint -db_name $db_name -sql_username $sql_username -sql_password $sql_password
    if ($result -is [array]) { $result = $result[0] }

    if ($wait) {
        rds_wait -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -task_id $result.task_id
    }

    return $result
}

function sql_backup_database($sql_endpoint, $sql_username, $sql_password, $db_name, $filename) {
    sql_query -query "backup database [$db_name] to disk = N'$filename' with nounload, stats = 10" -sql_endpoint $sql_endpoint -db_name master -sql_username $sql_username -sql_password $sql_password
}

function rds_backup_database($sql_endpoint, $sql_username, $sql_password, $db_name, $bucket_backup, $snapshot_name) {
    rds_query -query "exec msdb.dbo.rds_backup_database @source_db_name='$db_name', @s3_arn_to_backup_to='arn:aws:s3:::$bucket_backup/$snapshot_name'" -sql_endpoint $sql_endpoint -db_name msdb -sql_username $sql_username -sql_password $sql_password
}

function sql_restore_database($sql_endpoint, $sql_username, $sql_password, $db_name, $db_username, $db_password, $filename) {
    sql_query -query "restore database [$db_name] from disk = N'$filename' with file = 1, nounload, replace, stats = 10" -sql_endpoint $sql_endpoint -db_name master -sql_username $sql_username -sql_password $sql_password

    sql_restore_database_access -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name -db_username $db_username -db_password $db_password
}

function rds_restore_database($sql_endpoint, $sql_username, $sql_password, $db_name, $db_username, $db_password, $bucket_backup, $snapshot_name) {
    rds_query -query "exec msdb.dbo.rds_restore_database @restore_db_name='$db_name', @s3_arn_to_restore_from='arn:aws:s3:::$bucket_backup/$snapshot_name'" -sql_endpoint $sql_endpoint -db_name msdb -sql_username $sql_username -sql_password $sql_password

    sql_restore_database_access -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -db_name $db_name -db_username $db_username -db_password $db_password
}

function sql_restore_database_access($sql_endpoint, $sql_username, $sql_password, $db_name, $db_username, $db_password) {
    sql_query -query "if not exists (select loginname from master.dbo.syslogins where name = '$db_username') begin; create login [$db_username] with password=N'$db_password', check_expiration=off, check_policy=off; end" -sql_endpoint $sql_endpoint -db_name master -sql_username $sql_username -sql_password $sql_password

    sql_query -query "if exists (select * from sys.sysusers where name = '$db_username') begin; drop user [$db_username]; end; create user [$db_username] for login [$db_username]; alter user [$db_username] with default_schema=[dbo]; alter role [db_owner] add member [$db_username]" -sql_endpoint $sql_endpoint -db_name $db_name -sql_username $sql_username -sql_password $sql_password
}

function sql_delete_database($sql_endpoint, $sql_username, $sql_password, $db_name) {
    $result = sql_query -query "exec msdb.dbo.sp_delete_database_backuphistory @database_name='$db_name'" -sql_endpoint $sql_endpoint -db_name msdb -sql_username $sql_username -sql_password $sql_password

    #$result = sql_query -query "if exists(select name from sys.databases where name = '$db_name') alter database [$db_name] set multi_user" -sql_endpoint $sql_endpoint -db_name msdb -sql_username $sql_username -sql_password $sql_password

    $result = sql_query -query "declare @sql varchar(max);set @sql = '';select @sql = @sql + ' kill ' + cast(spid as varchar(4)) + ' ' from master.dbo.sysprocesses where db_name(dbid) = '$db_name';exec(@sql)" -sql_endpoint $sql_endpoint -db_name master -sql_username $sql_username -sql_password $sql_password

    $result = sql_query -query "if exists(select name from sys.databases where name = '$db_name') drop database [$db_name]" -sql_endpoint $sql_endpoint -db_name master -sql_username $sql_username -sql_password $sql_password
}

function rds_database_exists($sql_endpoint, $sql_username, $sql_password, $db_name) {
    $result = sql_query -query "select * from sys.databases where name = '$db_name'" -sql_endpoint $sql_endpoint -db_name master -sql_username $sql_username -sql_password $sql_password
    return $result.Count -ne 0
}

function rds_task_status($sql_endpoint, $sql_username, $sql_password, $task_id) {
    return rds_query -query "exec msdb.dbo.rds_task_status @task_id='$task_id'" -sql_endpoint $sql_endpoint -db_name msdb -sql_username $sql_username -sql_password $sql_password -wait $false
}

function rds_cancel_task($sql_endpoint, $sql_username, $sql_password, $task_id) {
    rds_query -query "exec msdb.dbo.rds_cancel_task @task_id='$task_id'" -sql_endpoint $sql_endpoint -db_name msdb -sql_username $sql_username -sql_password $sql_password -wait $false
    rds_wait -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password -task_id $task_id
}
