<#
.SYNOPSIS
creates a Python Azure Function App and deploys a boilerplate HTTP function via an Azure DevOps pipeline

.DESCRIPTION
handles the required overhead involved with using Azure Functions in production, in terms of:
- resource provisioning and configuration in Azure
- automatic, initial deployment of Python Azure Function V2 programming model code out of a complementary assortment of Function samples (as well as a corresponding suite of unittests)
- setup of E-Mail alerts regarding resource bottlenecks and exceptions
- Azure DevOps configuration

.EXAMPLE
PS> ./create-py-function-app.ps1 'westeurope'

.EXAMPLE
PS> ./create-py-function-app.ps1 -AzureStorageGeoLocation 'westeurope' -AzureResourcesPrefix 'SplunkUtils' -DevOpsProject 'IT-Security' -DevOpsOrg 'https://dev.azure.com/illnevertell' -AbsoluteTargetRepoPathPrefix 'C:\Users\GOERLERLUI\repos'
#>

param(
    [string]
    # geographic location for the Azure resources that will be created
    [Parameter(Mandatory)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        @(
            'eastus',
            'southeastasia',
            'northeurope',
            'swedencentral',
            'westeurope',
            'centralus',
            'centralindia',
            'eastasia',
            'canadacentral',
            'polandcentral',
            'uaenorth',
            'qatarcentral',
            'asia',
            'asiapacific',
            'australia',
            'brazil',
            'canada',
            'europe',
            'france',
            'germany',
            'global',
            'india',
            'japan',
            'korea',
            'norway',
            'singapore',
            'southafrica',
            'switzerland',
            'uae',
            'uk',
            'westus',
            'southindia',
            'westindia',
            'canadaeast',
            'uaecentral'
        ) | Where-Object {
            $_ -like "*$wordToComplete*"
        } | ForEach-Object {
            "'$_'"
        }
    })]
    $AzureStorageGeoLocation,
    # prefix for the names of the Azure resources (actually determines the "core" of the names, only a small resource-type-dependent suffix will be appended) (overrides value in config file)
    $AzureResourcesPrefix,
    # your Azure DevOps project (overrides value in config file)
    $DevOpsProject,
    # your Azure DevOps organization (overrides value in config file)
    $DevOpsOrg,
    # absolute local filepath to the folder that should contain the local clone of the DevOps git repository that will be created
    $AbsoluteTargetRepoPathPrefix,
    [switch]
    # instead of asking for confirmation to proceed, exit directly after the prevalidation step
    $PrevalidationOnly
)


$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0


# git sometimes outputs informational messages on stderr
$env:GIT_REDIRECT_STDERR = '2>&1'
$ConfigFile = 'cfg/config.json'
$TargetRepoPathPrefix = "$PSScriptRoot"


function Login-ToDevOpsWriteInfo() {
    Write-Host '=====Authenticating and configuring DevOps extension'
    Login-ToDevOps -DevOpsOrg "$($Cfg.devOpsOrg)" -Project "$($Cfg.devOpsProject)" -NoCleanup
}

