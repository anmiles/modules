Param ( 
    [Parameter(Mandatory = $true)][string]$sql_endpoint,
    [Parameter(Mandatory = $true)][string]$db_username,
    [Parameter(Mandatory = $true)][string]$db_password,
    [Parameter(Mandatory = $true)][string]$db_name,
    [Parameter(Mandatory = $true)][string]$sql_migrations
)

Import-Module $env:MODULES_ROOT\sql.ps1 -Force

$sql_query = {
    param($query, $filename) 
    sql_query -query $query -filename $filename -db_name $db_name -sql_endpoint $sql_endpoint -sql_username $db_username -sql_password $db_password
}

$sql_exec = {
    param($name, $parameters = @{}) 
    sql_exec -name $name -parameters $parameters -db_name $db_name -sql_endpoint $sql_endpoint -sql_username $db_username -sql_password $db_password
}

$migration_entities = @(
    @{Section = "Types"},
    @{Section = "Tables"},
    @{Section = "Functions"},
    @{Section = "Views"},
    @{Section = "StoredProcedures"},
    @{Section = "Data"}
)

$drop_entities = @(
    @{Section = "StoredProcedures"; Keyword = "procedure"},
    @{Section = "Views"; Keyword = "view"},
    @{Section = "Functions"; Keyword = "function"},
    @{Section = "Types"; Keyword = "type"}
)

Function CreateMigrationsObject {
    $obj = @{}
    $migration_entities | % {$obj[$_.Section] = @{}}
    return $obj
}

Function GetSPDependencies($type) {
    $result = &$sql_query -query "select referencing_entity_name from sys.dm_sql_referencing_entities('dbo.$type', 'TYPE')"
    if (!$result) { return @() }
    return $result["referencing_entity_name"]
}

$drops = CreateMigrationsObject
$migrations = CreateMigrationsObject
$last_migrations = CreateMigrationsObject

Function GetMigrations {
    try {
        (&$sql_exec -name "GetMigrations") | % {
            $last_migrations[$_.Section][$_.Name] = @{Hash = $_.Hash}
        }
    } catch {
        if ($_.Exception.Message.Contains("Could not find stored procedure")) {
            $install = Join-Path $sql_migrations "../Install"
            &$sql_query -filename (Join-Path $install "Tables/Migrations.sql")
            &$sql_query -filename (Join-Path $install "StoredProcedures/GetMigrations.sql") 
            &$sql_query -filename (Join-Path $install "StoredProcedures/SetMigration.sql")
            GetMigrations
        } else { throw $_.Exception }
    }
}

Write-Host "Get migrations" -ForegroundColor Green
GetMigrations

# create migrations and drops
Write-Host "Build dependencies" -ForegroundColor Green
$migrations.Keys | % {
    $section = $_
    $path = Join-Path $sql_migrations $section

    if (Test-Path $path) {
        Get-ChildItem $path -Filter "*.sql" | % {
            $name = $_.Name.Replace(".sql", "")
            $filename = $_.FullName
            $hash = (Get-FileHash $filename).Hash
            $migrations[$section][$name] = @{Hash = $hash}

            if ($hash -ne $last_migrations[$section][$name].Hash) {
                if ($drop_entities.Section -contains $section) {
                    $drops[$section][$name] = $true

                    if ($section -eq "Types") {
                        GetSPDependencies($name) | % {
                            $drops["StoredProcedures"][$_] = $true
                        }
                    }
                }
            }
        }
    }
}

# skip migrations that wasn't changed and don't follow drops
$migrations.Keys | % {
    $section = $_

    $migrations[$section].Keys | % {
        $name = $_
        $hash = $migrations[$section][$name].Hash

        if ($hash -eq $last_migrations[$section][$name].Hash -and !($drops[$section].Keys -contains $name)) {
            $migrations[$section][$name].Skipped = $true
        }
    }
}

# perform drops
Write-Host "Perform drops" -ForegroundColor Green
$drop_entities | % {
    $section = $_.Section
    $keyword = $_.Keyword
    Write-Host "> $section"

    $drops[$section].Keys | % {
        $name = $_
        Write-Host "  $name" -ForegroundColor Yellow
        &$sql_query -query "drop $keyword if exists dbo.$name"
    }
}

# perform migrations
Write-Host "Perform migrations" -ForegroundColor Green
$migration_entities.Section | % {
    $section = $_
    Write-Host "> $section"
    $path = Join-Path $sql_migrations $section

    $migrations[$section].Keys | % {
        $name = $_

        if (!$migrations[$section][$name].Skipped) {
            Write-Host "  $name" -ForegroundColor Yellow
            $hash = $migrations[$section][$name].Hash
            $filename = Join-Path $path "$name.sql"
            $startDate = Get-Date
            &$sql_query -filename $filename
            $endDate = Get-Date

            &$sql_exec -name "SetMigration" -parameters @{
                section = $section
                name = $name
                hash = $hash
                startDate = $startDate
                endDate = $endDate
            }
        }
    }
}

Write-Host "Done!" -ForegroundColor Green
