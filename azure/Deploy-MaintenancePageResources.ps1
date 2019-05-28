param(
    [string]$ResourceEnvironmentName,
    [string]$ServiceName,
    [string]$ResourceGroupName,
    [string]$StorageAccountType = "Standard_LRS",
    [string]$CDNProfileName,
    [string]$CDNProfileResourceGroupName,
    [string]$CustomDomain = ""
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
Enable-AzStorageStaticWebsite -IndexDocument "index.htm" -ErrorDocument404Path "error.htm"

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

if ($CustomDomain) {
    $ExistingCustomDomain = Get-AzCdnCustomDomain -EndpointName $CDNEndpoint.Name -ProfileName $CDNProfile.Name -ResourceGroupName $CDNProfileResourceGroup.ResourceGroupName
    if (!$ExistingCustomDomain) {
        $CustomDomainConfig = @{
            CdnEndpoint      = $CDNEndpoint
            CustomDomainName = $CustomDomain.Replace(".", "-")
            HostName         = $CustomDomain
        }
        New-AzCdnCustomDomain @CustomDomainConfig | Enable-AzCdnCustomDomainHttps
    }
}

$SrcRootPath = "$PSScriptRoot/../src"

# --- Upload files to website root
$ProjectRootFiles = Get-ChildItem -Path $SrcRootPath -Include *.htm, *.html. *.txt -File
foreach ($File in $ProjectRootFiles) {
    Write-Host "-> Uploading $($File.Name) to website root"
    $null = Set-AzStorageBlobContent -File "$File" -Container "`$web" -Blob $File.Name -Properties @{"ContentType" = "text/html" } -Force
}

# --- Upload folders to correct path in container
$ProjectFolders = Get-ChildItem -Path $SrcRootPath -Exclude azure -Directory
foreach ($Folder in $ProjectFolders) {
    Write-Host "-> Uploading $($Folder.Name) maintenance pages"
    $StaticPages = Get-ChildItem -Path $Folder.FullName -Include *.htm, *.html, *.txt -Recurse

    foreach ($Page in $StaticPages) {
        Write-Host "    -> $($Page.Name)"
        $BlobName = "$($Folder.Name)/$($Page.Name)"
        $null = Set-AzStorageBlobContent -File "$Page" -Container "`$web" -Blob $BlobName -Properties @{"ContentType" = "text/html" } -Force
    }
}