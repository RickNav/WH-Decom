BeforeAll {
    . .\Start-Decom.ps1
}


Describe "Read-WorkSheetCSV" {
    It "returns 'CSV file not found' if file does not exist" {
        { Read-WorkSheetCSV -csvFilePath "nonexistent.csv" } | Should -Throw "CSV file not found"
    }

    It "returns 'Invalid CSV file format' if the CSV does not have the expected columns" {
        $csvFilePath = "invalid_columns.csv"
        $csvContent = @"
Name,Age
John,30
"@
        Set-Content -Path $csvFilePath -Value $csvContent
        { Read-WorkSheetCSV -csvFilePath $csvFilePath } | Should -Throw "Invalid CSV file format"
        Remove-Item -Path $csvFilePath
    }

    It "returns 'Unable to read CSV file' if the CSV content is null" {
        $csvFilePath = "empty.csv"
        Set-Content -Path $csvFilePath -Value ""
        { Read-WorkSheetCSV -csvFilePath $csvFilePath } | Should -Throw "Unable to read CSV file"
        Remove-Item -Path $csvFilePath 
    }

    It "returns 'Empty column detected' if any cell is empty" {
        $csvFilePath = "missing_content.csv"
        $csvContent = @"
SubscriptionId,ResourceGroup,ResourceName,ResourceType,Environment
sub1,rg1,,type1,env1
"@
        Set-Content -Path $csvFilePath -Value $csvContent
        { Read-WorkSheetCSV -csvFilePath $csvFilePath } | Should -Throw "Empty column detected"
        Remove-Item -Path $csvFilePath
    }

    It "returns the CSV content as an object if the CSV is valid" {
        $csvFilePath = "valid.csv"
        $csvContent = @"
SubscriptionId,ResourceGroup,ResourceName,ResourceType,Environment
sub1,rg1,res1,type1,env1
"@
        Set-Content -Path $csvFilePath -Value $csvContent
        $result = Read-WorkSheetCSV -csvFilePath $csvFilePath
        $result | Should -BeOfType "System.Management.Automation.PSCustomObject"
        $result[0].SubscriptionId | Should -Be "sub1"
        $result[0].ResourceGroup | Should -Be "rg1"
        $result[0].ResourceName | Should -Be "res1"
        $result[0].ResourceType | Should -Be "type1"
        $result[0].Environment | Should -Be "env1"
        Remove-Item -Path $csvFilePath
    }
}

