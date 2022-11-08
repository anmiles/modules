<#
.SYNOPSIS
    Timer
.DESCRIPTION
    Outputs elapsed time of each task and total elapsed time
.PARAMETER format
    Date format
#>

class Timer {
    [string]$format
    [string]$elapsedFormat
    [switch]$accurate
    [DateTime]$start_date
    [DateTime]$task_start_date
    [DateTime]$current_date
    [string]$task_title
    [TimeSpan]$elapsed
    [bool]$running
    [bool]$muted

    Timer([string]$format, [switch]$accurate) {
        $this.format = $format
        $this.accurate = $accurate
        $this.elapsedFormat = switch($accurate) {
            $true { "ss'.'fff" }
            $false { "mm':'ss" }
        }
        $this.elapsed = [TimeSpan]::new(0)
    }

    [Timer] Start() {
        out ""
        $this.Output("{Green:STARTED}", $true)
        return $this
    }

    [void] Finish() {
        if ($this.running) { $this.FinishTask() }
        $this.Output("{Green:FINISHED}", $false, $null, $this.elapsed)
        out ""
    }

    [void] StartTask([string]$title) {
        if ($this.running) { $this.FinishTask() }
        $this.running = $true

        $this.task_title = $title
        $this.Output("{Green:start} $($this.task_title)", $false)
        $this.task_start_date = $this.current_date
    }

    [void] FinishTask() {
        $this.running = $false
        $this.Output("{Green:finish} $($this.task_title)", $true, $this.task_start_date)
        $this.elapsed += $this.current_date - $this.task_start_date
    }

    [void]Output([string]$text, $underline, $from_date, $_elapsed){
        if ($this.muted) { return }

        if ($from_date -or $_elapsed) {
            $this.current_date = Get-Date
            if (!$_elapsed) { $_elapsed = ($this.current_date - $from_date) }
            $text += " {Gray:in} {Green:$($_elapsed.ToString($this.elapsedFormat))}"
        }

        out "[$($this.current_date.ToString($this.format))] $text" -ForegroundColor Yellow -underline:$underline

        if (!$from_date) {
            $this.current_date = Get-Date
        }
    }

    [void]Output([string]$text, $underline){
        $this.Output($text, $underline, $null, $null)
    }

    [void]Output([string]$text, $underline, $from_date){
        $this.Output($text, $underline, $from_date, $null)
    }

    [void]Mute(){
        $this.muted = $true
    }

    [void]Unmute(){
        $this.muted = $false
    }
}

Function Start-Timer {
    Param (
        [string]$format = "yyyy-MM-dd HH:mm:ss",
        [switch]$accurate
    )

    return [Timer]::new($format, $accurate).Start()
}
