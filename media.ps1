
Function NormalizeMediaFilename($name) {
	$ext = [IO.Path]::GetExtension($name).ToLower()
	$name = $name -replace "$ext$", ''
	$date = $null

	$ext = $ext.Replace(".jpeg", ".jpg")

	Function CreateDate($year, $month, $day, $hour, $minute, $second) {
		try {
			$date = [DateTime]::new($year, $month, $day, $hour, $minute, 0)
			$date = $date.AddSeconds($second)
			return $date
		} catch {
			return $null
		}
	}

	switch -regex ($name) {
		'^(\d{10})(\d{3})$' {
			$date = (Get-Date 01.01.1970) + [System.TimeSpan]::FromSeconds($matches[1])
			$name = $date.ToString("yyyy.MM.dd_HH.mm.ss")
			break
		}

		'^(IMG_|VID_|)(\d{4})\D?(\d{2})\D?(\d{2})\D(\d{2})\D?(\d{2})\D?(\d{2})\d*([\._]\d+)?( ?\(\d(\.\d)?\))?[+-]*([ _.].+)?$' {
			$date = CreateDate $matches[2] $matches[3] $matches[4] $matches[5] $matches[6] $matches[7]
			if ($date) { $name = "$($matches[2]).$($matches[3]).$($matches[4])_$($matches[5]).$($matches[6]).$($matches[7])$($matches[11])" }
			break
		}

		'^(\d{4})\D(\d{2})\D(\d{2})(_(\d{4}))?[+-]*([ _.].+)?$' {
			$date = CreateDate $matches[1] $matches[2] $matches[3] 0 0 $matches[5]
			if ($date) { $name = "$($matches[1]).$($matches[2]).$($matches[3])$($matches[4])$($matches[6])" }
			break
		}

		'^(\d{4})\D(\d{2})(_(\d{4}))?[+-]*([ _.].+)?$' {
			$date = CreateDate $matches[1] $matches[2] 1 0 0 $matches[4]
			if ($date) { $name = "$($matches[1]).$($matches[2])$($matches[3])$($matches[5])" }
			break
		}

		'^(\d{4})(_(\d{4}))?[+-]*([ _.].+)?$' {
			$date = CreateDate $matches[1] 1 1 0 0 $matches[3]
			if ($date) { $name = "$($matches[1])$($matches[2])$($matches[4])" }
			break
		}
	}

	return @{ Name = "$name$ext"; Date = $date }
}
