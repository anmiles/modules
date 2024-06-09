Function GetTextDistance($text1, $text2) {
	$len1 = $text1.Length;
	$len2 = $text2.Length;

	if ($len1 -eq 0) { return $len2 }
	if ($len2 -eq 0) { return $len1 }

	$diff = New-Object 'int[,]' $($len1 + 1), $($len2 + 1)

	0..$len1 | % { $diff[$_, 0] = $_ }
	0..$len2 | % { $diff[0, $_] = $_ }

	1..$len1 | % {
		$x = $_

		1..$len2 | % {
			$y = $_
			$result = 1 - ($text2[$y - 1] -eq $text1[$x - 1])

			$values = @(
				($diff[($x - 1), $y] + 1),
				($diff[$x, ($y - 1)] + 1),
				($diff[($x - 1), ($y - 1)] + $result)
			)

			$diff[$x, $y] = ($values | Measure -Minimum).Minimum
		}
	}

	return $diff[$len1, $len2]
}

Function GetAllClosest($text, $variants, $property) {
	$distances = @{}

	$variants | % {
		$variant = $_
		if ($property) { $variant = $variant.$property }
		$distance = GetTextDistance $variant $text
		if (!$distances[$distance]) { $distances[$distance] = @() }
		$distances[$distance] += $_
	}

	return $distances.Keys | Sort | % { $distances[$_] }
}

Function GetClosest($text, $variants, $property) {
	return (GetAllClosest $text $variants $property)[0]
}
