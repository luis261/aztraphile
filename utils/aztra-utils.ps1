$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0


#. "$PSScriptRoot/plotting.ps1"


$GitLogFile = "$PSScriptRoot/../git.log"


<#
.SYNOPSIS

Displays metrics (about an App Service Plan) graphically

.DESCRIPTION

Graphical wrapper around "Fetch-FaMetric"

.EXAMPLE

PS> Show-FaMetric MemoryPercentage

.EXAMPLE

PS> Show-FaMetric -Metric CpuPercentage -Interval 5m -Offset 3h

.EXAMPLE

PS> Show-FaMetric -Metric 'CpuPercentage' -Interval '15m' -Offset '16h' -AppServicePlan 'YourASPHere'
#>
function Show-FaMetric {
    param(
        [string]
        # metric to be evaluated
        [Parameter(Mandatory)]
        [ValidateSet("CpuPercentage","MemoryPercentage")]
        $Metric,
        [string]
        # size of time-bins
        $Interval="24h",
        [string]
        # total timespan under observation
        $Offset="28d",
        [string]
        # function used to transform each bins values to a single value
        [ValidateSet("Average","Count","Maximum","Minimum","None","Total")]
        $Aggregation="Maximum",
        [string]
        # target of the metric calculation/observation
        $AppServicePlan
    )

    Ensure-LoggedIn

    $Stats = Fetch-FaMetric $Metric $Interval $Offset $Aggregation $AppServicePlan
    $PropertyName = $Aggregation.ToLower()
    $Values = $Stats.$PropertyName | ForEach-Object{ [double]::Parse([string]$_, [cultureinfo]$PSCulture) }
    Show-Graph -Datapoints $Values -XAxisTitle "$Aggregation $Metric % in $Interval bins over last $Offset"
}

<#
.SYNOPSIS

Fetches metrics (about an App Service Plan)

.DESCRIPTION

Allows you to query App Service Plan metrics from the command line instead of having to use the Azure portal
Automatically searches for an App Service Plan resource in case you don't explicitly specify one

.EXAMPLE

PS> Fetch-FaMetric CpuPercentage

.EXAMPLE

PS> Fetch-FaMetric CpuPercentage -Interval 6h -Offset 3d -Aggregation Average

.EXAMPLE

PS> Fetch-FaMetric 'MemoryPercentage' -Interval '12h' -Offset '14d' -Aggregation 'Maximum' -AppServicePlan 'YourASPHere'
#>
function Fetch-FaMetric {
    param(
        [string]
        # metric to be evaluated
        [Parameter(Mandatory)]
        [ValidateSet("CpuPercentage","MemoryPercentage")]
        $Metric,
        [string]
        # size of time-bins
        $Interval="30m",
        [string]
        # total timespan under observation
        $Offset="16h",
        [string]
        # function used to transform each bins values to a single value
        [ValidateSet("Average","Count","Maximum","Minimum","None","Total")]
        $Aggregation="Maximum",
        [string]
        # target of the metric calculation/observation
        $AppServicePlan
    )

    Ensure-LoggedIn
    Ensure-RgToInspectSet

    if ($AppServicePlan -eq "") {
        Write-Warning "no app service plan was specified, performing search in given RG"
        $Res = az resource list -g $ResourceGroupToInspect --resource-type "Microsoft.Web/serverFarms" --output json | ConvertFrom-Json
        try {
            $AspName = $Res.name
        } catch [System.Management.Automation.RuntimeException] {
            Write-Error $_.Exception.Message
            throw "the given RG `"$ResourceGroupToInspect`" does not contain any app service plans"
        }

        if ($AspName -is [array]) {
            throw "omitting the app service plan name is only permissible if there is exactly one app service plan in the given RG"
        } else {
            $AppServicePlan = $AspName
            Write-Warning "using app service plan `"$AppServicePlan`""
        }
    }

    $ResourceURI = "/subscriptions/$($LoginInfo.id)/resourceGroups/$ResourceGroupToInspect/providers/Microsoft.Web/serverfarms/$AppServicePlan"

    $Res = az monitor metrics list --resource $ResourceURI --metrics $Metric --interval $Interval --offset $Offset --aggregation $Aggregation --output json | ConvertFrom-Json

    $rows = New-Object System.Collections.Generic.List[System.Object]
    $Res.value.timeseries.data | ForEach-Object { 
        $r = @()
        foreach ( $val in $_.PSObject.properties.Value ) {
            $r += $val
        }
        $rows.Add($r)
    }

    $ColumnsToSelect = @("timeStamp",$Aggregation.ToLower())
    return Convert-ToDatatable $rows.ToArray() @("average","count","maximum","minimum","timeStamp","total") $ColumnsToSelect
}

