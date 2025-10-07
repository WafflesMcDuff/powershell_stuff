<#
.SYNOPSIS
    This script can be used to update certificates on your Citrix NetScaler
.DESCRIPTION
    This script can be used to update certificates on your Citrix NetScaler. It relies on Posh-SSH Powershell Module (which it will install itself if missing). 
    At the moment, it only supports pfx files with no password. I will add password-protected pfx support later.
.PARAMETER NetScalerIP
    The IP address of your Citrix Netscaler
.PARAMETER User
    (Optional) Username for your Netscaler admin. Default is nsroot.
.PARAMETER nspasswordfile
    Path to the txt file containing your Netscaler admin password stored as secure string.
    To create the $nspasswordfile needed, run the following from powershell:
        C:\PS> read-host -assecurestring | convertfrom-securestring | out-file .\nspass.txt 
        Replace '.\nspass.txt' with whatever you want to call the nspass file
.PARAMETER pfxPath
    Path to the folder where your pfx file is stored.
.PARAMETER NSkeyPair
    This is the name of the certificate on the Netscaler you wish to update.
.PARAMETER pfxFileName
    (Optional)If specified, this will be the name of the pfx file you wish to upload.
    If not specified, the script will assume that your pfx file is called <$NSKeyPair>.pfx (i.e. If your NSKeyPair is called mycoolsitecert, then the default will be mycoolsitecert.pfx)
.EXAMPLE
    C:\PS> Update-NSC-cert.ps1 -NetScalerIP 192.168.1.3 -User nsroot -nspasswordfile .\nspass.txt -pfxPath C:\path\to\pfx\storage\folder -NSkeyPair mycoolwebsite
.NOTES
    Author: WafflesMcDuff
    Date:   October 7, 2025    
#>
#Requires -Version 5.1
 param (
    [Parameter(Mandatory=$true)][string]$NetScalerIP,
    [string]$User = "nsroot",
    # To create the $nspasswordfile needed, run the following from powershell:
    ## PS> 
    [Parameter(Mandatory=$true)][string]$nspasswordfile,
    [Parameter(Mandatory=$true)][string]$pfxPath,
    [Parameter(Mandatory=$true)][string]$NSkeyPair,
    [string]$pfxFileName,
    [string]$pfxPass
 )
 $FileDate = Get-Date -format "dd-MM-yyyy HH.mm"
 Start-Transcript "$pfxPath\$NskeyPair.log" -Append
 

###################

# PreReqs Check

###################
write-host "Powershell version:" $PSVersionTable.PSVersion
$poshcheck = Get-InstalledModule posh-ssh -ErrorAction SilentlyContinue
if ( !$poshcheck )
{
Write-Host -ForegroundColor Yellow "Posh-SSH Module is not installed. Installing...."
install-module posh-ssh -Repository PSGallery -force
}
Write-Host -ForegroundColor Green "Posh-SSH Module is installed. Importing Posh-SSH Module..."
import-module posh-ssh
$error[0].ErrorDetails


###########################

# Netscaler Section #

###########################

#Set Netscaler OS Creds
$password = Get-Content $nspasswordfile | ConvertTo-SecureString

$Credential = New-Object System.Management.Automation.PSCredential ($User, $Password)

#Set File Paths
if (!$pfxFileName){
 $pfxFileName = "$NSkeyPair.pfx"
 }
 else {
    if (!($pfxFileName.EndsWith(".pfx"))){
    $pfxFileName = "$pfxFileName.pfx"
    }
 }

$FilePath = "$pfxPath\$pfxFileName"

$SftpPath = '/tmp/'

$SftpFile = "$sftpPath$pfxFileName"

#Establish SFTP Connection
Write-Host "Connecting to SFTP..."
$SFTPSession = New-SFTPSession -ComputerName $NetScalerIP -Credential $Credential -AcceptKey

#Upload the file to SFTP
Write-Host "Uploading $filePath to $SftpPath..."
$UploadFile = Set-SFTPItem -SessionId ($SFTPSession).SessionID -Path $FilePath -Destination $SftpPath -Force -Verbose:($PSBoundParameters["Verbose"] -eq $true) -ErrorAction "Stop"

#Set-SFTPItem -SessionId ($SFTPSession).SessionID -LocalFile $FilePath -RemotePath $SftpPath -Overwrite

#Disconnect SFTP Session
Write-Host "Disconnecting from SFTP..."
if (Remove-SFTPSession -SessionID ($SFTPSession.SessionID))
{
Write-Host -foregroundcolor Green "SFTP Session successfully disconnected."
}
else {
write-host -foregroundcolor Red "SFTP Session not successfully disconnected. After script, please check Get-SFTPSession."
}


#Establish SSH Session
Write-Host "Connecting to SSH..."
$SSHConnection=New-SSHSession -ComputerName $NetScalerIP -Credential $Credential
if ($SSHConnection.Connected){
Write-Host -foregroundcolor green "Successfully connected to SSH."
}
else {
Write-Host -ForegroundColor red "Unable to connect to $NetScalerIP"
Return
}

#Update Cert KeyPair
Write-Host "Updating key for $NSKeyPair"
$UpdateKeyPair = Invoke-SSHCommand -Index 0 -Command "update ssl certkey $NSKeyPair -cert $SftpFile -key $SftpFile"
if ($UpdateKeyPair.ExitStatus -eq 0 ){
Write-Host -ForegroundColor Green "Successfully updated $NSKeyPair"
}
else {
$UpdateKeyPairError = $UpdateKeyPair.Error
write-host -ForegroundColor Red "$NSKeyPair not updated successfully. Reason: $UpdateKeyPairError"
Return 
}

#Save Config
Write-Host "Saving Config..."
$SaveConfig = Invoke-SSHCommand -Index 0 -Command "save config"
if ($SaveConfig.ExitStatus -eq 0 ){
Write-Host -ForegroundColor Green "Successfully saved config."
}
else {
$SaveConfigError = $SaveConfig.Error
write-host -ForegroundColor Red "Config not saved successfully. Reason: $SaveConfigError. Please try to save config manaully from the GUI."
Return 
}

#Exit
Write-Host "Exiting SSH Session..."
$ExitSSH = Invoke-SSHCommand -Index 0 -Command "exit" -InformationAction SilentlyContinue 
if ($SaveConfig.ExitStatus -eq 0 ){
Write-Host -ForegroundColor Green "Exited SSH successfully."
}
else {
$ExitSSHError = $ExitSSH.Error
write-host -ForegroundColor Red "Failed to exit SSH. Reason: $ExitSSHError."
Return 
}
#Kill SSH Session

Get-SSHSession | Remove-SSHSession | Out-Null

Stop-Transcript