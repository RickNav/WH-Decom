function Read-WorkSheetCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$csvFilePath
    )
    
    process {

        if(-not (Test-Path $csvFilePath)) {
            throw "CSV file not found"
        }

        $csvContentObj = Import-Csv -Path $csvFilePath
        $expectedColumns = @("SubscriptionId", "ResourceGroup", "ResourceName", "ResourceType", "Environment")

        if($null -eq $csvContentObj) {
            throw "Unable to read CSV file"
        }
        
        if(($csvContentObj[0].PSObject.Properties | ConvertTo-Json | ConvertFrom-Json).Length -ne $expectedColumns.Length) {
            throw "Invalid CSV file format"
        }       

        $csvContentObj[0].PSObject.Properties | ForEach-Object {
            if($expectedColumns -notcontains $_.Name){
                throw "Invalid CSV file format"
            }
        }

        $csvContentObj | ForEach-Object {
            if($null -eq $_.SubscriptionId -or $_.SubscriptionId -eq "" -or `
                $null -eq $_.ResourceGroup -or $_.ResourceGroup -eq "" -or `
                $null -eq $_.ResourceName -or $_.ResourceName -eq "" -or `
                $null -eq $_.ResourceType -or $_.ResourceType -eq "" -or `
                $null -eq $_.Environment -or $_.Environment -eq "") {
                throw "Empty column detected"
            }
        }
        return $csvContentObj
    }
}

function Set-Subscription {
    param (
        [Parameter(Mandatory=$true)]
        [string] $subscription
    )
    $account = az account show --subscription $subscription | ConvertFrom-Json
    if(-not $null -eq $account){
        az account set --subscription $account.id
        return $true
    }
    else {
        return $false
    }
}

