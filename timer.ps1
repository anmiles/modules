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
    [DateTime]$start_date
    [DateTime]$task_start_date
    [string]$task_title
    
    Timer([string]$format) {
        $this.format = $format
    }

    [Timer] Start() {
        out ""
        $this.start_date = $this.Output("{Green:STARTED}", $true)
        return $this
    }

    [void] Finish() {
        $this.Output("{Green:FINISHED}", $false, $this.start_date)
        out ""
    }

    [void] StartTask([string]$title) {
        $this.task_title = $title
        $this.task_start_date = $this.Output("{Green:start} $($this.task_title)", $false)
    }

    [void] FinishTask() {
        $this.Output("{Green:finish} $($this.task_title)", $true, $this.task_start_date)
    }

    [DateTime]Output([string]$text, $underline, $start_date){
        $current_date = Get-Date

        if ($start_date) {
            $elapsed = ($current_date - $start_date)
            $elapsedString = [Math]::Floor($elapsed.TotalMinutes).ToString()
            $elapsedString += ":" + $elapsed.Seconds.ToString().PadLeft(2, "0")
            $text += " {Gray:in} {Green:$elapsedString}"
        }

        out "[$($current_date.ToString($this.format))] $text" -ForegroundColor Yellow -underline:$underline

        return $current_date
    }

    [DateTime]Output([string]$text, $underline){
        return $this.Output($text, $underline, $null)
    }
}

Function Start-Timer {
    Param (
        [string]$format = "yyyy-MM-dd HH:mm:ss"
    )

    return [Timer]::new($format).Start()
}
