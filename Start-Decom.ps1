function Read-WorkSheetCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$csvFilePath
    )
    
    process {

        if(-not (Test-Path $csvFilePath)) {
            Write-Error "[$(Get-Date)] Error: CSV file not found at $csvFilePath"
            exit 1
        }

        $csvContentObj = Import-Csv -Path $csvFilePath
        $expectedColumns = @("SubscriptionId", "ResourceGroup", "ResourceName", "ResourceType", "Environment")

        if($null -eq $csvContentObj) {
            Write-Error "[$(Get-Date)] Error: Unable to read CSV file. File may be empty or not in the correct format."
            exit 1
        }
        
        if(($csvContentObj[0].PSObject.Properties | ConvertTo-Json | ConvertFrom-Json).Length -ne $expectedColumns.Length) {
            Write-Error "[$(Get-Date)] Error: CSV file does not contain the expected number of columns"
            exit 1
        }       

        $csvContentObj[0].PSObject.Properties | ForEach-Object {
            if($expectedColumns -notcontains $_.Name){
                Write-Error "[$(Get-Date)] Error: CSV file does not contain the expected column $($_.Name)"
                exit 1
            }
        }

        $csvContentObj | ForEach-Object {

            if($null -eq $_.SubscriptionId -or $_.SubscriptionId -eq "") {
                Write-Error "[$(Get-Date)] Error: Empty column in SubscriptionId detected"
                exit 1
            }

            if($null -eq $_.ResourceGroup -or $_.ResourceGroup -eq "") {
                Write-Error "[$(Get-Date)] Error: Empty column in ResourceGroup detected"
                exit 1
            }

            if($null -eq $_.ResourceName -or $_.ResourceName -eq "") {
                Write-Error "[$(Get-Date)] Error: Empty column in ResourceName detected"
                exit 1
            }

            if($null -eq $_.ResourceType -or $_.ResourceType -eq "") {
                Write-Error "[$(Get-Date)] Error: Empty column in ResourceType detected"
                exit 1
            }

            if($null -eq $_.Environment -or $_.Environment -eq "") {
                Write-Error "[$(Get-Date)] Error: Empty column in Environment detected"
                exit 1
            }

        }
        return $csvContentObj
    }
}

function Connect-User {
    param (
        [Parameter(Mandatory=$true)]
        [string]$subscription,

        [Parameter(Mandatory=$true)]
        [string]$tenantId
    )

    Write-Output "[$(Get-Date)] Connecting to Azure..."
    try {
        az login --tenant $tenantId --output none
        if ($LASTEXITCODE -ne 0) {
            throw "[$(Get-Date)] Error: Failed to login to Azure."
        }
        Write-Output "[$(Get-Date)] Successfully logged in to Azure."
    }
    catch {
        Write-Error $_
        exit 1
    }

    Write-Output "[$(Get-Date)] Setting subscription to $subscription..."
    try {
        az account set --subscription $subscription --output none
        if ($LASTEXITCODE -ne 0) {
            throw "[$(Get-Date)] Error: Failed to set subscription to $subscription."
        }
        Write-Output "[$(Get-Date)] Successfully set subscription to $subscription."
    }
    catch {
        Write-Error $_
        exit 1
    }
}

function Sort-Resources {
    param (
        [Parameter(Mandatory=$true)]
        [object[]]$csvContentObj,

        [Parameter(Mandatory=$true)]
        [string]$customOrderFilePath
    )

    $customOrder = Import-Csv $customOrderFilePath

    # Sort the CSV content by the custom order of ResourceType
    $sortedCsvContentObj = $csvContentObj | Sort-Object { 
        $index = $customOrder.ResourceType.IndexOf($_.ResourceType)
        if ($index -eq -1) { 
            $index = [int]::MaxValue 
        }
        $index
    }

    return $sortedCsvContentObj
    
}

