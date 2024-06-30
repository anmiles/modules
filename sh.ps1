<#
.SYNOPSIS
    Open sh console
.PARAMETER command
    Execute command in opened console
.PARAMETER title
    Set custom title for the opened console, if empty - set title equals to cmomand 
.PARAMETER path
    Set working directory for the console
.PARAMETER shell
    Shell to use (if not specified - use Git bash)
.PARAMETER envars
    Environment variables object
.PARAMETER new
    Whether to open new window
.PARAMETER wait
    Whether to not exit after executing a command
.PARAMETER background
    Whether new window should be opened in background
.PARAMETER debug
    Whether to output the command passed
.EXAMPLE
    sh
    # open sh console in the current directory
.EXAMPLE
    sh "npm install"
    # open sh console in the current directory and execure command "npm install"
.EXAMPLE
    sh "eslint ." "lint"
    # open sh console in the current directory, sets title "lint" and execute command "eslint ."
.EXAMPLE
    sh "npm run test" "test" "api"
    # open sh console in the directory "api", sets title "test" and execute command "npm run test"
#>

Param (
    [string]$command,
    [string]$title,
    [string]$path = ".",
    [ValidateSet('', 'git', 'wsl', 'cygwin')][string]$shell,
    [HashTable]$envars,
    [switch]$new,
    [switch]$wait,
    [switch]$background,
    [switch]$debug
)

if (!$shell) { $shell = $env:SH }

$bash = switch($shell) {
    "git" { "C:\Program Files\Git\bin\bash.exe" }
    "wsl" { "C:\Windows\system32\bash.exe" }
    "cygwin" { "C:\cygwin64\bin\bash.exe" } # cygwin bash doesn't receive environment variables from here
}

$prompt_color = switch($shell) {
    "git" { 36 }
    "wsl" { 33 }
    "cygwin" { 35 }
}

$root = switch($shell) {
    "git" { "/" }
    "wsl" { "/mnt/" }
    "cygwin" { "/mnt/" }
}

if (!(Test-Path $bash)) {
    out "{Red:Executable} {Yellow:$bash} {Red:doesn't exist for shell type '}{Green:$shell}{Red:'. Consider other shell types from the list:} {Green:('git', 'wsl', 'cygwin')}"
    exit 1
}

if ($debug) {
    out "{White:$command}"
}

$arguments = @()
$commands = @()

$path = (Resolve-Path $path).Path
if (!$title) { $title = Split-Path $path -Leaf }

$prompt_path = shpath $path -native:($shell -eq "wsl")

$interactive = !$command -or $new -or $wait

$envars.CUSTOM_PROMPT_COLOR = $prompt_color

$env:ENVARS.Split(",") | ? { $_ -ne "PATH" } | % {
    $var = [Environment]::GetEnvironmentVariable($_)
    if ($var -and $var.Contains("`n")) { return }
    $envars.$_ = shpath $var -native:($shell -eq "wsl")
}

$envars.NONINTERACTIVE = if ($interactive) { 0 } else { 1 }

$envars.Keys | % {
    $commands += "export $_=$($envars[$_])"
}

if ($command -and $new) {
    $prompt_prefix = git rev-parse --abbrev-ref HEAD 2>$null
    if (!$prompt_prefix) { $prompt_prefix = $shell }
    $commands += "printf '\033[$($prompt_color)m$prompt_prefix \033[0m\033[1;$($prompt_color)m$prompt_path>\033[0m $($command -replace "'", "'\''")\n'"
}

$commands += "cd $prompt_path"

if ($command) {
    $parts = $command -split " "

    if ($command.StartsWith("git -C ")) {
        $cd = $parts.IndexOf("-C")
        $parts[$cd + 1] = shpath $parts[$cd + 1] -native
        $command = $parts
    }

    if ($parts[0] -eq "git" -and $parts.Contains("push")) {
        $command = "$command 2>&1"
    }

    $commands += $command
}

$commands += "exitcode=\`$?"

if ($interactive) {
    $commands += "bash -i"
} else {
    $commands += "exit \`$exitcode >/dev/null 2>&1"
}

$b = if ($background) { ":b" } else { "" }
$n = if ($interactive) { ":n" } else { "" }

$arguments = @()
if ($new) { $arguments += "-new_console:t:`"$title`"$b$n" }
if (!$interactive) { $arguments += @("-i") }
$arguments += @("-c", "`"$($commands -Join ";")`"")
# Write-Host "& $bash $arguments"

Push-Location $HOME

try {
    & $bash $arguments
} catch {
    throw $_
} finally {
    Pop-Location
}

exit $LastExitCode
