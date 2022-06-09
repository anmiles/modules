Function Get-Combinations {
    Param ( 
        [Parameter(Mandatory = $true)][string]$query
    )

    [string[]]$combinations = @("")
    [string[]]$group = @()

    $query -replace '^\?', '' -replace '\?+', '?' -split '(\([^\)]*\)\??|[^\)]\?)' | % {
        $part = $_
        if ($part.Length -eq 0) { return }

        $group = switch ($true) {
            ($part.Length -eq 2 -and $part[1] -eq "?") {
                @("", $part[0])
            }
            ($part[0] -eq "(") {
                $variations = $part.Trim('()?').Split("|/")
                if ($part[$part.Length - 1] -eq "?") { $variations = @("") + $variations}
                $variations
            }
            default {
                $part
            }
        }

        $combinations_new = @()

        $group | % {
            $variation = $_
            $combinations_new += $combinations | % { $_ + $variation }
        }

        $combinations = $combinations_new
    }

    return $combinations | % { $_ -join "" }
}