<#
.SYNOPSIS

Fetches insights via an App Insights query

.DESCRIPTION

Allows you to query insights from the command line instead of having to use the Azure portal
Automatically searches for an App Insights resource in case you don't explicitly specify one

.EXAMPLE

PS> Fetch-FaInsights 'logs'

.EXAMPLE

PS> Fetch-FaInsights -InsightsSpecifier 'logs' -Offset 3h

.EXAMPLE

PS> Fetch-FaInsights -InsightsSpecifier 'logs' -Offset '7d' -Raw | Where-Object {$_.message -ilike '*detected new*'}
#>
function Fetch-FaInsights([string]$InsightsSpecifier, [string]$Offset, [switch]$Raw, [string]$AppInsightsTarget) {
    Ensure-LoggedIn
    Ensure-RgToInspectSet

    if (-Not ($AppInsightsTarget -eq "")) {
        $AppInsights = $AppInsightsTarget
    } else {
        try {
            if ([string]::IsNullOrEmpty($AppInsightsToQuery)) {
                throw "please specify an application insights instance to query (via `"Set-InsightsToQuery`")"
            } else {
                $AppInsights = $AppInsightsToQuery
            }
        } catch [System.Management.Automation.RuntimeException] {
            Write-Warning "no app insights instance was specified, performing search in given RG"
            $Res = az resource list -g $ResourceGroupToInspect --resource-type "Microsoft.Insights/components" --output json | ConvertFrom-Json
            try {
                $InsightsInstanceName = $Res.name
            } catch [System.Management.Automation.RuntimeException] {
                Write-Error $_.Exception.Message
                throw "the given RG `"$ResourceGroupToInspect`" does not contain any application insights instances"
            }

            if ($InsightsInstanceName -is [array]) {
                throw "omitting the application insights name is only permissible if there is exactly one application insights instance in the given RG, please specify an application insights instance to query (via `"Set-InsightsToQuery`")"
            } else {
                $AppInsights = $InsightsInstanceName
                Write-Warning "using app insights instance `"$AppInsights`""
                Write-Warning "will use app insights instance `"$AppInsights`" as default for further queries without explicit insight target in this session"
                Set-InsightsToQuery $AppInsights
            }
        }
    }

    try {
        switch ($InsightsSpecifier) {
            { $_.ToLower() -in "logs","log","logging","traces","trace" -or $_ -eq "" } {
                if ($Offset -eq "") {
                    $Offset = "3h"
                }
                $Res = az monitor app-insights query -g $ResourceGroupToInspect -a $AppInsights --analytics-query 'traces' --offset $Offset --output json | ConvertFrom-Json
                $ColumnsToSelect = @("operation_Name","severityLevel","timestamp","message")
            }
            { $_.ToLower() -in "requests","request","duration","durations" } {
                if ($Offset -eq "") {
                    $Offset = "8h"
                }
                $Res = az monitor app-insights query -g $ResourceGroupToInspect -a $AppInsights --analytics-query 'requests' --offset $Offset --output json | ConvertFrom-Json
                $ColumnsToSelect = @("operation_Name","success","timestamp","duration","performanceBucket")
            }
            { $_.ToLower() -in "exceptions","exception","error","errors" } {
                if ($Offset -eq "") {
                    $Offset = "24h"
                }
                $Res = az monitor app-insights query -g $ResourceGroupToInspect -a $AppInsights --analytics-query 'exceptions' --offset $Offset --output json | ConvertFrom-Json
                $ColumnsToSelect = @("operation_Name","timestamp","innermostMessage")
            }
            default {
                throw "unsupported InsightsSpecifier: `"$InsightsSpecifier`""
            }
        }
    } catch {
        if (-Not ($_.Exception.Message -ilike "*unsupported InsightsSpecifier*")) {
            Write-Warning "unsetting `"AppInsightsToQuery`" because an error occurred"
            Set-InsightsToQuery ""
        }
        throw $_
    }

    $Table = Convert-ToDatatable $Res.tables[0].rows $Res.tables[0].columns.name $ColumnsToSelect
    $Table = New-Object System.Data.DataView($Table)
    $Table.Sort="timestamp ASC"

    if ($Raw) {
        return $Table
    } else {
        Set-StrictMode -Off
        $PostProcessedRes = $Table | Where-Object { $_.operation_Name -ne $null -and $_.operation_Name -ne "" `
            -and ($_.severityLevel -eq $null -or $_.severityLevel -eq "" -or $_.severityLevel -le 1) # ignoring warnings
        }
        Set-StrictMode -Version 3.0
        return $PostProcessedRes | Format-Table -Wrap
    }
}

