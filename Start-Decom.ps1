function Read-WorkSheetCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$csvFilePath
    )
    
    process {

        if(-not (Test-Path $csvFilePath)) {
            Write-Error "[$(Get-Date)] Error: CSV file not found at $csvFilePath"
            throw "CSV file not found"
            exit 1
        }

        $csvContentObj = Import-Csv -Path $csvFilePath
        $expectedColumns = @("SubscriptionId", "ResourceGroup", "ResourceName", "ResourceType", "Environment")

        if($null -eq $csvContentObj) {
            Write-Error "[$(Get-Date)] Error: Unable to read CSV file. File may be empty or not in the correct format."
            exit 1
        }
        
        if(($csvContentObj[0].PSObject.Properties | ConvertTo-Json | ConvertFrom-Json).Length -ne $expectedColumns.Length) {
            Write-Error "[$(Get-Date)] Error: Invalid CSV file format"
            throw "Invalid CSV file format"
            exit 1
        }       

        $csvContentObj[0].PSObject.Properties | ForEach-Object {
            if($expectedColumns -notcontains $_.Name){
                Write-Error "[$(Get-Date)] Error: CSV file does not contain the expected column $($_.Name)"
                throw "Invalid CSV file format"
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
            Write-Error "[$(Get-Date)] Failed to login to Azure."
            throw "Failed to login to Azure"
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

    Connect-User -subscription $subscription -tenantId $tenantId

    $ResourceIdsForDecom = [System.Collections.ArrayList]::new()
    
    $webappsFromCSV = [System.Collections.ArrayList]::new()
    foreach($webApp in $csvSortedContentObj){
        if($webApp.ResourceType -eq "Microsoft.Web/sites"){
            $webappsFromCSV.Add($webApp.ResourceName) | Out-Null
        }
    }


    $csvSortedContentObj | ForEach-Object{
        
        Write-Output "[$(Get-Date)] Checking if the resource $($_.ResourceName) exist in azure portal"
        $resource = az resource show --ids "/subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)" | ConvertFrom-Json
        
        if($null -eq $resource -and $LASTEXITCODE -ne 0) {
            Write-Error "[$(Get-Date)] Error: Resource not found. Please verify the resource details in the CSV file."
            Write-Error "[$(Get-Date)] Error: resourceId: /subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)"
            throw "Resource not found"
            exit 1
        }
        else {
            Write-Output "[$(Get-Date)] [Verified] resourceId: $($resource.id)"
        }

    }


    $csvSortedContentObj | ForEach-Object{

        $resource = az resource show --ids "/subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)" | ConvertFrom-Json
        
        if($null -eq $resource -and $LASTEXITCODE -ne 0) {
            Write-Error "[$(Get-Date)] Error: Resource not found. Please verify the resource details in the CSV file."
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
                    throw "Web app is still running"
                    exit 1
                }

                if ((az webapp vnet-integration list -g $webApp.resourceGroup -n $webApp.name | ConvertFrom-Json).Count -gt 0) {
                    # Disconnect web app from VNet integration
                    Write-Output "[$(Get-Date)] Disconnecting web app from VNet integration..."
                    try {
                        az webapp vnet-integration remove --name $resource.name --resource-group $resource.resourceGroup
                        if ($LASTEXITCODE -ne 0) {
                            throw "Failed to disconnect web app from VNet integration"
                        }
                        Write-Output "[$(Get-Date)] Successfully disconnected web app from VNet integration."
                    }
                    catch {
                        Write-Error $_
                        exit 1
                    }
                }
                $ResourceIdsForDecom.Add($resource) | Out-Null
            }

            # Check if the resource is an App Service Plan and if it still has web apps
            if ($_.ResourceType -eq "Microsoft.Web/serverfarms") {
                Write-Output "[$(Get-Date)] Verifying Microsoft.Web/serverfarms ..."
                $webAppsInAsp = az webapp list --query "[?appServicePlanId=='$($resource.id)']" | ConvertFrom-Json
                if($null -ne $webAppsInAsp){
                    # If the web app in ASP count is greater than 0, then the ASP still shared
                    if($webAppsInAsp.Count -gt 0) { 
                        if($webAppsInAsp.Count -ne $webappsFromCSV.Count){
                            Write-Output "[$(Get-Date)] $($_.ResourceName) is shared but listed to be decommissioned"
                            Write-Output "[$(Get-Date)] $($_.ResourceName) is shared between the following sites:"
                            $webAppsInAsp.name | Format-Table
                            Write-Output "[$(Get-Date)] Listed webapp for decommision:"
                            $webappsFromCSV | Format-Table
                            Write-Output "[$(Get-Date)] Check the list before running the script"
                            exit 1
                        }
                        $ResourceIdsForDecom.Add($resource) | Out-Null
                    }
                    else {
                        Write-Output "[$(Get-Date)] $($_.ResourceName) is not shared and listed to be decommissioned."
                        $ResourceIdsForDecom.Add($resource) | Out-Null
                    }
                }
            }
        }
    }

    $decommissionedResources = [System.Collections.ArrayList]::new()
    foreach($resource in $ResourceIdsForDecom){
        $DecomStatus = ""
        $DecomRemarks = ""

        Write-Output "[$(Get-Date)] Decommissioning $($resource.name) ..."
        # az resource delete --ids $resource.id
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

        $decommissionedResources.Add($decommissionedResource) | Out-Null

    }

    $decommissionedResources | Export-Csv -Path ".\$(Get-Date -Format "yyyyMMddHHmmss")_DecommissionedResources.csv" -NoTypeInformation

    Write-Output "[$(Get-Date)] Decommissioning process completed successfully."

}