Describe "Connect-User" {

    BeforeEach{
        Mock az {   
            return '[{ "tenantId": "valid-tenant-id" }]'
        } -ParameterFilter {
            $args -contains "login" -and 
            $args -contains "--tenant" -and 
            $args -contains "valid-tenant-id"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return true if login is successful" {
        $result = Connect-User -tenantId "valid-tenant-id"
        $result | Should -BeTrue
    }

    It "Return false if login is unsuccessful" {
        $result = Connect-User -tenantId "invalid-tenant-id"
        $result | Should -BeFalse
    }
}

Describe "Set-Subscription" {

    BeforeEach{
        Mock az {   
            return '{ "id": "valid-subscription-id" }'
        } -ParameterFilter {
            $args -contains "account" -and 
            $args -contains "show" -and 
            $args -contains "--subscription" -and 
            $args -contains "valid-subscription-id"
        }
        Mock az { } -ParameterFilter {
            $args -contains "account" -and 
            $args -contains "set" -and 
            $args -contains "--subscription" -and 
            $args -contains "valid-subscription-id"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return true if subscription is valid" {
        $result = Set-Subscription -subscription "valid-subscription-id"
        $result | Should -BeTrue
    }

    It "Return false if subscription is invalid" {
        $result = Set-Subscription -subscription "invalid-subscription-id"
        $result | Should -BeFalse
    }
}

Describe "Disconnect-VnetIntegration" {
    BeforeEach{
        Mock az {   
            return '[{ "id": "valid-id" }]'
        } -ParameterFilter {
            $args -contains "webapp" -and 
            $args -contains "vnet-integration" -and 
            $args -contains "list" -and 
            $args -contains "--name" -and 
            $args -contains "valid-webapp" -and 
            $args -contains "--resource-group" -and 
            $args -contains "valid-resourcegroup"
        }
        Mock az { } -ParameterFilter {
            $args -contains "webapp" -and 
            $args -contains "vnet-integration" -and 
            $args -contains "remove" -and 
            $args -contains "--name" -and 
            $args -contains "valid-webapp" -and 
            $args -contains "--resource-group" -and 
            $args -contains "valid-resourcegroup"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return true if vnet integration is successfully removed" {
        $result = Disconnect-VnetIntegration -resourceGroup "valid-resourcegroup" -webappName "valid-webapp"
        $result | Should -BeTrue
    }

    It "Return false if vnet integration is unsuccessfully removed" {
        $result = Disconnect-VnetIntegration -resourceGroup "invalid-resourcegroup" -webappName "invalid-webapp"
        $result | Should -BeFalse
    }
}

Describe "Get-WebAppVnetIntegration" {
    BeforeEach{
        Mock az { 
            return '{ "id": "valid-id" }'
        } -ParameterFilter {
            $args -contains "webapp" -and
            $args -contains "vnet-integration" -and
            $args -contains "list" -and
            $args -contains "--name" -and
            $args -contains "valid-webapp" -and
            $args -contains "--resource-group" -and
            $args -contains "valid-resourcegroup"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return valid id if web app has vnet integration" {
        $result = Get-WebAppVnetIntegration -resourceGroup "valid-resourcegroup" -resourceName "valid-webapp"
        $result.id | Should -Be "valid-id"
    }

    It "Throw ResourceNotFound if web app dont exist" {
        { Get-WebAppVnetIntegration -resourceGroup "invalid-resourcegroup" -resourceName "invalid-webapp" } | Should -Throw "ResourceNotFound"
    }

}

Describe "Get-Resource" {
    BeforeEach{
        Mock az { 
            return '{"id":"valid-id"}'
        } -ParameterFilter {
            $args -contains "resource" -and
            $args -contains "show" -and
            $args -contains "--ids" -and
            $args -contains "valid-id"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return valid id if resource exists" {
        $result = Get-Resource -resourceId "valid-id"
        $result.id | Should -Be "valid-id"
    }

    It "Throw ResourceNotFound if resource do not exist" {
        { Get-Resource -resourceId "invalid-id" } | Should -Throw "ResourceNotFound"
    }
}

Describe "Get-WebAppByAspId" {
    BeforeEach {
        Mock az { 
            return '[{"id":"valid-id"}]'
        } -ParameterFilter {
            $args -contains "webapp" -and
            $args -contains "list" -and
            $args -contains "--query" -and
            $args -contains "[?appServicePlanId=='valid-id']"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return valid id if web app exists" {
        $result = Get-WebAppByAspId -resourceId "valid-id"
        $result[0].id | Should -Be "valid-id"
    }

    It "Throw ResourceNotFound if web app dont exist" {
        $result = Get-WebAppByAspId -resourceId "invalid-id"
        $result | Should -Be $null
    }

}

Describe "Get-WebApp" {
    BeforeEach{
        Mock az { 
            return '{"id":"valid-id"}'
        } -ParameterFilter {
            $args -contains "webapp" -and
            $args -contains "show" -and
            $args -contains "--name" -and
            $args -contains "valid-webapp" -and
            $args -contains "--resource-group" -and
            $args -contains "valid-resourcegroup"
        }
    }

    AfterEach{
        $global:LASTEXITCODE = $null
    }
    It "Return valid id if web app exists" {
        $result = Get-WebApp -resourceGroup "valid-resourcegroup" -resourceName "valid-webapp"
        $result.id | Should -Be "valid-id"
    }

    It "Throw ResourceNotFound if web app dont exist" {
        { Get-WebApp -resourceGroup "valid-resourcegroup" -resourceName "invalid-webapp" } | Should -Throw "ResourceNotFound"
    }
}

Describe "Remove-ResourceById" {

    BeforeEach {
        Mock Get-Resource {
            return @{ id = "valid-id" }
        } -ParameterFilter {
            $resourceId -eq "valid-id"
        }
        
        Mock az {
            return $true
        } -ParameterFilter {
            $args -contains "resource" -and
            $args -contains "delete" -and
            $args -contains "--ids" -and
            $args -contains "valid-id"
        }
    } 

    AfterEach{
        $global:LASTEXITCODE = $null
    }

    It "Return valid id if deletion is successfull" {
        $result = Remove-ResourceById -resourceId "valid-id"
        $result | Should -BeTrue
    }

    It "Return false if resource do not exist" {
        $result = Remove-ResourceById -resourceId "invalid-id"
        $result | Should -BeFalse
    }

}