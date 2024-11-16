<#
.SYNOPSIS
    Progress bar
.PARAMETER count
    Amount of ticks to fill progress bar
.PARAMETER length
    Length of the progress bar (and +2 symbols for brackets)
.PARAMETER title
    Title of the progress bar (can be set on any Tick)
.PARAMETER fillColor
    Color of the progress bar
.EXAMPLE
    $progress = Start-Progress 40; $progress.Tick()
    # initialize progress for 40 items; increment 1 item
#>

class ProgressBar {
    [int]$count
    [int]$length
    [int]$threshold
    [string]$title
    [int]$current = 0
    [int]$current_set = 0
    [int]$left = 0
    [int]$top = 0
    [int]$position = 0
    [int]$titleLength
    [char]$open = '['
    [char]$close = ']'
    [char]$fill = '.'
    [string]$fillColor = [ConsoleColor]::White
    [bool]$inline = !([console]::IsOutputRedirected)

    ProgressBar([int]$count, [int]$length, [string]$title, [string]$fill, [string]$fillColor) {
        $this.count = $count
        $this.length = $length
        $this.threshold = [Math]::Max(1, [Math]::Floor($count / ($length * 2)))
        $this.title = $title
        $this.fill = $fill
        $this.fillColor = $fillColor
        $this.position = $this.titleLength = $this.title.Length
        #$this.inline = $false
    }

    [ProgressBar] Start() {
        if ($this.inline) {
            $this.left = [console]::CursorLeft
            $this.top = [console]::CursorTop

            if ($this.left -gt 0) {
                Write-Host " " -NoNewline
                $this.left = $this.left + 1
            }

            Write-Host $this.open -NoNewline -ForegroundColor Green
            Write-Host $this.title -NoNewline -ForegroundColor White
            [console]::SetCursorPosition($this.left + $this.length + 1, $this.top)
            Write-Host $this.close -ForegroundColor Green
        } else {
            if ($this.title) {
                Write-Host $this.open -NoNewline -ForegroundColor Green
                Write-Host $this.title -NoNewline -ForegroundColor White
                Write-Host $this.close -ForegroundColor Green
            }
        }

        return $this
    }

    [void] Tick() {
        $this.Tick(1)
    }

    [void] Tick([int]$step) {
        $this.Tick($step, $this.title)
    }

    [void] Tick([int]$step, [string]$title) {
        $this.Set($this.current + $step, $title)
    }

    [void] Set([int]$current) {
        $this.Set($current, $this.title)
    }

    [void] Set([int]$current, [string]$title) {
        $this.current = $current
        $this.current = [Math]::Min($this.current, $this.count)

        if ($this.threshold -gt 1 -and $current -lt $this.current_set + $this.threshold) {
            return
        }

        if ($title -ne $this.title) {
            $this.title = $title
            $this.titleLength = [Math]::Max($this.titleLength, $this.title.Length)

            if ($this.inline) {
                $prev_left = [console]::CursorLeft
                $prev_top = [console]::CursorTop
                [console]::SetCursorPosition($this.left + 1, $this.top)
                Write-Host $this.title -NoNewline -ForegroundColor White

                ($this.title.Length .. $this.titleLength) | % {
                    Write-Host $this.fill -NoNewline -ForegroundColor $this.fillColor
                }

                [console]::SetCursorPosition($prev_left, $prev_top)
            } else {
                if ($this.title) {
                    Write-Host $this.open -NoNewline -ForegroundColor Green
                    Write-Host $this.title -NoNewline -ForegroundColor White
                    Write-Host $this.close -ForegroundColor Green
                }
            }
        }

        $this.current_set = $this.current
        $prev_position = [Math]::Max($this.position, $this.titleLength)
        $this.position = $this.title.Length + [Math]::Floor(($this.length - $this.title.Length) * $this.current / $this.count)

        if ($this.position -gt $prev_position) {
            if ($this.inline) {
                $prev_left = [console]::CursorLeft
                $prev_top = [console]::CursorTop
                [console]::SetCursorPosition($this.left + $prev_position + 1, $this.top)

                ($prev_position .. ($this.position - 1)) | % {
                    Write-Host $this.fill -NoNewline -ForegroundColor $this.fillColor
                }

                [console]::SetCursorPosition($prev_left, $prev_top)
            } else {
                Write-Host "$([Math]::Round(100 * $this.current / $this.count))%" -ForegroundColor White
            }
        }
    }
}

Function Start-Progress {
    Param (
        [Parameter(Mandatory = $true)][int]$count,
        [int]$length = 100,
        [string]$title = "",
        [string]$fill = ".",
        [string]$fillColor = [ConsoleColor]::White
    )

    return [ProgressBar]::new($count, $length, $title, $fill, $fillColor).Start()
}
