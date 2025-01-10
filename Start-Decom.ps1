function Read-WorkSheetCSV {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$csvFilePath
    )
    
    process {
        $csvContentObj = Import-Csv -Path $csvFilePath
        $expectedColumns = @("SubscriptionId", "ResourceGroup", "ResourceName", "ResourceType", "Environment")

        if($null -eq $csvContentObj) {
            Write-Error "Error: Unable to read CSV file. File may be empty or not in the correct format."
            $csvContentObj = $null
            return $csvContentObj
        }
        
        if(($csvContentObj[0].PSObject.Properties | ConvertTo-Json | ConvertFrom-Json).Length -ne $expectedColumns.Length) {
            Write-Error "Error: CSV file does not contain the expected number of columns"
            $csvContentObj = $null
            return $csvContentObj
        }       

        $csvContentObj[0].PSObject.Properties | ForEach-Object {
            if($expectedColumns -notcontains $_.Name){
                Write-Error "Error: CSV file does not contain the expected column $($_.Name)"
                $csvContentObj = $null
                return $csvContentObj
            }
        }

        $csvContentObj | ForEach-Object {

            if($null -eq $_.SubscriptionId -or $_.SubscriptionId -eq "") {
                Write-Error "Error: Empty column in SubscriptionId detected"
                $csvContentObj = $null
                return $csvContentObj
            }

            if($null -eq $_.ResourceGroup -or $_.ResourceGroup -eq "") {
                Write-Error "Error: Empty column in ResourceGroup detected"
                $csvContentObj = $null
                return $csvContentObj
            }

            if($null -eq $_.ResourceName -or $_.ResourceName -eq "") {
                Write-Error "Error: Empty column in ResourceName detected"
                $csvContentObj = $null
                return $csvContentObj
            }

            if($null -eq $_.ResourceType -or $_.ResourceType -eq "") {
                Write-Error "Error: Empty column in ResourceType detected"
                $csvContentObj = $null
                return $csvContentObj
            }

            if($null -eq $_.Environment -or $_.Environment -eq "") {
                Write-Error "Error: Empty column in Environment detected"
                $csvContentObj = $null
                return $csvContentObj
            }

        }
        return $csvContentObj
    }
}

Write-Output "[$(Get-Date)] Starting Decommissioning process..."
Write-Output "[$(Get-Date)] Reading worksheet.csv file..."
Write-Output "[$(Get-Date)] Validating worksheet.csv file..."

$csvContentObj = Read-WorkSheetCSV -csvFilePath "C:\Users\JohnPatrick\Navitaire\WH-Decom\worksheet.csv"
Write-Output $csvContentObj | Format-Table -AutoSize

