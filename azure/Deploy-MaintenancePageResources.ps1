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
    $StorageAccount = New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -SkuName $StorageAccountType -Kind "StorageV2" -Location $ResourceGroup.Location
}

$null = Set-AzCurrentStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName

# Enable Static Hosting
if (!$StorageAccount.PrimaryEndpoints.Web) {
    Enable-AzStorageStaticWebsite -IndexDocument "index.html" -ErrorDocument404Path "error.html"
}


# Set up CDN Endpoint
$CDNEndpointName = "das-$ResourceEnvironmentName-$ServiceName-end"

$CDNProfileResourceGroup = Get-AzResourceGroup -Name $CDNProfileResourceGroupName -ErrorAction Stop
$CDNProfile = Get-AzCdnProfile -ProfileName $CDNProfileName -ResourceGroupName $CDNProfileResourceGroupName -ErrorAction Stop

$CDNEndpoint = Get-AzCdnEndpoint -EndpointName $CDNEndpointName -ProfileName $CDNProfile.Name -ResourceGroupName $CDNProfileResourceGroup.ResourceGroupName -ErrorAction SilentlyContinue

$CDNEndpointConfig = @{
    OriginName     = $StorageAccountName
    OriginHostName = $StorageAccount.PrimaryEndpoints.Web
}

if (!$CDNEndpoint) {
    $CDNEndpointConfig = @{
        EndpointName      = $CDNEndpointName
        ResourceGroupName = $CDNProfileResourceGroup.ResourceGroupName
        ProfileName       = $CDNProfile.Name
        Location          = $ResourceGroup.Location
        OriginName        = $StorageAccountName
        OriginHostName    = $StorageAccount.PrimaryEndpoints.Web
    }

    $CDNEndpoint = New-AzCdnEndpoint  @CDNEndpointConfig
}

# Upload Maintenance Pages
$ProjectFolders = Get-ChildItem -Path "$PSScriptRoot/.." -Exclude azure -Directory

foreach ($Folder in $ProjectFolders) {
    $StaticPages = Get-ChildItem -Path $Folder.FullName -Include *.htm, *.html -Recurse    

    foreach ($Page in $StaticPages) {
        $BlobName = "$($Folder.Name)/$($Page.Name)"
        (Set-AzStorageBlobContent -File "$Page" -Container "`$web" -Blob $BlobName -Properties @{"ContentType" = "text/html" } -Force).Name
    }
}