function Set-GroupToInspect {
    param(
        [string]
        # Resource Group to be used as target for other utility functions
        [Parameter(Mandatory)]
        $ResourceGroup
    )
    Write-Warning "`"$ResourceGroup`" will now be used as the default RG, you can change that via calling `"Set-GroupToInspect`" directly"
    $global:ResourceGroupToInspect = $ResourceGroup
}

function Set-InsightsToQuery {
    param(
        [string]
        # Application Insights resource to set as default target for other utility functions
        [Parameter(Mandatory)]
        $AppInsights
    )
    $global:AppInsightsToQuery = $AppInsights
}

function Build-LogMessageSieve {
    param(
        [string]
        # search term to filter with
        [Parameter(Mandatory)]
        $SearchTerm
    )
    { $_.message -ilike "*$SearchTerm*" }.GetNewClosure()
}

function Convert-ToDatatable($Rows, $ExistingColumns, [array]$ColumnsToSelect) {
    $Table = New-Object System.Data.Datatable

    $WantedColIndices = foreach ($ColName in $ColumnsToSelect) { [array]::indexof($ExistingColumns, $ColName) }

    foreach ($ColName in $ColumnsToSelect) { $Table.Columns.Add([System.Data.DataColumn]$ColName) }
    foreach ($Row in $Rows) { 
        $NewEntry = $Table.NewRow()
        for ($Index = 0; $Index -lt $WantedColIndices.length; $Index++) {
            $NewEntry[$ColumnsToSelect[$Index]] = $Row[$WantedColIndices[$Index]]
        }
        $Table.Rows.Add($NewEntry)
    }

    return ,$Table
}


function Invoke-Function {
    param(
        [string]
        # name of the Function App containing your invocation target
        [Parameter(Mandatory)]
        $FunctionAppName,
        [string]
        # name of the Azure Function to invoke
        [Parameter(Mandatory)]
        $FunctionName,
        [string]
        # name of the deployment slot (omit/leave empty in case of default slot)
        $Slot
    )

    Ensure-LoggedIn
    Ensure-RgToInspectSet

    if ($Slot) {
        $FunctionKey = ((az functionapp keys list -g $ResourceGroupToInspect -n $FunctionAppName --slot $Slot | ConvertFrom-Json).functionKeys).default
    } else {
        $FunctionKey = ((az functionapp keys list -g $ResourceGroupToInspect -n $FunctionAppName | ConvertFrom-Json).functionKeys).default
    }

    if ($Slot) {
        $FunctionAppName = "$FunctionAppName/$Slot"
    }
    $CallUrl = (az functionapp function show -g $ResourceGroupToInspect -n $FunctionAppName --function-name $FunctionName | ConvertFrom-Json).invokeUrlTemplate

    Write-Host "${CallUrl}?code=$FunctionKey"
    Invoke-WebRequest -Uri "${CallUrl}?code=$FunctionKey"
}

<#
.SYNOPSIS

Completely restarts a Function App, which tends to help with resolving issues relating to configuration changes that don't seem to actuate in particular as well as having a chance to fix errors in general

.DESCRIPTION

You may not believe it, but stopping and then starting a Function App is not the same as restarting it, so just to be sure, a combined approach is used here
#>
function Restart-FunctionAppCompletely {
    param(
        [string]
        # name of the Function App containing your invocation target
        [Parameter(Mandatory)]
        $FunctionAppName,
        [string]
        # name of the deployment slot (omit/leave empty in case of default slot)
        $Slot
    )

    Ensure-LoggedIn
    Ensure-RgToInspectSet

    Write-Host "Stopping $FunctionAppName"
    if ($Slot) {
        az functionapp stop -g $ResourceGroupToInspect -n $FunctionAppName --slot $Slot
    } else {
        az functionapp stop -g $ResourceGroupToInspect -n $FunctionAppName
    }
    Write-Host "Waiting for 60 seconds"
    Start-Sleep -Seconds 60
    Write-Host "Starting $FunctionAppName"
    if ($Slot) {
        az functionapp start -g $ResourceGroupToInspect -n $FunctionAppName --slot $Slot
    } else {
        az functionapp start -g $ResourceGroupToInspect -n $FunctionAppName
    }
    Write-Host "Waiting for 60 seconds"
    Start-Sleep -Seconds 60

    Write-Host "Restarting $FunctionAppName"
    if ($Slot) {
        az functionapp restart -g $ResourceGroupToInspect -n $FunctionAppName --slot $Slot
    } else {
        az functionapp restart -g $ResourceGroupToInspect -n $FunctionAppName
    }
    Write-Host "Waiting for 60 seconds"
    Start-Sleep -Seconds 60
}