function Start-Decom {
    param (
        
        [Parameter(Mandatory=$true)]
        [string]$csvFilePath,
            
        [Parameter(Mandatory=$true)]
        [string]$ResourceTypeCustomSortCsvPath,
        
        [Parameter(Mandatory=$true)]
        [string]$subscription,

        [Parameter(Mandatory=$true)]
        [string]$tenantId
    )
    
    Write-Output "[$(Get-Date)] Starting Decommissioning process..."
    Write-Output "[$(Get-Date)] Reading worksheet.csv file..."
    Write-Output "[$(Get-Date)] Validating worksheet.csv file..."

    $csvContentObj = Read-WorkSheetCSV -csvFilePath $csvFilePath

    $csvSortedContentObj = Sort-Resources -csvContentObj $csvContentObj -customOrderFilePath $ResourceTypeCustomSortCsvPath

    Write-Output $csvSortedContentObj | Format-Table -AutoSize

    Write-Output "[$(Get-Date)] worksheet.csv file read and validated successfully."
    Write-Output "[$(Get-Date)] Verifying worksheet content."

    $ResourceIdsForDecom = [System.Collections.ArrayList]::new()

    $csvSortedContentObj | ForEach-Object{

        $resource = az resource show --ids "/subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)" | ConvertFrom-Json
        
        if($resource -eq $null) {
            Write-Error "[$(Get-Date)] Error: Resource not found. Please verify the resource details in the worksheet.csv file."
            Write-Error "[$(Get-Date)] Error: resourceId: /subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)"
            exit 1
        }
        else {
            Write-Output "[$(Get-Date)] Checking ResourceId: $($resource.id)"
            # Check if the resource is a web app and if it is running
            if ($_.ResourceType -eq "Microsoft.Web/sites") {
                Write-Output "[$(Get-Date)] Verifying Microsoft.Web/sites ..."
                $webApp = az webapp show --resource-group $($_.ResourceGroup) --name $($_.ResourceName) | ConvertFrom-Json
                if ($webApp.state -eq "Running") {
                    Write-Output "[$(Get-Date)] Web App $($_.ResourceName) is running."
                    Write-Output "[$(Get-Date)] Please stop the web app before running the script."
                    Write-Output "[$(Get-Date)] Exiting proccess."
                    exit 1
                }
            }

            # Check if the resource is an App Service Plan and if it still has web apps
            if ($_.ResourceType -eq "Microsoft.Web/serverfarms") {
                Write-Output "[$(Get-Date)] Verifying Microsoft.Web/serverfarms ..."
                $webAppsInAsp = az webapp list --query "[?appServicePlanId=='$($resource.id)']" | ConvertFrom-Json
                # If the web app in ASP count is greater than 1, then the ASP still shared
                if($webAppsInAsp.Count -gt 1) { 
                    Write-Output "[$(Get-Date)] App Service Plan $($_.ResourceName) still has web apps $($webAppsInAsp.name)."
                    Write-Output "[$(Get-Date)] Please move the web apps to another App Service Plan before running the script."
                    Write-Output "[$(Get-Date)] Exiting proccess."
                    exit 1
                }
                # Else the web app in ASP count is 1, then the ASP is not shared and can be decommissioned
            }

            $ResourceIdsForDecom.Add($resource) | Out-Null
        }
    }

    $decommissionedResources = [System.Collections.ArrayList]::new()
    foreach($resource in $ResourceIdsForDecom){
        $DecomStatus = ""
        $DecomRemarks = ""

        Write-Output "[$(Get-Date)] Decommissioning $($resource.name) ..."
        az resource delete --ids $resource.id
        if ($LASTEXITCODE -ne 0) {
            Write-Error "[$(Get-Date)] Error: Failed to decommission resource: $($resource.name) with ResourceId: $($resource.id)."
            $DecomStatus = "Failed"
            $DecomRemarks = "Failed to decommission"
        }
        else {
            $DecomStatus = "Deleted"
            $DecomRemarks = "Successfully decommissioned"
        }

        $decommissionedResource = [PSCustomObject]@{
            ResourceName = $resource.name
            ResourceType = $resource.type
            ResourceLocation = $resource.location
            ResourceId = $resource.id
            DecomStatus = $DecomStatus
            Remarks = $DecomRemarks
            Date = Get-Date
        }

        $decommissionedResources.Add($decommissionedResource)

    }

    $decommissionedResources | Export-Csv -Path ".\$(Get-Date -Format "yyyyMMddHHmmss")_DecommissionedResources.csv" -NoTypeInformation

    Write-Output "[$(Get-Date)] Decommissioning process completed successfully."

}

Start-Decom -csvFilePath .\worksheet.csv -ResourceTypeCustomSortCsvPath .\ResourceTypeCustomSort.csv -subscription "2d1c7006-7070-45e4-a17a-c791cad26905" -tenantId "b3f4f7c2-72ce-4192-aba4-d6c7719b5766"