function Identify-ResourceToReuse([string]$ResourceType, [bool]$ReuseOnly) {
    switch ($ResourceType) {
        'group' {
            $FoundResources = az group list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = 'Resource Groups'
        }
        'functionapp' {
            $FoundResources = az functionapp list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = 'Function Apps'
        }
        'appservice plan' {
            $FoundResources = az appservice plan list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = 'App Service Plans'
        }
        'storage account' {
            $FoundResources = az storage account list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = 'Storage Accounts'
        }
        'keyvault' {
            $FoundResources = az keyvault list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = 'Key Vaults'
        }
        default {
            Write-Error "`"Identify-ResourceToReuse`" received unexpected value: `"$ResourceType`""
        }
    }

    if ($FoundResources.length -eq 1) {
        Write-Warning "`"$($FoundResources[0].name)`" matches the configured prefix, will use that resource instead of creating any new $Descriptor"
        return $FoundResources[0]
    } elseif ($FoundResources.length -eq 0) {
        if ($ReuseOnly)  {
            Write-Error "Found 0 $Descriptor matching the configured prefix, expected to find exactly 1"
        } else {
            return $null
        }
    } else {
        Write-Error "Found $($FoundResources.length) $Descriptor matching the configured prefix, 1 or 0 would have been acceptable"
    }
}

function Perform-EarlyAzLogout() {
    az logout
    $global:LoginInfo = $null
    Write-Host 'OK: Logged out of Azure'
}

function Perform-EarlyDevOpsLogout() {
    az devops logout
    $global:DevOpsPat = $null
    Write-Host 'OK: Logged out of Azure DevOps'
}


Write-Host '=====Initiating prevalidation'

Write-Host '=======Checking local dependencies'
try {
    git -v | Out-Null
} catch {
    Write-Error "Seems like you don't have git installed"
}
try {
    az -v | Out-Null
} catch {
    Write-Error "Seems like you don't have the Azure CLI installed"
}
Write-Host 'OK: Local dependency check passed'
Write-Warning 'Logging you out of Azure and Azure DevOps, just in case'
try {
    az logout *>$null
    $global:LoginInfo = $null
} catch { }
try {
    az devops logout *>$null
    $global:DevOpsPat = $null
} catch { }

Write-Host "=======Reading configuration from $ConfigFile"
if (-Not (Test-Path "$PSScriptRoot/$ConfigFile")) {
    Write-Error "Could not find config file under `"$PSScriptRoot/$ConfigFile`""
}
$Cfg = Get-Content "$PSScriptRoot/$ConfigFile" | ConvertFrom-Json
if (-Not (Get-Member -inputobject $Cfg -name 'devOpsRepoName')) {
    Write-ToObj $Cfg 'devOpsRepoName' "$($Cfg.azureResourcesPrefix)"
}
$CreateKeyVault = (Get-Member -inputobject $Cfg -name 'createKeyVault') -and $Cfg.createKeyVault
if (-Not $CreateKeyVault) {
    Write-Warning 'Will be skipping the creation of a Key Vault'
}
$CreateMinApprovalPolicy = (Get-Member -inputobject $Cfg -name 'defaultPullReviewerMailAddresses') -and $Cfg.defaultPullReviewerMailAddresses.Length -ge 3
if (-Not $CreateMinApprovalPolicy) {
    Write-Warning 'Will be skipping the creation of a policy for minimum PR approval count because there are not enough values specified under "defaultPullReviewerMailAddresses"'
}
$CreateAlerts = (Get-Member -inputobject $Cfg -name 'alertRecipientMailAddresses') -and $Cfg.alertRecipientMailAddresses.Length -ge 1
if (-Not $CreateAlerts) {
    Write-Warning 'Will be skipping the creation of E-Mail alerts because there are not enough values specified under "alertRecipientMailAddresses"'
}
Write-Host 'OK: Read config file'

Write-Host '=======Overriding configuration provided via file with given command line arguments'
if ($AzureResourcesPrefix) { Write-ToObj $Cfg 'azureResourcesPrefix' $AzureResourcesPrefix }
if ($DevOpsProject) { Write-ToObj $Cfg 'devOpsProject' $DevOpsProject }
if ($DevOpsOrg) { Write-ToObj $Cfg 'devOpsOrg' $DevOpsOrg }

$RepoUrl = -join($Cfg.devOpsOrg, '/', $Cfg.devOpsProject, '/_git/', $Cfg.devOpsRepoName)
$PrefixQuery = "[?starts_with(name, '$($Cfg.azureResourcesPrefix)') || starts_with(name, '$($Cfg.azureResourcesPrefix.ToLower())')]"
$LinuxFxVersion = -join('"PYTHON|', "$($Cfg.pythonVersion)", '"')

Write-Host '=======Validating configuration'
$ExpectedKeys = @(
    'azureResourcesPrefix',
    'aspTier',
    'pythonVersion',
    'devOpsProject',
    'devOpsOrg'
)
if (-Not (Assert-Keys-Exist $Cfg -Keys $ExpectedKeys)) {
    Write-Error 'Invalid config file: missing required keys'
}
if (-Not $Cfg.aspTier.StartsWith('P')) {
    Write-Error 'This project currently only supports Premium Service Plan options since they are required for deployment slot usage (which are used for QA and currently baked into the PPL)'
}
if ($AbsoluteTargetRepoPathPrefix) {

    Write-Host '=======Performing validation of the custom local target repo path that was given'
    if (Test-Path $TargetRepoPathPrefix) {
        Write-Host 'OK: Path validation passed'
        $TargetRepoPathPrefix = $AbsoluteTargetRepoPathPrefix
    } else {
        Write-Error 'The given path is invalid'
    }
}
if (Test-Path "$TargetRepoPathPrefix/$($Cfg.devOpsRepoName)") {
    Write-Warning 'The path given as a destination for the local clone of the git repo already exists, please either specify a different name or delete the folder'
    Write-Error "`"$TargetRepoPathPrefix/$($Cfg.devOpsRepoName)`" already exists"
}

Write-Host '=======Performing Azure DevOps prevalidation'
Login-ToDevOpsWriteInfo
try {
    $FoundRepos = az repos list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
    if ($FoundRepos.length -ge 1) {
        Write-Error "Found existing DevOps repo matching the configured prefix, you will have to specify a custom repo name in the config file under `"devOpsRepoName`""
    }
} catch {
    Warn-CustomThenThrowErr 'An error occurred, logging out of Azure DevOps' $_
} finally {
    Perform-EarlyDevOpsLogout
}

