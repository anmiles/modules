Param ( 
    [Parameter(Mandatory = $true)][string]$environment_name,
    [Parameter(Mandatory = $true)][string]$terraform_name,
    [Parameter(Mandatory = $true)][string]$json_file,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$rules
)

$show_passed = $false
Import-Module $env:MODULES_ROOT\progress.ps1 -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Function GetConfig {
    if (!(Test-Path $json_file)) { throw "JSON file $json_file doesn't exist" }
    return Get-Content $json_file | ConvertFrom-Json
}

Function GetUrls($environment_name) {
    $tfvars_file = Join-Path $env:TERRAFORM_ROOT "$terraform_name/vars/environments/$environment_name.tfvars"
    if (!(Test-Path $tfvars_file)) { throw "Variables file $tfvars_file doesn't exist" }
    $tfvars = Get-Content $tfvars_file
    $urls = @{}

    $tfvars | % {
        if ($_ -match '"url.([a-z\.]+)"\s*=\s*"(.*?)"') { $urls[$matches[1]] = $matches[2] }
    }

    return $urls
}

Function TestPage($url, $code, $redirect) {
    $client = New-Object System.Net.WebClient
    $request = [System.Net.WebRequest]::Create($url)
    $request.Method = "HEAD"
    $request.Timeout = 10000
    $request.AllowAutoRedirect = $false

    try {
        $response = [System.Net.HttpWebResponse]$request.GetResponse()
        $response.close()
    } catch {
        $exception = $_.Exception

        while ($exception.InnerException -ne $null) {
            $exception = $exception.InnerException
        }

        if ($exception.getType() -eq [System.Net.WebException]) {
            $response = ([System.Net.WebException]$exception).Response
        } else {
            return "{Red:FAILED} {Yellow:$url} : {Red:$($exception.Message)} when requested"
        }
    }

    if ([int]$response.StatusCode -ne $code) {
        return "{Red:FAILED} {Yellow:$url} : status code is {Red:$([int]$response.StatusCode)} but expected {Green:$code}"
    }

    if ([int]$response.StatusCode -eq 301) {
        $location = $response.Headers["Location"]

        if (!$location) {
            return "{Red:FAILED} {Yellow:$url} : redirect is {Red:empty} but expected {Green:$redirect}"
        }

        if ($location -notmatch "https?://") {
            $location = "https://$($request.Host)$location"
        }

        $request = [System.Net.WebRequest]::Create($url)
        $request.Method = "HEAD"
        $request.Timeout = 5000

        try {
            $response = [System.Net.HttpWebResponse]$request.GetResponse()
            $response.close()
        } catch {
            $exception = $_.Exception

            while ($exception.InnerException -ne $null) {
                $exception = $exception.InnerException
            }

            if ($exception.getType() -eq [System.Net.WebException]) {
                $response = ([System.Net.WebException]$exception).Response
            } else {
                return "{Red:FAILED} {Yellow:$url} : {Red:$($exception.Message)} when redirecting"
            }
        }
        
        if ($response -ne $null) {
            $location = $response.responseUri.ToString() -replace '/?(#.*)?$', ""
        }

        if ($location -ne $redirect) {
            if ($location -eq $url) {
                return "{Red:FAILED} {Yellow:$url} : redirect is {Red:circular} but expected {Green:$redirect}"
            } else {
                return "{Red:FAILED} {Yellow:$url} : redirect is {Red:$location} but expected {Green:$redirect}"
            }
        }
    }

    if ($show_passed) {
        return "{Green:PASSED} {Yellow:$url}"
    } else {
        return $null
    }
}

$config = GetConfig
$urls = GetUrls $environment_name
$urls_live = GetUrls "live"
$all_rules = $rules -eq $null -or $rules.Count -eq 0 -or ($rules.Count -eq 1 -and $rules[0] -eq "")

$config.rules | % {
    if ($all_rules -or $rules.Contains($_.name)) {
        $progress = Start-Progress -title $_.name -count $_.checks.Length
    
        $_.checks | % {
            if ($_.disabled -eq "true") { continue }
            if ($_.stop -eq "true") { exit }

            $url = $_.url
            $code = $_.code
            $redirect = $_.redirect

            $urls.Keys | % {
                $url = $url.Replace($urls_live[$_], $urls[$_])
                if ($redirect) { $redirect = $redirect.Replace($urls_live[$_], $urls[$_]) }
            }

            $result = TestPage $url $code $redirect
            $progress.Tick()
            if ($result) { out $result }
        }
    }
}
