param(
    [string]
    [Parameter(Mandatory)]
    [ValidateSet('CpuPercentage','MemoryPercentage')]
    $Metric,
    [int]
    # offset between individual polls in seconds
    $PollingInterval=60,
    [string]
    $Interval='24h',
    [string]
    $Offset='28d',
    [string]
    [ValidateSet('Average','Count','Maximum','Minimum','None','Total')]
    $Aggregation='Maximum',
    [string]
    [Parameter(Mandatory)]
    $AppServicePlan,
    $SubscriptionId,
    $ResourceGroupToInspect
)

$host.ui.RawUI.WindowTitle = "$ResourceGroupToInspect>$AppServicePlan"

. "$PSScriptRoot/aztra-utils.ps1"

while ($true) {
    $Stats = Fetch-FaMetric $Metric $Interval $Offset $Aggregation $AppServicePlan -BypassScopeBasedChecks $SubscriptionId $ResourceGroupToInspect
    $PropertyName = $Aggregation.ToLower()
    $Values = $Stats.$PropertyName | ForEach-Object{ [double]::Parse([string]$_, [cultureinfo]$PSCulture) }

    Clear-Host
    Show-Graph -Datapoints $Values -XAxisTitle "$Aggregation $Metric in $Interval bins over last $Offset"

    Start-Sleep -Seconds $PollingInterval
}
