
function Read-WorkSheetCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$csvFilePath
    )
    
    if(-not (Test-Path $csvFilePath)) {
        return "CSV file not found"
    }

    $csvContentObj = Import-Csv -Path $csvFilePath
    $expectedColumns = @("SubscriptionId", "ResourceGroup", "ResourceName", "ResourceType", "Environment")
    
    if($null -eq $csvContentObj) {
        return "Unable to read CSV file"
    }
    
    if(($csvContentObj[0].PSObject.Properties | ConvertTo-Json | ConvertFrom-Json).Length -ne $expectedColumns.Length) {
        return "Invalid CSV file format"
    }       

    $csvContentObj[0].PSObject.Properties | ForEach-Object {
        if($expectedColumns -notcontains $_.Name){
            return "Invalid CSV file format"
        }
    }

    $csvContentObj | ForEach-Object {

        if($null -eq $_.SubscriptionId -or $_.SubscriptionId -eq "" -or
            $null -eq $_.ResourceGroup -or $_.ResourceGroup -eq "" -or
            $null -eq $_.ResourceName -or $_.ResourceName -eq "" -or
            $null -eq $_.ResourceType -or $_.ResourceType -eq "" -or
            $null -eq $_.Environment -or $_.Environment -eq "") {
            return "Missing content in a cell"
        }

    }

    return $csvContentObj
}
    
function Connect-Users {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$subscription,

        [Parameter(Mandatory=$true)]
        [string]$tenantId
    )
    
    if((az login --tenant $tenantId | ConvertFrom-Json).Length -gt 0){
        az account set --subscription $subscription | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        return $true
    }
    else {
        return $false
    }
        
    
}