function Set-KvSecret([string]$VaultName, [string]$SecretName, [string]$SecretValue) {
    Ensure-LoggedIn

    $Res = az keyvault secret set --vault-name $VaultName --name $SecretName --value $SecretValue --output json | ConvertFrom-Json
    return $Res.id
}

function Create-StorageContainer([string]$ResourceGroup, [string]$StorageAccount, [string]$ContainerName) {
    Ensure-LoggedIn

    $ConnectionRes = az storage account show-connection-string -g $ResourceGroup -n $StorageAccount --output json | ConvertFrom-Json
    $ContainerRes = az storage container exists -n $ContainerName --connection-string "$($ConnectionRes.connectionString)" --output json | ConvertFrom-Json
    if ($ContainerRes.exists) {
        Write-Warning "a container with the given name already exists, skipping creation"
        return $null
    } else {
        return az storage container create -n $ContainerName --connection-string "($($ConnectionRes.connectionString)"
    }
}


function Set-AzPipelinesVar($PipelineNamePrefix, $VariableName, $Value) {
    Login-ToDevOps

    $Ppl = (az pipelines list --name "${PipelineNamePrefix}*" | ConvertFrom-Json)[0]
    if ((az pipelines variable list --pipeline-id $Ppl.id | Where-Object {$_.name -eq $VariableName }).Length -ge 1) {
        az pipelines variable update --name $VariableName --value $Value
    } else {
        az pipelines variable create --name $VariableName --value $Value
    }
}


function Ensure-LoggedIn() {
    try {
        if ($LoginInfo -eq $null) {
            Login-PersistInfo
        }
    } catch [System.Management.Automation.RuntimeException] {
        Login-PersistInfo
    }
}

function Login-PersistInfo([switch]$NoCleanup) {
    $global:LoginInfo = az login --use-device-code --output json | ConvertFrom-Json
    if ($NoCleanup) {} else {
        Write-Warning "aztraphile will try to log you out automatically once you`'re done using it. However, because of a technical flaw in powershell, if you end your powershell session by closing the window (instead of typing `"exit`"), you will have to manually run `"az logout`"" # https://github.com/PowerShell/PowerShell/issues/8000
        Register-EngineEvent PowerShell.Exiting -Action {
            try {
                az logout
            } catch {
                Set-Content -Path "$PSScriptRoot/azlogouterror.log" -Value $_.Exception.Message
                [Console]::Beep()
            }
        } | Out-Null
    }
    Write-Host 'OK: authenticated against Azure'
}

function Login-ToDevOps($DevOpsOrg, $Project, [switch]$NoCleanup) {
    try {
        if (-Not [string]::IsNullOrEmpty($DevOpsPat)) {
            return
        }
    } catch [System.Management.Automation.RuntimeException] { }

    if (-Not $DevOpsOrg) {
        $DevOpsOrg = Read-Host 'Enter the base URL to your Azure DevOps organization'
    }
    if (-Not $Project) {
        $Project = Read-Host 'Enter the name of your Azure DevOps project'
    }

    $global:DevOpsPat = Read-Host 'Enter the DevOps Personal Access Token'
    $DevOpsPat | Write-Output | az devops login | Out-Null

    if ($NoCleanup) {} else {
        Write-Warning "aztraphile will try to log you out automatically once you`'re done using it. However, because of a technical flaw in powershell, if you end your powershell session by closing the window (instead of typing `"exit`"), you will have to manually run `"az devops logout`"" # https://github.com/PowerShell/PowerShell/issues/8000
        Register-EngineEvent PowerShell.Exiting -Action {
            try {
                az devops logout
            } catch {
                Set-Content -Path "$PSScriptRoot/azlogouterror.log" -Value $_.Exception.Message
                [Console]::Beep()
            }
        } | Out-Null
    }

    if ($DevOpsOrg -and $Project) {
        az devops configure --defaults organization=$DevOpsOrg project=$Project *>$null
        Write-Host "OK: authenticated and configured with the defaults of `"$Project`" in `"$DevOpsOrg`""
    } else {
        $Defaults = az devops configure -l
        $Project = ($Defaults[2] -split "=")[1].Trim()
        $DevOpsOrg = ($Defaults[3] -split "=")[1].Trim()
        Write-Host "OK: authenticated, your defaults are: `"$Project`" in `"$DevOpsOrg`""
    }
}

