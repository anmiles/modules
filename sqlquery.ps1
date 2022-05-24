Param (
    [Parameter(Mandatory = $true)][string]$db_username,
    [Parameter(Mandatory = $true)][string]$db_password,
    [string]$sql_username,
    [string]$sql_password,
    [Parameter(Mandatory = $true)][string]$sql_endpoint,
    [Parameter(Mandatory = $true)][string]$db_name,
    [string]$query,
    [string]$filename,
    [string]$output,
    [string[]]$headers,
    [Switch]$overwrite
)

Import-Module $env:MODULES_ROOT\sql.ps1 -Force

if ($output) {
    if (Test-Path $output) {
        if ($overwrite) {
            Remove-Item $output -Force
        } else {
            Move-Item $output "$output.bak" -Force
        }
    } else {
        New-Item -Type Directory -Path (Split-Path $output -Parent) | Out-Null
    }
}

Function Output-Line($line) {
    if ($output) {
        file $output (($line -Join "`t") + "`r`n") -append
    } else {
        return $line
    }
}

$result = sql_query -query $query -filename $filename -db_name $db_name -sql_endpoint $sql_endpoint -sql_username $sql_username -sql_password $sql_password

$result | % {
    if (!$headersList) {
        $headersCount = $result[0].ItemArray.Length
        $headersList = $_.PSObject.Properties.Name | Select -First $headersCount | ? { !$headers -or $headers.Contains($_) }
        Output-Line $headersList
    }

    Output-Line ($_.PSObject.Properties | ? { $headersList.Contains($_.Name) } | % { $_.Value })
}
