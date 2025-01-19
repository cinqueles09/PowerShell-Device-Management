Enum SupportedWinSsprLogonScreenWindowsVersion {
  NotSupported
  RS4
  RS5
  R19H1
  R19H2
  R20H1
  R21H2
  R22H2
  Win1121H2
  Win1122H2
}

# Pre-PS5 compatible version for when we support Win7
#Add-Type -TypeDefinition @"
#   public enum SupportedWinSsprLogonScreenWindowsVersion
#   {
#     NotSupported,
#     RS4,
#     RS5
#   }
#"@

class Windows10ReleaseId {
  static [int]$RS4 = 1803
  static [int]$RS5 = 1809
  static [int]$R19H1 = 1903
  static [int]$R19H2 = 1909
  static [int]$R20H1 = 2004
  static [int]$R20H2 = 19042
  static [int]$R21H2 = 19044
  static [int]$R22H2 = 19045
}

class Windows11BuildId {
  static [int]$Win1121H2 = 22000 
  static [int]$Win1122H2 = 22621 
}



# Reg Paths #
$HKLMSoftwarePoliciesMicrosoftRegPath = "HKLM:\SOFTWARE\Policies\Microsoft"
$HKLMWinNTCurrentVersionRegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$HKLMWindowsCurrentVersionRegPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion"
$HKCUWindowsCurrentVersionRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion"
$HKCUWinNTCurrentVersionRegPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion"

$PersonalizationRegPath = $HKLMSoftwarePoliciesMicrosoftRegPath + "\Windows\Personalization"
$AppxPath = $HKLMSoftwarePoliciesMicrosoftRegPath + "\Windows\Appx"
$WinLogonRegPath = $HKLMWinNTCurrentVersionRegPath + "\Winlogon"
$NotificationsSettigsRegPath = $HKCUWinNTCurrentVersionRegPath + "\Notifications\Settings"
$HKLMPoliciesSystemRegPath = $HKLMWindowsCurrentVersionRegPath + "\Policies\System"
$HKCUPoliciesSystemRegPath = $HKCUWindowsCurrentVersionRegPath + "\Policies\System"
$CredentialProvidersPath = $HKLMWindowsCurrentVersionRegPath + "\Authentication\Credential Providers"
$LostModePath = $WinLogonRegPath + "\LostMode"
$AzureADAccountRegPath = $HKLMSoftwarePoliciesMicrosoftRegPath + "\AzureADAccount"

# Known Windows 10 Credential Providers #
[string[]]$defaultWin10CredentialProviders =
'01A30791-40AE-4653-AB2E-FD210019AE88', # Automatic Redeployment Credential Provider
'1b283861-754f-4022-ad47-a5eaaa618894', # Smartcard Reader Selection Provider
'1ee7337f-85ac-45e2-a23c-37c753209769', # Smartcard WinRT Provider
'2135f72a-90b5-4ed3-a7f1-8bb705ac276a', # PicturePasswordLogonProvider
'25CBB996-92ED-457e-B28C-4774084BD562', # GenericProvider
'27FBDB57-B613-4AF2-9D7E-4FA7A66C21AD', # TrustedSignal Credential Provider
'2D8B3101-E025-480D-917C-835522C7F628', # FIDO Credential Provider
'3dd6bec0-8193-4ffe-ae25-e08e39ea4063', # NPProvider
'48B4E58D-2791-456C-9091-D524C6C706F2', # Secondary Authentication Factor Credential Provider
'600e7adb-da3e-41a4-9225-3c0399e88c0c', # CngCredUICredentialProvider
'60b78e88-ead8-445c-9cfd-0b87f74ea6cd', # PasswordProvider / Logon PasswordReset
'8AF662BF-65A0-4D0A-A540-A338A999D36F', # FaceCredentialProvider
'8FD7E19C-3BF7-489B-A72C-846AB3678C96', # Smartcard Credential Provider
'94596c7e-3744-41ce-893e-bbf09122f76a', # Smartcard Pin Provider
'A910D941-9DA9-4656-8933-AA1EAE01F76E', # Remote NGC Credential Provider
'BEC09223-B018-416D-A0AC-523971B639F5', # WinBio Credential Provider
'C5D7540A-CD51-453B-B22B-05305BA03F07', # Cloud Experience Credential Provider
'C885AA15-1764-4293-B82A-0586ADD46B35', # IrisCredentialProvider
'cb82ea12-9f71-446d-89e1-8d0924e1256e', # PINLogonProvider
'D6886603-9D2F-4EB2-B667-1971041FA96B', # NGC Credential Provider
'e74e57b0-6c6d-44d5-9cda-fb2df5ed7435', # CertCredProvider
'F8A0B131-5F68-486c-8040-7E8FC3C85BB6', # WLIDCredentialProvider
'F8A1793B-7873-4046-B2A7-1F318747F427', # FIDO Credential Provider
'f64945df-4fa9-4068-a2fb-61af319edd33'  # RdpCredentialProvider

