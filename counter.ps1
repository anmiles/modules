<#
.SYNOPSIS
    Counter
.PARAMETER count
    Collect execution statistics and show formatted report
.PARAMETER length
    Length of the progress bar (and +2 symbols for brackets)
.PARAMETER title
    Title of the progress bar (can be set on any Tick)
.EXAMPLE
    $progress = Start-Progress 40; $progress.Tick()
    # initialize progress for 40 items; increment 1 item
#>

Function Sum-Object($obj){
    if ($obj.Values.Length -eq 0) { return $null }
    $type = ([System.Collections.ArrayList]$obj.Values)[0].GetType()
    $result = New-Object -TypeName $type.FullName
    $obj.Values | % { $result += $_ }
    return $result
}

class Counter {
    $titles = @()
    $counts = @{}
    $times = @{}
    $totalMilliseconds = 0
    $timestamp

    $columns = @(
        @{Label = "Action"; Align = 'Left'; Expression = { $this.GetExpression("Action", $_, $this.FormatAction) }},
        @{Label = "Count"; Align = 'Right'; Expression = { $this.GetExpression("Count", $_, $this.FormatCount) }},
        @{Label = "Speed"; Align = 'Right'; Expression = { $this.GetExpression("Speed", $_, $this.FormatSpeed) }},
        @{Label = "TotalTime"; Align = 'Right'; Expression = { $this.GetExpression("TotalTime", $_, $this.FormatTotalTime) }},
        @{Label = "Percent"; Align = 'Left'; Expression = { $this.GetExpression("Percent", $_, $this.FormatPercent) }}
    )
    
    Counter() {
        $this.Set()
    }

    [void] Set() {
        $this.timestamp = Get-Date
    }

    [void] Tick($title) {
        $this.Tick($title, 1)
    }

    [void] Tick($title, $count) {
        if ($count) {
            $time = ((Get-Date) - $this.timestamp)

            if (!$this.titles.Contains($title)) {
                $this.titles += $title
                $this.counts[$title] = 0
                $this.times[$title] = New-TimeSpan
            }

            $this.counts[$title] += $count
            $this.times[$title] += $time
            $this.totalMilliseconds += $time.TotalMilliseconds
        }
        
        $this.Set()
    }

    [object[]] Render() {
        $output = $this.titles | % { [PSCustomObject](@{Action = $_; Count = $this.counts[$_]; Time = $this.times[$_]}) }
        $output += [PSCustomObject](@{Action = $null})
        $output += [PSCustomObject](@{Action = "Total"; Count = 0; Time = Sum-Object($this.times)})
        return $output | Format-Table -Property $this.columns
    }

    hidden [string] GetExpression($header, $obj, $formatter) {
        if (!$obj.Action) { return "".PadRight($header.Length, "-") }
        return $formatter.Invoke($obj)
    }

    hidden [string] FormatAction($obj) {
        return $obj.Action
    }

    hidden [string] FormatCount($obj) {
        if ($obj.Count -eq 0) { return "" }
        return $obj.Count
    }

    hidden [string] FormatSpeed($obj) {
        if ($obj.Count -eq 0) { return "" }
        return '{0:n3}' -f ($obj.Time.TotalMilliseconds / (1000 * $obj.Count))
    }

    hidden [string] FormatTotalTime($obj) {
        return $obj.Time.ToString("G") -replace '^[0\D]+(.*)(\d\.\d+)$', '$1$2' -replace '(\.\d{3})\d*$', '$1'
    }

    hidden [string] FormatPercent($obj) {
        return ('{0:n0}%' -f (100 * $obj.Time.TotalMilliseconds / $this.totalMilliseconds)).PadLeft(4, " ") + " ".PadRight(50 * $obj.Time.TotalMilliseconds / $this.totalMilliseconds, "*")
    }
}

Function Start-Counter {
    return [Counter]::new()
}