function Ensure-RgToInspectSet() {
    try {
        if ([string]::IsNullOrEmpty($ResourceGroupToInspect)) {
            throw "please specify a resource group to inspect (via `"Set-GroupToInspect`")"
        }
    } catch {
        $RgInput = Read-Host 'please specify which resource group to target'
        Set-GroupToInspect $RgInput
    }
}



function Ask-ToConfirmElseExit {
    [CmdletBinding()]
    Param([switch]$Question, [string]$Header)
    if(-Not ($Force.IsPresent -or $PSCmdlet.ShouldContinue($Question, $Header))) {
        echo "Stopping as requested, instead of proceeding with $Header"
        Exit 1
    }
    echo "Proceeding as requested with $Header"
}

function Copy-ToIndex([string]$SelectionSpecifier, [string]$FetchPathPrefix, $Destination='.', $GitErrorAction='EXIT') {
    Fetch-ByLocalCopy "$FetchPathPrefix$SelectionSpecifier" $Destination
    Add-ToIndex $SelectionSpecifier $GitErrorAction
}

function Fetch-ByLocalCopy([string]$SelectionSpecifier, [string]$Destination='.', [bool]$Silent=$true) {
    if ($Silent) {
        Copy-Item $SelectionSpecifier -Destination $Destination | Out-Null
    } else {
        Copy-Item $SelectionSpecifier -Destination $Destination
    }
}

function Add-ToIndex([string]$SelectionSpecifier, [string]$GitErrorAction='EXIT') {
    git add $SelectionSpecifier *>>"$PSScriptRoot/$GitLogFile"
    Assert-GitStatusOk $GitErrorAction
}

function Assert-GitStatusOk([string]$FallbackAction='EXIT') {
    if ($LastExitCode -ne 0) {
        Handle-FallbackRouting $FallbackAction 'git encountered an error, please refer to the log file'
    }
}

function Handle-FallbackRouting([string]$Action, [string]$Message='') {
    switch ($Action.ToUpper()) {
        "EXIT" {
            if ($Message.Length > 0) {
                Write-Error $Message
            }
        }
        "THROW" {
            throw $Message
        }
        "WARN" {
            Write-Warning $Message
        }
        default {
            # (SKIP/IGNORE)
        }
    }
}

function Write-ToObj($TargetObject, [string]$Key, $Value, [switch]$Silent, [switch]$NoOverwrite) {
    if (Get-Member -inputobject $TargetObject -name $Key) {
        if ($NoOverwrite) {
            if ($Silent) {} else {
                Write-Warning "not setting $Key on the given object: $Key is already set to $(Get-Member -inputobject $TargetObject -name $Key)"
            }
        } else {
            if ($Silent) {} else {
                Write-Warning "overwriting $(Get-Member -inputobject $TargetObject -name $Key) under $Key with $Value"
            }
            $TargetObject | Add-Member -Name $Key -Type NoteProperty -Value $Value -Force
        }
    } else {
        $TargetObject | Add-Member -Name $Key -Type NoteProperty -Value $Value
    }
}

function Assert-Keys-Exist($TargetObject, $Keys, [switch]$Silent) {
    $Flag = $true
    foreach ($Key in $Keys) {
        if (-Not (Get-Member -inputobject $TargetObject -name $Key)) {
            if ($Silent) {} else {
                Write-Warning "the given object is missing a member with name $Key"
            }
            $Flag = $false
        }
    }
    return $Flag
}

function Identify-ResourceToReuse([string]$ResourceType, [bool]$ReuseOnly) {
    switch ($ResourceType) {
        "group" {
            $FoundResources = az group list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = "Resource Groups"
        }
        "functionapp" {
            $FoundResources = az functionapp list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = "Function Apps"
        }
        "appservice plan" {
            $FoundResources = az appservice plan list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = "App Service Plans"
        }
        "storage account" {
            $FoundResources = az storage account list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = "Storage Accounts"
        }
        "keyvault" {
            $FoundResources = az keyvault list --query `"$PrefixQuery`" --output json | ConvertFrom-Json
            $Descriptor = "Key Vaults"
        }
        default {
            Write-Error "`"Identify-ResourceToReuse`" received unexpected parameter"
        }
    }
    
    if ($FoundResources.length -eq 1) {
        return $FoundResources[0]
    } elseif ($FoundResources.length -eq 0) {
        if ($ReuseOnly)  {
            Write-Error "found 0 $Descriptor matching the configured prefix, expected to find exactly 1"
        } else {
            return $null
        }
    } else {
        Write-Error "found $($FoundResources.length) $Descriptor matching the configured prefix, 1 or 0 would have been acceptable"
    }
}