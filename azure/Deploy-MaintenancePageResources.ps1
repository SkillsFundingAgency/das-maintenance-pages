param(
    [string]$ResourceEnvironmentName,
    [string]$StorageAccountResourceGroup,
    [string]$StorageAccountName,
    [string]$AfdProfileResourceGroup,
    [string]$AfdProfileName,
    [string]$AfdEndPointName
)

# Get Storage Account
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName -ErrorAction SilentlyContinue

if (!$StorageAccount) {
    throw "Storage Account $StorageAccountName in Resource Group $StorageAccountResourceGroup does not exist. Should be created from ARM template deployment."
}

$null = Set-AzCurrentStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName
Enable-AzStorageStaticWebsite -IndexDocument "index.htm" -ErrorDocument404Path "error.htm"


$AfdProfileRg = Get-AzResourceGroup -Name $AfdProfileResourceGroup -ErrorAction Stop
$AfdProfile = Get-AzFrontDoorCdnProfile -ProfileName $AfdProfileName -ResourceGroupName $AfdProfileResourceGroup -ErrorAction Stop

$AfdEndpoint = Get-AzFrontDoorCdnEndpoint -EndpointName $AfdEndPointName -ProfileName $AfdProfile.Name -ResourceGroupName $AfdProfileRg.ResourceGroupName -ErrorAction SilentlyContinue

if (!$AfdEndpoint) {
    throw "AFD Endpoint $AfdEndPointName in Resource Group $($AfdProfileRg.ResourceGroupName) does not exist. Should be created from ARM template deployment."
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