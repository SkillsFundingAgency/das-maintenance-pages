param(
    [string]$ResourceEnvironmentName,
    [string]$StorageAccountResourceGroup,
    [string]$StorageAccountName,
    [string]$SharedEnvResourceGroup,
    [string]$SharedCdnProfileName,
    [string]$CdnEndpointName
)

# Get Storage Account
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName -ErrorAction SilentlyContinue

if (!$StorageAccount) {
    throw "Storage Account $StorageAccountName in Resource Group $StorageAccountResourceGroup does not exist. Should be created from ARM template deployment."
}

$null = Set-AzCurrentStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName
Enable-AzStorageStaticWebsite -IndexDocument "index.htm" -ErrorDocument404Path "error.htm"


$CdnProfileResourceGroup = Get-AzResourceGroup -Name $SharedEnvResourceGroup -ErrorAction Stop
$CdnProfile = Get-AzCdnProfile -ProfileName $SharedCdnProfileName -ResourceGroupName $SharedEnvResourceGroup -ErrorAction Stop

$CdnEndpoint = Get-AzCdnEndpoint -EndpointName $CdnEndpointName -ProfileName $CdnProfile.Name -ResourceGroupName $CdnProfileResourceGroup.ResourceGroupName -ErrorAction SilentlyContinue

if (!$CdnEndpoint) {
    throw "Cdn Endpoint $CdnEndpointName in Resource Group $($CdnProfileResourceGroup.ResourceGroupName) does not exist. Should be created from ARM template deployment."
}

$SrcRootPath = "$PSScriptRoot/../src"

# --- Upload files to website root
$ProjectRootFiles = Get-ChildItem -Path $SrcRootPath -File
foreach ($File in $ProjectRootFiles) {
    Write-Host "-> Uploading $($File.FullName) to website root"
    $null = Set-AzStorageBlobContent -File "$($File.FullName)" -Container "`$web" -Blob $File.Name -Properties @{"ContentType" = "text/html" } -Force
}

# --- Upload folders to correct path in container
if ($ResourceEnvironmentName -eq "Test") {
    $ProjectFolders = Get-ChildItem -Path $SrcRootPath -Exclude azure,GatewayProd -Directory
    foreach ($Folder in $ProjectFolders) {
        Write-Host "-> Uploading $($Folder.Name) maintenance pages"
        $StaticPages = Get-ChildItem -Path $Folder.FullName -Include *.htm, *.html, *.txt -Recurse

        foreach ($Page in $StaticPages) {
            Write-Host "    -> $($Page.Name)"
            if ($Folder.Name -eq "GatewayTest" ) {
                $BlobName = "Gateway/$($Page.Name)"
            }
            else { 
                $BlobName = "$($Folder.Name)/$($Page.Name)"
            }
            $null = Set-AzStorageBlobContent -File "$Page" -Container "`$web" -Blob $BlobName -Properties @{"ContentType" = "text/html" } -Force
        }
    }
}
else {
    $ProjectFolders = Get-ChildItem -Path $SrcRootPath -Exclude azure,GatewayTest -Directory
    foreach ($Folder in $ProjectFolders) {
        Write-Host "-> Uploading $($Folder.Name) maintenance pages"
        $StaticPages = Get-ChildItem -Path $Folder.FullName -Include *.htm, *.html, *.txt -Recurse

        foreach ($Page in $StaticPages) {
            Write-Host "    -> $($Page.Name)"
            if ($Folder.Name -eq "GatewayProd" ) {
                $BlobName = "Gateway/$($Page.Name)"
            }
            else { 
                $BlobName = "$($Folder.Name)/$($Page.Name)"
            }
            $null = Set-AzStorageBlobContent -File "$Page" -Container "`$web" -Blob $BlobName -Properties @{"ContentType" = "text/html" } -Force
        }
    }
}