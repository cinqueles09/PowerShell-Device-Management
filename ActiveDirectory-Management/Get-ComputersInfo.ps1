Get-ADComputer -Filter * -Properties Name, LastLogonDate, DistinguishedName, Enabled, OperatingSystem, OperatingSystemVersion |
Select-Object Name,
              OperatingSystem,
              OperatingSystemVersion,
              @{Name='LastLogonDate'; Expression={($_.LastLogonDate).ToString("dd/MM/yyyy HH:mm")}},
              DistinguishedName,
              Enabled |
Export-Csv -Path "ComputersLastLogon.csv" -NoTypeInformation -Encoding UTF8
