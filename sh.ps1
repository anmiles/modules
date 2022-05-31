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
    [switch]$background,
    [switch]$debug
)

if (!$shell) { $shell = $env:SH }

$bash = switch($shell) {
    "git" { "C:\Program Files\Git\bin\sh.exe" }
    "wsl" { "C:\Windows\system32\bash.exe" }
    "cygwin" { "C:\cygwin64\bin\bash.exe" } # cygwin bash doesn't receive environment variables from here
}

$prompt_color = switch($shell) {
    "git" { 36 }
    "wsl" { 33 }
    "cygwin" { 35 }
}

if (!(Test-Path $bash)) {
    out "{Red:Executable} {Yellow:$bash} {Red:doesn't exist for shell type '}{Green:$shell}{Red:'. Consider other shell types from the list:} {Green:('git', 'wsl', 'cygwin')}"
    exit 1
}

if ($debug) {
    out "{White:$command}"
}

$path = (Resolve-Path $path).Path
if (!$title) { $title = Split-Path $path -Leaf }

$prompt_path = shpath -path $path -wsl:($shell -eq "wsl")

$arguments = @("-i")
$commands = @("cd $prompt_path")

$envars.CUSTOM_PROMPT_COLOR = $prompt_color

$env:ENVARS.Split(",") | ? { $_ -ne "PATH" } | % {
    $envars.$_ = shpath -path ([Environment]::GetEnvironmentVariable($_)) -wsl:($shell -eq "wsl")
}

$envars.Keys | % {
    $commands += "export $_=$($envars[$_])"
}

if ($command -and $new) {
    $prompt_prefix = git rev-parse --abbrev-ref HEAD 2>$null
    if (!$prompt_prefix) { $prompt_prefix = $shell }
    $commands += "printf '\033[$($prompt_color)m$prompt_prefix \033[0m\033[1;$($prompt_color)m$prompt_path>\033[0m $($command -replace "'", "'\''")\n'"
}

if ($command) {
    $commands += $command
}

$commands += "exitcode=`$?"

if (!$command -or $new) {
    $commands += "bash"
} else {
    $commands += "exit `$exitcode >/dev/null 2>&1"
}

$b = switch($background) {
    $true { ":b" }
    $false { "" }
}

$arguments += @("-c", "`"$($commands -Join ";")`"")

if ($new) {
    $arguments += "-new_console:t:`"$title`"$b"
    Start-Process $bash -ArgumentList $arguments
} else {
    & $bash $arguments
    $result = $?
}

if ($result -eq $false) { exit 1 }