$DefaultWindowsCredentialProviders = [System.Collections.Generic.HashSet[Guid]]::new()
Foreach ($credProviderId in $defaultWin10CredentialProviders) {
  $DefaultWindowsCredentialProviders.Add([System.Guid]::New($credProviderId)) | out-null
}

# Global issue counter and methods that operate on it
$global:TotalIssuesFound = 0

Function Trace-PotentialBreakingIssue($description) {
  Write-Warning $description
  $global:TotalIssuesFound++
}

Function Write-DiagnosticsResults {
  if ($global:TotalIssuesFound -eq 0) {
    Write-Host "No issues detected!"
  }
  else {
    Write-Warning "$global:TotalIssuesFound issue(s) found that may prevent SSPR on the logon screen from working!"
  }
}

#Type Definitions
Add-Type -TypeDefinition @"
namespace SsprDiagnosticsTool
{
  using System;
  using System.Runtime.InteropServices;
  using System.Security.Principal;
  using System.Security.Permissions;
  using Microsoft.Win32.SafeHandles;
  using System.Runtime.ConstrainedExecution;
  using System.Security;

  public sealed class SafeTokenHandle : SafeHandleZeroOrMinusOneIsInvalid
  {
      private SafeTokenHandle()
          : base(true)
      {
      }

      [DllImport("kernel32.dll")]
      [ReliabilityContract(Consistency.WillNotCorruptState, Cer.Success)]
      [SuppressUnmanagedCodeSecurity]
      [return: MarshalAs(UnmanagedType.Bool)]
      private static extern bool CloseHandle(IntPtr handle);

      protected override bool ReleaseHandle()
      {
          return CloseHandle(handle);
      }
  }

