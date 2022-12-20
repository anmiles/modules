Function Test-IIS-SMTP($solution_path, $recipient) {
	$subject = "Test message from Powershell"
	$body = "Test message from Powershell"
	$config_file = Join-Path $solution_path "web.config"
	$xml = [xml](Get-Content $config_file)
	$smtp = $xml.configuration."system.net".mailSettings.smtp
	$smtpMessage = New-Object System.Net.Mail.MailMessage($smtp.from, $recipient, $subject, $body)
	$smtpClient = New-Object Net.Mail.SmtpClient($smtp.network.host, $smtp.network.port)
	$smtpClient.EnableSsl = [bool]::Parse($smtp.network.enableSSL)
	$smtpClient.Credentials = New-Object System.Net.NetworkCredential($smtp.network.userName, $smtp.network.password)
	$smtpClient.Send($smtpMessage)
}