function Connect-User {
    param (
        [Parameter(Mandatory=$true)]
        [string]$tenantId
    )
    $tenants = az login --tenant $tenantId | ConvertFrom-Json
    if(-not $null -eq $tenants){
        return $true
    } 
    else {
        return $false
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

function Disconnect-VnetIntegration {
    param(
        [Parameter(Mandatory=$true)]
        [string] $resourceGroup,

        [Parameter(Mandatory=$true)]
        [string] $webappName

    )
    $vnet = az webapp vnet-integration list --resource-group $resourceGroup --name $webappName | ConvertFrom-Json
    if(-not $null -eq $vnet){
        az webapp vnet-integration remove --name $webappName --resource-group $resourceGroup
        return $true
    }
    else{
        return $false
    }
}

function Get-WebAppVnetIntegration {
    param(
        [Parameter(Mandatory=$true)]
        [string]$resourceGroup,

        [Parameter(Mandatory=$true)]
        [string]$resourceName
    )
    
    $webAppIntegration = az webapp vnet-integration list --resource-group $resourceGroup --name $resourceName | ConvertFrom-Json
    
    if($null -eq $webAppIntegration) {
        throw "ResourceNotFound"
    }
    else {
        return $webAppIntegration
    }
}

function Get-Resource{
    param(
        [Parameter(Mandatory=$true)]
        [string]$resourceId
    )
    
    $resource = az resource show --ids $resourceId | ConvertFrom-Json

    if($null -eq $resource) {
        throw "ResourceNotFound"
    }
    else {
        return $resource
    }
}

function Get-WebAppByAspId {
    param (
        [Parameter(Mandatory=$true)]
        [string]$resourceId
    )
    return az webapp list --query "[?appServicePlanId=='$resourceId']" | ConvertFrom-Json
}

function Get-WebApp{
    param(

        [Parameter(Mandatory=$true)]
        [string]$resourceGroup,

        [Parameter(Mandatory=$true)]
        [string]$resourceName
    )
    
    $webApp = az webapp show --resource-group $resourceGroup --name $resourceName | ConvertFrom-Json
    
    if($null -eq $webApp) {
        throw "ResourceNotFound"
    }
    else {
        return $webApp
    }

}

function Remove-ResourceById {
    param(
        [Parameter(Mandatory=$true)]
        [string] $resourceId
    )
    try {
        $resource = Get-Resource -resourceId $resourceId
        az resource delete --ids $resource.id
        return $true
    }
    catch {
        return $false
    }
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
        [string]$tenantId,

        [switch] $Test
    )
    
    Write-Output "[$(Get-Date)] Starting Decommissioning process..."
    Write-Output "[$(Get-Date)] Reading worksheet.csv file..."
    Write-Output "[$(Get-Date)] Validating worksheet.csv file..."

    $csvContentObj = Read-WorkSheetCSV -csvFilePath $csvFilePath

    $csvSortedContentObj = Sort-Resources -csvContentObj $csvContentObj -customOrderFilePath $ResourceTypeCustomSortCsvPath

    Write-Output $csvSortedContentObj | Format-Table -AutoSize

    Write-Output "[$(Get-Date)] worksheet.csv file read and validated successfully."
    Write-Output "[$(Get-Date)] Verifying worksheet content."
    Write-Output "[$(Get-Date)] Connecting to Azure..."

    if(Connect-User -tenantId $tenantId){
        Write-Output "[$(Get-Date)] Successfully logged in to Azure."
    }
    else{
        throw "Failed to login to Azure"
    }
    Write-Output "[$(Get-Date)] Setting subscription to $subscription..."
    if(Set-Subscription -subscription $subscription){
        Write-Output "[$(Get-Date)] Successfully set to subscription $($subscription)"
    }
    else {
        throw "Failed to set subscription"
    }

    $ResourceIdsForDecom = [System.Collections.ArrayList]::new()
    
    $webappsFromCSV = [System.Collections.ArrayList]::new()
    foreach($webApp in $csvSortedContentObj){
        if($webApp.ResourceType -eq "Microsoft.Web/sites"){
            $webappsFromCSV.Add($webApp) | Out-Null
        }
    }


    $csvSortedContentObj | ForEach-Object{
        
        Write-Output "[$(Get-Date)] Checking if the resource $($_.ResourceName) exist in azure portal"
        $resource = Get-Resource -resourceId "/subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)"

        if($null -eq $resource -and $LASTEXITCODE -ne 0) {
            Write-Error "[$(Get-Date)] Error: Resource not found. Please verify the resource details in the CSV file."
            Write-Error "[$(Get-Date)] Error: resourceId: /subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)"
            throw "Resource not found"
        }
        else {
            Write-Output "[$(Get-Date)] [Verified] resourceId: $($resource.id)"
        }

    }

    # Check if web app is still on runnning state
    $webappsFromCSV  | ForEach-Object {
        $webApp = Get-WebApp -resourceGroup $_.ResourceGroup -resourceName $_.ResourceName
        
        if ($webApp.state -eq "Running") {
            Write-Output "[$(Get-Date)] Web App $($_.ResourceName) is running."
            Write-Output "[$(Get-Date)] Please stop the web app before running the script."
            Write-Output "[$(Get-Date)] Exiting proccess."
            throw "Web app is still running"
        }
    }

    $csvSortedContentObj | ForEach-Object{

        $resource = Get-Resource -resourceId "/subscriptions/$($_.SubscriptionId)/resourceGroups/$($_.ResourceGroup)/providers/$($_.ResourceType)/$($_.ResourceName)"
        
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
                $webApp = Get-WebApp -resourceGroup $_.ResourceGroup -resourceName $_.ResourceName
                if ($webApp.state -eq "Running") {
                    Write-Output "[$(Get-Date)] Web App $($_.ResourceName) is running."
                    Write-Output "[$(Get-Date)] Please stop the web app before running the script."
                    Write-Output "[$(Get-Date)] Exiting proccess."
                    throw "Web app is still running"
                }

                $webAppIntegration = Get-WebAppVnetIntegration -resourceGroup $webApp.resourceGroup -resourceName $webApp.name
                if ($webAppIntegration.Count -gt 0) {
                    # Disconnect web app from VNet integration
                    Write-Output "[$(Get-Date)] Disconnecting web app from VNet integration..."
                    if($Test){
                        # Disconnect Vnet Integration
                    }
                    else {
                        if(Disconnect-VnetIntegration -resourceGroup $resource.resourceGroup -webappName $resource.name){
                            Write-Output "[$(Get-Date)] Successfully disconnected web app from VNet integration."
                        }
                        else{
                            throw "Failed to disconnected web app from VNet integration"
                        }
                    }
                }
                $ResourceIdsForDecom.Add($resource) | Out-Null
            }

            # Check if the resource is an App Service Plan and if it still has web apps
            if ($_.ResourceType -eq "Microsoft.Web/serverfarms") {
                Write-Output "[$(Get-Date)] Verifying Microsoft.Web/serverfarms ..."
                $webAppsInAsp = Get-WebAppByAspId -resourceId $resource.id
                if($null -ne $webAppsInAsp){
                    # If the web app in ASP count is greater than 0, then the ASP still shared
                    if($webAppsInAsp.Count -gt 0) { 
                        if($webAppsInAsp.Count -ne $webappsFromCSV.Count){
                            Write-Output "[$(Get-Date)] $($_.ResourceName) is shared but listed to be decommissioned"
                            Write-Output "[$(Get-Date)] $($_.ResourceName) is shared between the following sites:"
                            $webAppsInAsp.name | Format-Table
                            Write-Output "[$(Get-Date)] Listed webapp for decommision:"
                            $webappsFromCSV.ResourceName | Format-Table
                            Write-Output "[$(Get-Date)] Check the list before running the script"
                            throw "Microsoft.Web/serverfarms is shared but listed to be decommissioned"
                        }
                        Write-Output "[$(Get-Date)] $($_.ResourceName) is shared and listed to be decommissioned."
                        Write-Output "[$(Get-Date)] All webapps under $($_.ResourceName) is listed to be decommissioned."
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
        $isDeleted = $true
        
        if($Test){
            # Delete resource by Id
        }
        else {
            $isDeleted = Remove-ResourceById -resourceId $resource.id
        }

        if ($isDeleted) {
            $DecomStatus = "Deleted"
            $DecomRemarks = "Successfully decommissioned"
        }
        else {
            Write-Error "[$(Get-Date)] Error: Failed to decommission resource: $($resource.name) with ResourceId: $($resource.id)."
            $DecomStatus = "Failed"
            $DecomRemarks = "Failed to decommission"
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