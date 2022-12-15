$patch_root = Join-Path $env:GIT_ROOT "patch"

Function AltPatchName($filename, $dirname) {
    if (![System.IO.Path]::IsPathRooted($filename)) {
        $filename = Join-Path $patch_root $filename
    }

    $dst = Split-Path $filename -Parent
    $dst = Join-Path $dst $dirname
    New-Item -Type Directory $dst -Force | Out-Null
    $dst = Join-Path $dst (Split-Path $filename -Leaf)
    return $dst
}

Function Patch {
    Param (
        [Parameter(Mandatory = $true)][string]$filename,
        [string]$command,
        [string]$moveTo
    )

    repo -name this -quiet -action {
        $result = @()

        $src = Join-Path $patch_root $filename
        $src = Get-ChildItem $src -File

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
                $dst = AltPatchName -filename $filename -dirname $moveTo
                Move-Item $filename $dst
                $result += $dst
            } else {
                $result += $filename
            }
        }

        return $result
    }
}