Write-Host '=======Starting prevalidation regarding existing Azure resources'
Login-PersistInfo -NoCleanup # fine because of finally block
try {
    $Rg = Identify-ResourceToReuse 'group' $true
    $Sa = Identify-ResourceToReuse 'storage account'
    $Asp = Identify-ResourceToReuse 'appservice plan'
    $Fa = Identify-ResourceToReuse 'functionapp'
    $Kv = Identify-ResourceToReuse 'keyvault'
    Write-Host 'OK: State in Azure did not warrant an abort'
    Write-Host 'OK: Prevalidation ran through successfully'
    if ($PrevalidationOnly) {
        Ask-ToConfirmElseExit -Question 'Are you certain you want to proceed?' -Header 'Azure Resource provisioning' -Force
    } else {
        Ask-ToConfirmElseExit -Question 'Are you certain you want to proceed?' -Header 'Azure Resource provisioning'
    }


    Write-Host '=====Starting creation of Azure resources'
    if ($Sa -eq $null) {

        Write-Host '=======Creating the Storage Account'
        $Sa = az storage account create -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix.ToLower())sa" -l "$($Cfg.azureStorageGeoLocation)" --kind StorageV2 --output json | ConvertFrom-Json
        Write-Host "OK: Created Storage Account `"$($Sa.name)`""
    }
    if ($Asp -eq $null) {

        Write-Host '=======Creating the App Service Plan'
        $Asp = az appservice plan create -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-asp" --is-linux --number-of-workers 1 --sku "$($Cfg.aspTier)" --output json | ConvertFrom-Json
        Write-Host "OK: Created App Service Plan `"$($Asp.name)`""
    }
    if ($Fa -eq $null) {

        Write-Host '=======Creating the Function App'
        $Fa = az functionapp create -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-fa" -s "$($Cfg.azureResourcesPrefix.ToLower())sa" --functions-version 4 -p "$($Cfg.azureResourcesPrefix)-asp" --https-only true --runtime python --assign-identity '[system]' --output json | ConvertFrom-Json
        Write-Host "OK: Created Function App `"$($Fa.name)`""
    }

    Write-Host '=======Configuring the Function App'
    az functionapp config set -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-fa" --linux-fx-version $LinuxFxVersion | Out-Null
    az functionapp config appsettings set -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-fa" --settings "`@$PSScriptRoot/cfg/appsettings.json" | Out-Null
    $slots = az functionapp deployment slot list -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-fa" --query "[?name == 'test']" --output json | ConvertFrom-Json
    if ($slots.length -eq 0) {

        Write-Host '=======Creating a deployment slot in the Function App for testing purposes'
        az functionapp deployment slot create -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-fa" --slot 'test' | Out-Null
        Write-Host 'OK: Created new deployment slot'
    } else {
        Write-Warning 'Using existing deployment slot'
    }
    $TSlotIdentityRes = az functionapp identity assign -g "$($Rg.name)" -n "$($Cfg.azureResourcesPrefix)-fa" --identities '[system]' --slot 'test' --output json | ConvertFrom-Json
    if ($CreateKeyVault) {
        if ($Kv -eq $null) {

            Write-Host '=======Creating the Key Vault'
            if (Get-Member -inputobject $Cfg -name 'keyVaultNameSuffix') {
                $KvName = "$($Cfg.azureResourcesPrefix)-kv$($Cfg.keyVaultNameSuffix)"
            } else {
                $KvName = "$($Cfg.azureResourcesPrefix)-kv"
            }
            $Kv = az keyvault create -g "$($Rg.name)" -n $KvName -l "$($Cfg.azureStorageGeoLocation)" --enable-rbac-authorization false --output json | ConvertFrom-Json
            Write-Host "OK: Created Key Vault `"$($Kv.name)`""
        }
        $ManagedSp = (az ad sp list --display-name "$($Fa.name)" --filter "servicePrincipalType eq 'ManagedIdentity'" --output json | ConvertFrom-Json) | Where-Object {-Not $_.displayName.EndsWith('/slots/test')}[0]
        # manually specifying -g as workaround for https://github.com/Azure/azure-cli/issues/27239
        az keyvault set-policy -g "$($Rg.name)" --name $Kv.name --object-id $ManagedSp.id --secret-permissions all | Out-Null
        # manually specifying -g as workaround for https://github.com/Azure/azure-cli/issues/27239
        az keyvault set-policy -g "$($Rg.name)" --name $Kv.name --object-id $TSlotIdentityRes.principalId --secret-permissions all | Out-Null

        Write-Host '=======Creating a Secret with name "ExampleSecret"'
        Set-KvSecret $Kv.name 'ExampleSecret' '1234'
    }
    if ($CreateAlerts) {

        Write-Host '=======Setting up E-Mail alerts regarding resource bottlenecks and exceptions'
        $ActionGroupCreationCmd = "az monitor action-group create -n `"Mailalerts`" -g `"$($Rg.name)`" "
        foreach ( $Email in $Cfg.alertRecipientMailAddresses ) {
            $ActionGroupCreationCmd += " -a `"email`" `"$Email`" `"$Email`""
        }
        $ActionGroupCreationCmd += ' | Out-Null'
        Invoke-Expression $ActionGroupCreationCmd
        $MetricAlertScope = "/subscriptions/$($LoginInfo.id)/resourceGroups/$($Rg.name)/providers/Microsoft.Web/serverfarms/$($Asp.name)"
        $ActionGroupPath = "/subscriptions/$($LoginInfo.id)/resourceGroups/$($Rg.name)/providers/Microsoft.Insights/actionGroups/Mailalerts"
        az monitor metrics alert create --condition 'avg CpuPercentage > 90' -n 'CPU alert - average percentage over 90' -g "$($Rg.name)" --scopes $MetricAlertScope -a $ActionGroupPath --evaluation-frequency '30m' --window-size '30m' --auto-mitigate false | Out-Null
        az monitor metrics alert create --condition 'max MemoryPercentage > 90' -n 'Memory alert - maximum percentage over 90' -g "$($Rg.name)" --scopes $MetricAlertScope -a $ActionGroupPath --evaluation-frequency '1h' --window-size '1h' --auto-mitigate false | Out-Null
        az monitor scheduled-query create -g "$($Rg.name)" -n 'Exception alert - detected exceptions during last hour' --scopes "/subscriptions/$($LoginInfo.id)/resourceGroups/$($Rg.name)/providers/Microsoft.Insights/components/$($Fa.name)" --action-group $ActionGroupPath --condition "count 'Arg0' > 0" --condition-query Arg0='exceptions' --window-size '1h' --evaluation-frequency '1h' --auto-mitigate false | Out-Null
        Write-Host 'OK: created E-Mail alerts'
    }
    $EndpointTargetInfo = $LoginInfo
    Write-Host 'OK: State in Azure now matches the target state'
} catch {
    Warn-CustomThenThrowErr 'An error occurred, logging out of Azure' $_
} finally {
    Perform-EarlyAzLogout
}
Login-ToDevOpsWriteInfo
try {


    Write-Host '=====Creating the DevOps Service Connection'
    $Endpoints = az devops service-endpoint list --query "$PrefixQuery" --output json | ConvertFrom-Json
    switch ($Endpoints.length) {
        0 {
            $AppRegId = Read-Host 'Enter the App Registration ID (appId)'
            $env:AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY = Read-Host 'Enter the Service Principal Key'
            ($ServiceConn = az devops service-endpoint azurerm create --azure-rm-service-principal-id $AppRegId --azure-rm-subscription-id $EndpointTargetInfo.id --azure-rm-subscription-name $EndpointTargetInfo.name --azure-rm-tenant-id $EndpointTargetInfo.tenantId --name "$($Rg.name)" --output json | ConvertFrom-Json) | Out-Null
            az devops service-endpoint update --id $ServiceConn.id --enable-for-all | Out-Null
        }
        1 {
            $ServiceConn = $Endpoints[0]
            Write-Warning "Using existing Service Connection `"$($ServiceConn.name)`""
        }
        default {
            Write-Error "Found $($Endpoints.length) Service Connections matching the configured prefix, 1 or 0 would have been acceptable"
        }
    }
    Write-Host 'OK: Required Service Connection is set up'


    Write-Host '=====Starting upload of Azure Function boilerplate code and pipeline scaffolding to a new DevOps repository'

    Write-Host '=======Creating local directory'
    New-Item -Path "$TargetRepoPathPrefix" -Name "$($Cfg.devOpsRepoName)" -ItemType 'directory' | Out-Null
    Set-Location "$TargetRepoPathPrefix/$($Cfg.devOpsRepoName)"
    Write-Host "OK: Created directory `"$($Cfg.devOpsRepoName)`""

    Write-Host '=======Creating and cloning DevOps repository'
    az repos create --name $Cfg.devOpsRepoName *>$null
    git clone $RepoUrl . *>"$GitLogFile"
    Assert-GitStatusOk
    git checkout -b main *>>"$GitLogFile"
    Assert-GitStatusOk
    Copy-ToIndex '.funcignore' "${PSScriptRoot}/cfg/"
    Copy-ToIndex '.gitignore' "${PSScriptRoot}/cfg/"
    Copy-ToIndex 'host.json' "${PSScriptRoot}/cfg/"
    Fetch-ByLocalCopy "${PSScriptRoot}/function-samples/http_default_function_sample.py" './function_app.py'
    Add-ToIndex 'function_app.py'
    Fetch-ByLocalCopy "${PSScriptRoot}/utils/*.py"
    Add-ToIndex './\*.py'
    Copy-ToIndex 'requirements.txt' "${PSScriptRoot}/cfg/"
    git commit -m 'Add files needed for sample Azure Function' *>>"$GitLogFile"
    Assert-GitStatusOk
    git push --set-upstream origin main *>>"$GitLogFile"
    Assert-GitStatusOk
    Copy-ToIndex 'azure-pipelines.yml' "${PSScriptRoot}/cfg/"
    New-Item -Name 'tests' -ItemType 'directory' | Out-Null
    Copy-Item "${PSScriptRoot}/test-samples/conftest.py" -Destination './tests' | Out-Null
    Copy-Item "${PSScriptRoot}/test-samples/http_default_function_sample_test.py" -Destination './tests' | Out-Null
    Copy-Item "${PSScriptRoot}/cfg/python_package_mark.txt" -Destination './tests/__init__.py' | Out-Null
    Add-ToIndex 'tests'
    Copy-Item "${PSScriptRoot}/cfg/python_package_mark.txt" -Destination './__init__.py' | Out-Null
    Add-ToIndex '__init__.py'
    Copy-ToIndex 'appsettings.json' "${PSScriptRoot}/cfg/"
    git commit -m 'Add pipeline files' *>>"$GitLogFile"
    Assert-GitStatusOk
    git push *>>"$GitLogFile"
    Assert-GitStatusOk
    az repos update --r $Cfg.devOpsRepoName --default-branch main *>$null
    $RepoData = az repos show -r $Cfg.devOpsRepoName | ConvertFrom-Json
    Write-Host "OK: Created the repository `"$($Cfg.devOpsRepoName)`" with the needed contents in `"$($Cfg.devOpsOrg)`" and cloned locally to `"$($Cfg.devOpsRepoName)`""


    Write-Host '=====Starting configuration of DevOps repository'

    Write-Host '=======Creating DevOps pipeline'
    ($Res = az pipelines create --name $Cfg.devOpsRepoName --description 'Build, test and deployment pipeline' --repository $RepoUrl --branch main --skip-first-run true --yaml-path azure-pipelines.yml) | Out-Null
    if ($LastExitCode -ne 0) {
        Write-Error $Res
    }
    $PipelineData = $Res | ConvertFrom-Json
    Write-Host 'OK: Created DevOps pipeline using the YML file contained in the repo'

    Write-Host '=======Creating pipeline variables'
    az pipelines variable create --name 'PythonVersion' --pipeline-id $PipelineData.id --value "$($Cfg.pythonVersion)" | Out-Null
    az pipelines variable create --name 'ServiceConnName' --pipeline-id $PipelineData.id --value $ServiceConn.name | Out-Null
    az pipelines variable create --name 'FunctionAppName' --pipeline-id $PipelineData.id --value "$($Cfg.azureResourcesPrefix)-fa" | Out-Null
    az pipelines variable create --name 'ResourceGroupName' --pipeline-id $PipelineData.id --value "$($Cfg.azureResourcesPrefix)-rg" | Out-Null
    az pipelines variable create --name 'TestSlotBlobOutPath' --pipeline-id $PipelineData.id --value 'test-slot-blobcontainer' | Out-Null
    az pipelines variable create --name 'TestSlotSchedule' --pipeline-id $PipelineData.id --value '0 30 * * * *' | Out-Null
    Write-Host 'OK: Created DevOps pipeline variables'

    Write-Host '=======Starting pipeline to deploy sample code'
    az pipelines run --id $PipelineData.id --open | Out-Null
    Write-Host 'OK: Started DevOps pipeline and opened in browser'

    Write-Host '=======Configuring repository policies'
    if ($CreateMinApprovalPolicy) {
        az repos policy approver-count create --allow-downvotes false --blocking true --branch main --creator-vote-counts false --enabled true --minimum-approver-count 2 --repository-id $RepoData.id --reset-on-source-push true *>$null
    }
    az repos policy work-item-linking create --blocking false --branch main --enabled true --repository-id $RepoData.id *>$null
    az repos policy comment-required create --blocking true --branch main --enabled true --repository-id $RepoData.id *>$null
    az repos policy required-reviewer create --blocking false --branch main --enabled true --message 'Automatically adding default reviewers' --repository-id $RepoData.id --required-reviewer-ids ($Cfg.defaultPullReviewerMailAddresses -join ';') *>$null
    Write-Host 'OK: Configured repository policies'

    Write-Host '=======Configuring build policies'
    az repos policy build create --blocking true --branch main --build-definition-id $PipelineData.id --display-name 'PR test, build and test-slot deployment policy' --enabled true --manual-queue-only false --queue-on-source-update-only  false --repository-id $RepoData.id --valid-duration 0 *>$null
    Write-Host 'OK: Configured build policies'
    Write-Host 'DONE: Proceeding with exit after successful run!'
} catch {
    Warn-CustomThenThrowErr 'An error occurred, logging out of Azure DevOps' $_
} finally {
    Perform-EarlyDevOpsLogout
}
