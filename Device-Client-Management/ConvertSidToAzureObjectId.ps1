function Convert-AzureAdSIDtoObjectId{

	param([String] $Sid)
	
	$text = $sid.Replace('S-1-12-1-',"")
	$array = [UInt32[]]$text.Split('-')

	$bytes = New-Object 'Byte[]' 16
	[Buffer]::BlockCopy($array, 0, $bytes, 0, 16)
	[Guid]$guid = $bytes

	return $guid
}

$sid = read-host "Introduce el SID "
$objectId = Convert-AzureAdSIDToObjectId -Sid $sid
#Write-Output $objectId
Get-AzureADDirectoryRole | sort DisplayName | select-string $objectId
