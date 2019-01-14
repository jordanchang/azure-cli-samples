<#
This script creates the resource group and resources for a multi-region Function App in the given environment.
Resources include storage, function app in 2 azure regions, traffic manager & endpoints, and app insights.
Naming convention is appname-environmentname-{location}-resourcetype, where location is used only when a resource 
is load balanced.

Examples: 
  helloworld-test-westus-functionapp
  helloworld-test-appinsights
#>

param ( 
    [Parameter(Mandatory=$true)]
    [ValidateSet("TEST", "PROD")]
    [String] 
    $environment,

    [String]
    $appName = "helloworld", # default app name

    [String]
    $subscription = "YourTestAzureSubscription", # default subscription

    [String]
    $primaryLocation = "WestUS2",

    [String]
    $secondaryLocation = "WestCentralUS",

    [String]
    $rgName = $appName + "-" + $environment.ToLower() + "-group",

    [String]
    $storageName = $appName.Replace("-", "") + $environment.ToLower(),

    [String]
    $trafficManagerName = $appName + "-" + $environment.ToLower() + "-" + "trafficmanager",

    [String]
    $appInsightsName = $appName + "-" + $environment.ToLower() + "-appinsights"
)

$ErrorActionPreference = "Stop"
$foregroundColor = "White"
$backgroundColor = "DarkGreen"

# Use colorized JSON
az configure --defaults output=jsonc

# select subscription
if($environment -eq "TEST"){
    $subscription = "YourTestAzureSubscription"
}
elseif($environment -eq "PROD"){
    $subscription = "YourProdAzureSubscription"
}

Write-Host "Selecting subscription" $subscription -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
az account set --subscription $subscription

# create new resource group
Write-Host "Creating resource group" -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
az group create --name $rgName --location $primaryLocation

# create storage account with encryption per AAG-EnforceStorageEncryption policy
Write-Host "Creating storage" -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
az storage account create --resource-group $rgName --name $storageName --location $primaryLocation --kind StorageV2  --sku Standard_LRS --encryption-services file --encryption-services blob

# create traffic manager
Write-Host "Creating traffic manager" -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
$trafficManagerDns = $appName + "-" + $environment
az network traffic-manager profile create --resource-group $rgName --name $trafficManagerName --routing-method Performance --unique-dns-name $trafficManagerDns

# create function app in primary & secondary locations
$functionAppName1 = $appName + "-" + $environment.ToLower() + "-" + $primaryLocation + "-functionapp"
$functionAppName2 = $appName + "-" + $environment.ToLower() + "-" + $secondaryLocation + "-functionapp"
Write-Host "Creating function apps" -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
az functionapp create --resource-group $rgName --name $functionAppName1 --storage-account $storageName --consumption-plan-location $primaryLocation
az functionapp create --resource-group $rgName --name $functionAppName2 --storage-account $storageName --consumption-plan-location $secondaryLocation

# Get function app ids
$functionAppId1=$(az functionapp show --resource-group $rgName --name $functionAppName1 --query id)
$functionAppId2=$(az functionapp show --resource-group $rgName --name $functionAppName2 --query id)

# add endpoints to traffic manager
Write-Host "Adding endpoint " $functionAppId1 -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
az network traffic-manager endpoint create --resource-group $rgName --profile-name $trafficManagerName --name $functionAppName1 --type AzureEndpoints --target-resource-id $functionAppId1
Write-Host "Adding endpoint " $functionAppId2 -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
az network traffic-manager endpoint create --resource-group $rgName --profile-name $trafficManagerName --name $functionAppName2 --type AzureEndpoints --target-resource-id $functionAppId2

# create application insight
Write-Host "Creating application insight" -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
$applicationInsightJson = '{ \"apiVersion\" : \"2014-04-01\", \"kind\" : \"web\", \"type\" : \"Microsoft.Insights/Components\", \"location\" : \"' + $primaryLocation + '\", \"properties\" : {\"ApplicationId\" : \"\"} }'
az resource create --resource-group $rgName --name $appInsightsName --resource-type "Microsoft.Insights/Components" --is-full-object --properties $applicationInsightJson

# get instrumentation key
$iKey = $(az resource show --resource-group $rgName --name $appInsightsName --resource-type "Microsoft.Insights/Components" --query  properties.InstrumentationKey)
Write-Host "Instrumentation Key is " $iKey -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor

# set InstrumentationKey in function apps
$iKeyAppSetting = "APPINSIGHTS_INSTRUMENTATIONKEY="+$iKey
Write-Host "Setting Instrumentation Key"
az functionapp config appsettings set --resource-group $rgName --name $functionAppName1 --settings $iKeyAppSetting
az functionapp config appsettings set --resource-group $rgName --name $functionAppName2 --settings $iKeyAppSetting
az functionapp config appsettings set --resource-group $rgName --name $functionAppName1 --settings FUNCTIONS_EXTENSION_VERSION=~2
az functionapp config appsettings set --resource-group $rgName --name $functionAppName2 --settings FUNCTIONS_EXTENSION_VERSION=~2

# # create redis cache
# $redisCacheName = $appName + "-" + $environment.ToLower() + "-" + "cache"
# az redis create --resource-group $rgName --name $redisCacheName --location $primaryLocation --sku Basic --vm-size C0