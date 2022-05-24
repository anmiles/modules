<#
.SYNOPSIS
    Inivaludate cloudfront distribution
.DESCRIPTION
    Inivaludate cloudfront distribution given its ID and one or more invalidation roots
.PARAMETER distribution_id
    Distribution id or full absolute url to be invalidated
.PARAMETER invalidation_roots
    Array of paths to invalidate all objects within them
.PARAMETER web_version
    Versioning suffix if versioning enabled
.PARAMETER async
    If switch specified - do not wait until invalidation finished
.EXAMPLE
    invalidate -distribution_id ABCDE123
    # invalidate all objects inside distribution ABCDE123 and wait until invalidation finished
.EXAMPLE
    invalidate -distribution_id ABCDE123 -invalidation_roots profiles/custom -async
    # invalidate all objects matching "/profiles/custom/*" inside distribution ABCDE123 and do not wait until invalidation finished
.EXAMPLE
    invalidate -distribution_id ABCDE123 -invalidation_roots Scripts,Images -web_version 49.2 -async
    # invalidate all objects matching any of @("/Scripts/v49.2/*" "/Images/v49.2/*") inside distribution ABCDE123 and do not wait until invalidation finished
#>

Param (
    [Parameter(Mandatory = $true)][string]$distribution_id,
    [string[]]$invalidation_roots,
    [string]$web_version,
    [switch]$async
)

$paths = switch ($invalidation_roots.Count) {
    0       { "/*" }
    default {
        $invalidation_roots | % {
            $invalidation_root = $_

            switch ($web_version) {
                ""      { "/$invalidation_root/*" }
                default { "/$invalidation_root/v$web_version/*" }
            }
        }
    }
} -join " "

$match = ([Regex]"https?:\/\/([^\/]+)(\/.*)$").Match($distribution_id)

if ($match.Success) {
    $domain = $match.Groups[1].Value
    $paths = @($match.Groups[2].Value + "*")
    $distributions = $(aws cloudfront list-distributions --query "DistributionList.Items[*].{Id:Id,Domain:Aliases.Items[0]}" --output json) | ConvertFrom-Json
    $distribution = $distributions | ? {$_.Domain -eq $domain}

    if (!$distribution) {
        throw "Cannot find distribution that have aliases matching to $domain"
    }

    $distribution_id = $distribution.Id
}

Write-Host "Invalidation started for distribution id $distribution_id using paths $paths" -ForegroundColor Green

aws configure set preview.cloudfront true
$invalidation = aws cloudfront create-invalidation --distribution-id $distribution_id --paths $paths | ConvertFrom-Json

if (!$async) {
    while ($invalidation.Invalidation.Status -ne "Completed") {
        Write-Host "Invalidation in progress..."
        $invalidation = aws cloudfront get-invalidation --distribution-id $distribution_id --id $invalidation.Invalidation.Id | ConvertFrom-Json
    }

    Write-Host "Invalidation finished!" -ForegroundColor Green
}
