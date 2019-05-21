param(    
    [string]$ResourceEnvironmentName,
    [string]$ServiceName,
    [string]$ResourceGroupName,
    [string]$StorageAccountType = "Standard_LRS",
    [string]$CDNProfileName,
    [string]$CDNProfileResourceGroupName
)

$ResourceGroup = Get-AzResourceGroup -Name $ResourceGroupName
$StorageAccountName = "das$($ResourceEnvironmentName)$($ServiceName)str"


# Set up Storage Account
$StorageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue

if (!$StorageAccount) {
    Write-Host "-> Creating new storage account"
    $StorageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName $StorageAccountType -Kind "StorageV2" -Location $ResourceGroup.Location
}

$null = Set-AzCurrentStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
Enable-AzStorageStaticWebsite -IndexDocument "index.html" -ErrorDocument404Path "error.html"

$CDNEndpointName = "das-$ResourceEnvironmentName-$ServiceName-end"

$CDNProfileResourceGroup = Get-AzResourceGroup -Name $CDNProfileResourceGroupName -ErrorAction Stop
$CDNProfile = Get-AzCdnProfile -ProfileName $CDNProfileName -ResourceGroupName $CDNProfileResourceGroupName -ErrorAction Stop

$CDNEndpoint = Get-AzCdnEndpoint -EndpointName $CDNEndpointName -ProfileName $CDNProfile.Name -ResourceGroupName $CDNProfileResourceGroup.ResourceGroupName -ErrorAction SilentlyContinue

if (!$CDNEndpoint) {
    Write-Host "-> Creating CDN Endpoint"
    $CDNEndpointConfig = @{
        EndpointName      = $CDNEndpointName
        ResourceGroupName = $CDNProfileResourceGroup.ResourceGroupName
        ProfileName       = $CDNProfile.Name
        Location          = $ResourceGroup.Location
        OriginName        = $StorageAccountName
        OriginHostName    = ([Uri]$StorageAccount.PrimaryEndpoints.Web).Host
    }
    $CDNEndpoint = New-AzCdnEndpoint  @CDNEndpointConfig
}

$ProjectFolders = Get-ChildItem -Path "$PSScriptRoot/.." -Exclude azure -Directory

foreach ($Folder in $ProjectFolders) {
    Write-Host "-> Uploading $($Folder.Name) maintenance pages"
    $StaticPages = Get-ChildItem -Path $Folder.FullName -Include *.htm, *.html -Recurse    

    foreach ($Page in $StaticPages) {
        Write-Host "    -> $($Page.Name)"
        $BlobName = "$($Folder.Name)/$($Page.Name)"
        $null = Set-AzStorageBlobContent -File "$Page" -Container "`$web" -Blob $BlobName -Properties @{"ContentType" = "text/html" } -Force
    }
}