Function Patch {
    Param (
        [Parameter(Mandatory = $true)][string]$filename,
        [string]$command,
        [string]$moveTo
    )

    repo -name this -quiet -action {
        $result = @()

        $root = Join-Path $env:GIT_ROOT ".patch"

        $src = $root
        $src = Join-Path $src $filename
        $src = Get-ChildItem $src -File -Recurse

        if ($src.Count -gt 1) {
            if (!(confirm "This will process multiple patches:{Green:`n- $($src.Name -Join "`n- ")`n}Continue")) {
                return
            }
        }

        $src | % {
            if ((Split-Path $_.DirectoryName -Leaf) -eq $moveTo) { return }

            out "{Green:- $($_.Name)}"
            $filename = $_.FullName
            $filename_sh = shpath $filename -native

            if ($command) {
                sh "$command $filename_sh"
            }

            if ($moveTo) {
                $dst = Split-Path $filename -Parent
                $dst = Join-Path $dst $moveTo
                New-Item -Type Directory $dst -Force | Out-Null
                $dst = Join-Path $dst (Split-Path $filename -Leaf)
                Move-Item $filename $dst
                $result += $dst
            } else {
                $result += $filename
            }
        }

        return $result
    }
}
