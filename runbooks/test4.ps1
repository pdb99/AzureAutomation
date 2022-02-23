$resourceGroup = "AutomationTest"
$keyVault = "kv-pdb"
$secretUsername = "AutomationTestUsername"
$secretPassword = "AutomationTestPassword"
$sqlServerName = 'sql-server-test1'
$databaseName = "TestDB2"
$secretStorageKey = "AutomationTestStorageKey"
$secretStorageAccount = "AutomationTestStorageAccount"
$blobContainerName = "runbook"
$RetentionDays = 6



# Ensures you do not inherit an AzContext in your runbook
Disable-AzContextAutosave -Scope Process | Out-Null

# Connect using a Managed Service Identity
try {
        $AzureContext = (Connect-AzAccount -Identity).context
    }
catch{
        Write-Output "There is no system-assigned user identity. Aborting."; 
        exit
    }

# set and store context
$AzureContext = Set-AzContext -Subscription 'Visual Studio Professional with MSDN' `
    -DefaultProfile $AzureContext
    


# Retrieve values from Key Vault
$adUsername = Get-AzKeyVaultSecret -VaultName $keyVault -Name $secretUsername -AsPlainText
$adPassword  = (Get-AzKeyVaultSecret -VaultName $keyVault -Name $secretPassword).SecretValue
$storageKey = Get-AzKeyVaultSecret -VaultName $keyVault -Name $secretStorageKey -AsPlainText
$storageAccount = Get-AzKeyVaultSecret -VaultName $keyVault -Name $secretStorageAccount -AsPlainText

Write-Verbose "Starting database export of database '$databaseName'" -Verbose
#$securePassword = ConvertTo-SecureString –String $azureADDatabasePassword –AsPlainText -Force 
#$creds = New-Object –TypeName System.Management.Automation.PSCredential –ArgumentList $azureADDatabaseUsername, $securePassword

$bacpacFilename = $databaseName + (Get-Date).ToString("yyyyMMddHHmm") + ".bacpac"
$bacpacUri = "https://" + $storageAccount + ".blob.core.windows.net/" + $blobContainerName + "/" + $bacpacFilename

Write-Output "New-AzSqlDatabaseExport -ResourceGroupName $resourceGroup –ServerName $sqlServerName `
–DatabaseName $databaseName –StorageKeytype "StorageAccessKey" –storageKey $storageKey -StorageUri $BacpacUri `
–AdministratorLogin $adUsername –AdministratorLoginPassword $adPassword -AuthenticationType ADPassword"

$exportRequest = New-AzSqlDatabaseExport -ResourceGroupName $resourceGroup –ServerName $sqlServerName `
    –DatabaseName $databaseName –StorageKeytype "StorageAccessKey" –storageKey $storageKey -StorageUri $BacpacUri `
    –AdministratorLogin $adUsername –AdministratorLoginPassword $adPassword -AuthenticationType ADPassword
    
    # Print status of the export
Get-AzSqlDatabaseImportExportStatus -OperationStatusLink $exportRequest.OperationStatusLink


# Check previous backups
$StorageContext = New-AzStorageContext -StorageAccountName $storageAccount -StorageAccountKey $storageKey


# Check that how many 'good' backups there are by checking for files larger than 100000 bytes (as it will create a small backup file even if it fails)
$goodBackupCount = (Get-AzStorageBlob -Container $blobContainerName -Context $storageContext | Where-Object {$_.Length -gt 100000}).Count

Write-Output "'$goodBackupCount' good backups found"

# Remove backups older than the retention period (as long as there are 2 good backups)
if ($goodBackupCount -ge 2)
{
	Write-Output "Removing backups older than '$retentionDays' days from blob: '$blobContainerName'"
	$isOldDate = [DateTime]::UtcNow.AddHours(-$retentionDays)
	$blobs = Get-AzStorageBlob -Container $blobContainerName -Context $storageContext

	foreach ($blob in ($blobs | Where-Object { $_.LastModified.UtcDateTime -lt $isOldDate -and $_.BlobType -eq "BlockBlob" })) 
	{
		Write-Verbose ("Removing blob: " + $blob.Name) -Verbose
		Remove-AzStorageBlob -Blob $blob.Name -Container $blobContainerName -Context $storageContext
	}
}
else
{
	Write-Output "Currently only '$goodBackupCount' good backups"
}