  public class LogonUserHelper
  {
      [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
      public static extern bool LogonUser(
          String lpszUsername,
          String lpszDomain,
          String lpszPassword,
          int dwLogonType,
          int dwLogonProvider,
          out SafeTokenHandle phToken);

      [PermissionSetAttribute(SecurityAction.Demand, Name = "FullTrust")]
      public static SafeTokenHandle LogonUser(
          string userName,
          string domainName,
          string password,
          int logonType,
          int logonProvider)
      {
          SafeTokenHandle safeTokenHandle;

          bool returnValue = LogonUser(
              userName,
              domainName,
              password,
              logonType,
              logonProvider,
              out safeTokenHandle);

          if (false == returnValue)
          {
              int ret = Marshal.GetLastWin32Error();
              throw new System.ComponentModel.Win32Exception(ret);
          }

          return safeTokenHandle;
      }
  }
}
"@

# For GeneratePassword #
Add-Type -AssemblyName System.web

# Policy Checks #
Function Get-WindowsVersionSupportedForSsprLogonScreenExperience {
  $osVersion = [System.Environment]::OSVersion.Version

  If (-NOT ($osVersion.Major -eq 10)) {
    Write-Error "Windows 10 RS4 or greater is required for Azure AD password reset from the login screen"
    return [SupportedWinSsprLogonScreenWindowsVersion]::NotSupported
  }

  $releaseId = $(Get-ItemProperty -Path $HKLMWinNTCurrentVersionRegPath).releaseid
  $buildId = $(Get-ItemProperty -Path $HKLMWinNTCurrentVersionRegPath).currentbuildnumber
  If ($releaseId -lt [Windows10ReleaseId]::RS4) {
    Write-Error "Windows 10 RS4 or greater is required for Azure AD password reset from the login screen"
    return [SupportedWinSsprLogonScreenWindowsVersion]::NotSupported
  }
  ElseIf ($releaseId -le [Windows10ReleaseId]::RS4) {
    Write-Verbose "Windows 10 RS4 detected"
    return [SupportedWinSsprLogonScreenWindowsVersion]::RS4
  }
  ElseIf ($releaseId -le [Windows10ReleaseId]::RS5) {
    Write-Verbose "Windows 10 RS5 detected"
    return [SupportedWinSsprLogonScreenWindowsVersion]::RS5
  }
  ElseIf ($releaseId -le [Windows10ReleaseId]::R19H1) {
    Write-Verbose "Windows 10 19H1 detected"
    return [SupportedWinSsprLogonScreenWindowsVersion]::R19H1
  }
  ElseIf ($releaseId -le [Windows10ReleaseId]::R19H2) {
    Write-Verbose "Windows 10 19H2 detected"
    return [SupportedWinSsprLogonScreenWindowsVersion]::R19H2
  }
  # Check for Win11 builds
  ElseIf ($buildId -le [Windows11BuildId]::Win1121H2) {
    Write-Verbose "Windows 11 21H2 detected"
    return [SupportedWinSsprLogonScreenWindowsVersion]::Win1121H2
  }
  ElseIf ($buildId -le [Windows11BuildId]::Win1122H2) {
    Write-Verbose "Windows 11 22H2 detected"
    return [SupportedWinSsprLogonScreenWindowsVersion]::Win1122H2
  } 
  Else {
    Write-Warning "Unrecognized new version of Windows detected. Proceeding with the Windows 10 19H2 checks"
    return [SupportedWinSsprLogonScreenWindowsVersion]::R19H2
  }
}

Function Test-IsRunningAsSystem {
  $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
  If ($currentIdentity.Name -ne "NT AUTHORITY\SYSTEM") {
    Write-Warning "Script is not running as NT AUTHORITY\SYSTEM. Results may not be accurate"
  }
}

Function Test-IsRunningAsAdmin {
  $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
  $isInAdminRole = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  If (-Not $isInAdminRole) {
    Write-Warning "Script is not running as admin. You may encounter issues running this script"
  }
}

Function Test-NotificationsDisabledOnLockscreen($SupportedWinSsprLogonScreenWindowsVersion) {
  If ($SupportedWinSsprLogonScreenWindowsVersion -ne [SupportedWinSsprLogonScreenWindowsVersion]::RS4) {
    Write-Verbose "Skipping Lockscreen Notification Disabled Checks. This was fixed in RS5 onward"
    return
  }

  $allowNotificationsOnLockScreenKeyName = "NOC_GLOBAL_SETTING_ALLOW_TOASTS_ABOVE_LOCK"
  If (Test-RegistryKeyExists $NotificationsSettigsRegPath $allowNotificationsOnLockScreenKeyName) {
    $allowNotificationsOnLockScreenKeyValue = Get-RegistryKeyValue $NotificationsSettigsRegPath $allowNotificationsOnLockScreenKeyName
    If ($allowNotificationsOnLockScreenKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "Lock Screen notifications are disabled. This is a known issue on Win10 RS4 that may prevent SSPR from working"
    }
  }
}

Function Test-FastUserSwitchingDisabled {
  $hideFastSwitchingKeyName = "HideFastUserSwitching"
  If (Test-RegistryKeyExists $HKLMPoliciesSystemRegPath $hideFastSwitchingKeyName) {
    $hideFastSwitchingKeyValue = Get-RegistryKeyValue $HKLMPoliciesSystemRegPath $hideFastSwitchingKeyName
    If ($hideFastSwitchingKeyValue -ne 0) {
      Trace-PotentialBreakingIssue "Fast user switching is disabled. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-UACNotificationsDisabled {
  $enableLUAKeyName = "EnableLUA"
  If (Test-RegistryKeyExists $HKLMPoliciesSystemRegPath $enableLUAKeyName) {
    $enableLUAKeyValue = Get-RegistryKeyValue $HKLMPoliciesSystemRegPath $enableLUAKeyName
    If ($enableLUAKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "Windows UAC notifications are disabled (EnableLUA registry key is set to 0). This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-DontDisplayLastUsernameOnLogonScreen {
  $dontDisplayLastUserNameKeyName = "DontDisplayLastUserName"
  If (Test-RegistryKeyExists $HKLMPoliciesSystemRegPath $dontDisplayLastUserNameKeyName) {
    $dontDisplayLastUserNameKeyValue = Get-RegistryKeyValue $HKLMPoliciesSystemRegPath $dontDisplayLastUserNameKeyName
    If ($dontDisplayLastUserNameKeyValue -ne 0) {
      Trace-PotentialBreakingIssue "Last logged on username not being displayed on logon screen. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-LockScreenDisabled {
  $noLockScreenKeyName = "NoLockScreen"
  If (Test-RegistryKeyExists $PersonalizationRegPath $noLockScreenKeyName) {
    $noLockScreenKeyValue = Get-RegistryKeyValue $PersonalizationRegPath $noLockScreenKeyName
    If ($noLockScreenKeyValue -ne 0) {
      Trace-PotentialBreakingIssue "The lock screen is disabled. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-CtrlAltDeleteRequiredOnLockscreen($SupportedWinSsprLogonScreenWindowsVersion) {
  If ($SupportedWinSsprLogonScreenWindowsVersion -ne [SupportedWinSsprLogonScreenWindowsVersion]::RS4) {
    Write-Verbose "Skipping lockscreen disabled checks. This was fixed in RS5 onward"
    return
  }

  $disableCADKeyName = "DisableCAD"
  If (Test-RegistryKeyExists $WinLogonRegPath $disableCADKeyName) {
    $disableCADKeyValue = Get-RegistryKeyValue $WinLogonRegPath $disableCADKeyName
    If ($disableCADKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "Ctrl+Alt+Del is required on the logon screen. This is a known issue on Win10 RS4 that may prevent SSPR from working"
    }
  }
}

Function Test-SystemShellReplaced {
  $shellKeyName = "Shell"
  If (Test-RegistryKeyExists $WinLogonRegPath $shellKeyName) {
    $shellKeyValue = Get-RegistryKeyValue $WinLogonRegPath $shellKeyName
    If ($shellKeyValue -ne "explorer.exe") {
      Trace-PotentialBreakingIssue "System shell has been replaced. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-3rdPartyCredentialProviders {
  $credentialProvidersKeys = Get-ChildItem $CredentialProvidersPath
  ForEach ($credentialProvidersKey in $credentialProvidersKeys) {
    $credProviderId = [System.Guid]::New($credentialProvidersKey.PSChildName)
    If (-Not ($DefaultWindowsCredentialProviders.Contains($credProviderId))) {
      Trace-PotentialBreakingIssue (Get-CredentialProvidersDetailsString $credentialProvidersKey)
    }
  }
}

Function Get-CredentialProvidersDetailsString($credentialProvidersKey) {
  $providerName = (Get-ItemProperty -LiteralPath ("Registry::" + $credentialProvidersKey)).'(default)'
  $providerPath = $credentialProvidersKey
  $customDetailsObject += [pscustomobject]@{Name = $providerName; Path = $providerPath }
  $detailsTable = ($customDetailsObject | Format-List | Out-String).Trim()
  $warningString =
  @"
Unrecognized Credential Provider found. Some 3rd party Credential Providers may prevent SSPR from working.
{0}
"@ -f $detailsTable

  return $warningString
}

Function Test-LostModeEnabled {
  $enableLostModeKeyName = "EnableLostMode"
  If (Test-RegistryKeyExists $LostModePath $enableLostModeKeyName) {
    $enableLostModeKeyValue = Get-RegistryKeyValue $LostModePath $enableLostModeKeyName
    If ($enableLostModeKeyValue -ne 0) {
      Trace-PotentialBreakingIssue "Lost Mode is enabled. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-BlockNonAdminAppPackageInstallEnabled {
  $blockNonAdminUserInstallKeyName = "BlockNonAdminUserInstall"
  If (Test-RegistryKeyExists $AppxPath $blockNonAdminUserInstallKeyName) {
    $blockNonAdminUserInstallKeyValue = Get-RegistryKeyValue $AppxPath $blockNonAdminUserInstallKeyName
    If ($blockNonAdminUserInstallKeyValue -ne 0) {
      Trace-PotentialBreakingIssue "Non-admins are unable to initiate installation of Windows app packages (policy: BlockNonAdminUserInstall). This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-IsDeviceAADOrHybridJoined {
  $azureAdJoinedKeyName = "AzureAdJoined"
  $azureAdJoinedExpectedStatus = "AzureAdJoined : YES"
  $dsregCmdOutput = dsregcmd /status 
  if ($lastexitcode -ne 0) {
    Write-Error "dsregcmd.exe failed with error code $lastexitcode. Bailing on Test-IsDeviceAADOrHybridJoined check"
    return
  }
  
  $azureAdJoinedStatus = $dsregCmdOutput | Select-String -Pattern $azureAdJoinedKeyName
  if ($azureAdJoinedStatus -notmatch $azureAdJoinedExpectedStatus)
  {
    Trace-PotentialBreakingIssue "Current device is neither AAD-Joined nor Hybrid-Joined. This is a requirement for SSPR from the logon screen"
  }
}

Function Test-UsersNotInAllowLogonLocally {
  $isUsersInAllowedLogonLocally = $false
  $tmpFileName = [System.IO.Path]::GetTempFileName()

  secedit.exe /export /cfg "$($tmpFileName)" | Out-Null
  if ($lastexitcode -ne 0) {
    Write-Error "secedit.exe failed with error code $lastexitcode. Bailing on Test-UsersNotInAllowLogonLocally check"
    return
  }

  $tmpFileContent = Get-Content -Path $tmpFileName
  foreach ($entry in $tmpFileContent) {
    # The entry will look something like the following:
    # SeInteractiveLogonRight = Guest,*S-1-5-32-544,*S-1-5-32-545,*S-1-5-32-551
    if ( $entry -like "SeInteractiveLogonRight*") {
      $rightSide = $entry.Split("=")[1]
      $interactiveLogonRightMembersList = $rightSide.Split(",")
      foreach ($sid in $interactiveLogonRightMembersList) {
        $sidTrimmed = $sid.Trim()
        if ($sidTrimmed -like "*S-1-5-32-545") {
          $isUsersInAllowedLogonLocally = $true
          break
        }
      }
    }
  }

  if (-Not ($isUsersInAllowedLogonLocally)) {
    Trace-PotentialBreakingIssue '"Users" not in "Allow log on locally" policy. This is a known issue that may prevent SSPR from working"'
  }
}

Function Test-BackButtonEnabled {
  $disableBackButtonKeyName = "DisableBackButton"
  If (Test-RegistryKeyExists $WinLogonRegPath $disableBackButtonKeyName) {
    $disableBackButtonKeyValue = Get-RegistryKeyValue $WinLogonRegPath $disableBackButtonKeyName
    If ($disableBackButtonKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "The Winlogon DisableBackButton key is set to false. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-PasswordResetNotEnabled {
  $allowPasswordResetKeyName = "AllowPasswordReset"
  If (Test-RegistryKeyExists $AzureADAccountRegPath $allowPasswordResetKeyName) {
    $allowPasswordResetKeyValue = Get-RegistryKeyValue $AzureADAccountRegPath $allowPasswordResetKeyName
    If ($allowPasswordResetKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "The AllowPasswordReset registry key is set to 0. SSPR is not configured to run on this machine"
    }
  }
  else {
    Trace-PotentialBreakingIssue "Could not find AllowPasswordReset registry key. SSPR is not configured to run on this machine"
  }
}

Function Test-DelayedDesktopSwitchTimeout {
  # Note: This test requires checking against this key in both HKLM and HKCU
  $delayedDesktopSwitchTimeoutKeyName = "DelayedDesktopSwitchTimeout"

  If (Test-RegistryKeyExists $HKLMPoliciesSystemRegPath $delayedDesktopSwitchTimeoutKeyName) {
    $delayedDesktopSwitchTimeoutKeyValue = Get-RegistryKeyValue $HKLMPoliciesSystemRegPath $delayedDesktopSwitchTimeoutKeyName
    If ($delayedDesktopSwitchTimeoutKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "DelayedDesktopSwitchTimeout is set to 0 in HKLM. This is a known issue that may prevent SSPR from working"
    }
  }
  If (Test-RegistryKeyExists $HKCUPoliciesSystemRegPath $delayedDesktopSwitchTimeoutKeyName) {
    $delayedDesktopSwitchTimeoutKeyValue = Get-RegistryKeyValue $HKCUPoliciesSystemRegPath $delayedDesktopSwitchTimeoutKeyName
    If ($delayedDesktopSwitchTimeoutKeyValue -eq 0) {
      Trace-PotentialBreakingIssue "DelayedDesktopSwitchTimeout is set to 0 in HKCU. This is a known issue that may prevent SSPR from working"
    }
  }
}

Function Test-FirstLogonTimeout {
  $firstLogonKeyName = "FirstLogon"
  If (Test-RegistryKeyExists $WinLogonRegPath $firstLogonKeyName) {
    $firstLogonKeyValue = Get-RegistryKeyValue $WinLogonRegPath $firstLogonKeyName
    If ($firstLogonKeyValue -eq 1) {
      $firstLogonTimeoutKeyName = "FirstLogonTimeout"
      If (Test-RegistryKeyExists $HKLMPoliciesSystemRegPath $firstLogonTimeoutKeyName) {
        $firstLogonTimeoutKeyValue = Get-RegistryKeyValue $HKLMPoliciesSystemRegPath $firstLogonTimeoutKeyName
        If ($firstLogonTimeoutKeyValue -eq 0) {
          Trace-PotentialBreakingIssue "FirstLogonTimeout is set to 0. This is a known issue that may prevent SSPR from working"
        }
      }
    }
  }
}

# Utility Functions #
Function Test-RegistryKeyExists($path, $name) {
  Try {
    Get-ItemProperty -Path $path -Name $name
    return $true
  }
  Catch [System.Management.Automation.PSArgumentException] {
    Write-Debug "Registry Key Property missing"
    return $false
  }
  Catch [System.Management.Automation.ItemNotFoundException] {
    Write-Debug "Registry Key missing"
    return $false
  }
}

Function Get-RegistryKeyValue($path, $name) {
  return (Get-ItemProperty -Path $path -Name $name).$name
}

Function New-StrongPassword {
  $passwordLength = 14
  $numberOfNonAlphanumericCharacters = 6
  return [System.Web.Security.Membership]::GeneratePassword($passwordLength, $numberOfNonAlphanumericCharacters)
}

### Connectivity checks ###
Function Test-ConnectivityToAllNecessaryEndpoints {
  try {
    $pw = New-StrongPassword
    $testUserAccount = New-SsprLogonUserAccount $pw
    $userToken = Get-LocalUserAccountToken $testUserAccount.Name $pw
    $testUserWindowsIdentity = New-Object -TypeName System.Security.Principal.WindowsIdentity -ArgumentList $userToken.DangerousGetHandle()
    $testUserWindowsImpersonationContext = $testUserWindowsIdentity.Impersonate()

    Test-HttpEndpointConnectivity "https://passwordreset.microsoftonline.com/ok"
    # ToDo: Don't hardcode the JQuery version in the future
    Test-HttpEndpointConnectivity "https://ajax.aspnetcdn.com/ajax/jQuery/jquery-3.3.1.min.js"
  }
  catch {
    Write-Error $_.Exception.Message
  }
  finally {
    Invoke-DisposeIfNotNull $testUserWindowsImpersonationContext
    Invoke-DisposeIfNotNull $testUserWindowsIdentity
    Invoke-DisposeIfNotNull $userToken
    Remove-SsprLogonUserAccount $testUserAccount
  }
}

Function Invoke-DisposeIfNotNull($obj) {
  if ($null -ne $obj) {
    $obj.Dispose()
  }
}
Function Test-HttpEndpointConnectivity($uri) {
  $requestSucceeded = $false
  try {
    $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -ErrorAction Stop
    $requestSucceeded = $true
    $StatusCode = $response.StatusCode
  }
  catch {
    $requestException = $_.Exception

    $warningString =
    @"
  "Unexpected error received while contacting {0} :"
    {1}
"@ -f $uri, $requestException

    Trace-PotentialBreakingIssue $warningString
  }
  If ($requestSucceeded) {
    If ($StatusCode -eq 200) {
      Write-Verbose "Successfully connected to $uri"
    }
    Else {
      Trace-PotentialBreakingIssue "Unexpected status code ($StatusCode) received while contacting $uri"
    }
  }
}

Function Test-RdpStatusCheck {
  $users = (quser) -ireplace '\s{2,}',',' | convertfrom-csv
  $sessionname = $users.sessionname

  if ($sessionname -like "rdp-tcp*") {
    Write-Warning "Script running on RDP session. SSPR on Windows will not work on Hyper-V enhanced sessions."
  }
}

Function New-SsprLogonUserAccount($pw) {
  $passwordSecureString = ConvertTo-SecureString $pw -AsPlainText -Force
  $testAccountExpiryTime = (Get-Date).AddMinutes(2)
  $accountNameSuffixGuid = [System.Guid]::newguid().ToString().ToUpper()
  # strip out any non-alphanumeric characters
  $accountNameSuffixGuid -replace '[^A-Z0-9]', ''
  $accountName = "SSPR_TEST_" + $accountNameSuffixGuid.Substring($accountNameSuffixGuid.Length - 4);

  $user = New-LocalUser -Name $accountName `
    -Password $passwordSecureString `
    -AccountExpires $testAccountExpiryTime `
    -Description "Sspr Diagnostics Tool Test Account" `
    -UserMayNotChangePassword

  $user | Set-LocalUser -PasswordNeverExpires $true

  return $user
}

Function Remove-SsprLogonUserAccount($testUserAccount) {
  if ($null -ne $testUserAccount) {
    Remove-LocalUser -Name $testUserAccount.Name
  }
}

Function Get-LocalUserAccountToken($userName, $pw) {
  $LOGON32_PROVIDER_DEFAULT = 0
  $LOGON32_LOGON_INTERACTIVE = 2
  $domain = "."   # Local Account

  #Attempt a logon using this credential
  return [SsprDiagnosticsTool.LogonUserHelper]::LogonUser(
    $userName,
    $domain,
    $pw,
    $LOGON32_LOGON_INTERACTIVE,
    $LOGON32_PROVIDER_DEFAULT)
}

### START ###
$ErrorActionPreference = "Stop"
$windowsVersion = Get-WindowsVersionSupportedForSsprLogonScreenExperience
If ($windowsVersion -eq [SupportedWinSsprLogonScreenWindowsVersion]::NotSupported) {
  exit
}

### System Checks ###
Test-RdpStatusCheck
Test-IsRunningAsSystem
Test-IsRunningAsAdmin
Test-NotificationsDisabledOnLockscreen $windowsVersion
Test-CtrlAltDeleteRequiredOnLockscreen $windowsVersion
Test-FastUserSwitchingDisabled
Test-DontDisplayLastUsernameOnLogonScreen
Test-LockScreenDisabled
Test-SystemShellReplaced
Test-3rdPartyCredentialProviders
Test-LostModeEnabled
Test-UsersNotInAllowLogonLocally
Test-BackButtonEnabled
Test-DelayedDesktopSwitchTimeout
Test-PasswordResetNotEnabled
Test-FirstLogonTimeout
Test-UACNotificationsDisabled
Test-BlockNonAdminAppPackageInstallEnabled
Test-IsDeviceAADOrHybridJoined

### Connectivity Checks ###
Test-ConnectivityToAllNecessaryEndpoints

### Summary ###
Write-DiagnosticsResults
