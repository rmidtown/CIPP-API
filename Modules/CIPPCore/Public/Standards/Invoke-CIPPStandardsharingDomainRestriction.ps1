function Invoke-CIPPStandardsharingDomainRestriction {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) sharingDomainRestriction
    .SYNOPSIS
        (Label) Restrict sharing to a specific domain
    .DESCRIPTION
        (Helptext) Restricts sharing to only users with the specified domain. This is useful for organizations that only want to share with their own domain.
        (DocsDescription) Restricts sharing to only users with the specified domain. This is useful for organizations that only want to share with their own domain.
    .NOTES
        CAT
            SharePoint Standards
        TAG
            "CIS"
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"name":"standards.sharingDomainRestriction.Mode","label":"Limit external sharing by domains","options":[{"label":"Off","value":"none"},{"label":"Restrict sharing to specific domains","value":"allowList"},{"label":"Block sharing to specific domains","value":"blockList"}]}
            {"type":"textField","name":"standards.sharingDomainRestriction.Domains","label":"Domains to allow/block, comma separated","required":false}
        IMPACT
            High Impact
        ADDEDDATE
            2024-06-20
        POWERSHELLEQUIVALENT
            Update-MgAdminSharePointSetting
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'sharingDomainRestriction' -TenantFilter $Tenant -RequiredCapabilities @('SHAREPOINTWAC', 'SHAREPOINTSTANDARD', 'SHAREPOINTENTERPRISE', 'ONEDRIVE_BASIC', 'ONEDRIVE_ENTERPRISE')

    if ($TestResult -eq $false) {
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $CurrentState = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/admin/sharepoint/settings' -tenantid $Tenant -AsApp $true
    }
    catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the SharingDomainRestriction state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    # Get mode value using null-coalescing operator
    $mode = $Settings.Mode.value ?? $Settings.Mode

    if ($mode -eq 'none' -or $null -eq $mode) {
        $StateIsCorrect = $CurrentState.sharingDomainRestrictionMode -eq 'none'
    } else {
        $SelectedDomains = [String[]]$Settings.Domains.Split(',').Trim() ?? @()
        $CurrentAllowedDomains = $CurrentState.sharingAllowedDomainList ?? @()
        $CurrentBlockedDomains = $CurrentState.sharingBlockedDomainList ?? @()

        $StateIsCorrect = ($CurrentState.sharingDomainRestrictionMode -eq $mode) -and (
            ($mode -eq 'allowList' -and ([string[]]($CurrentAllowedDomains | Sort-Object) -join ',') -eq ([string[]]($SelectedDomains | Sort-Object) -join ',')) -or
            ($mode -eq 'blockList' -and ([string[]]($CurrentBlockedDomains | Sort-Object) -join ',') -eq ([string[]]($SelectedDomains | Sort-Object) -join ','))
        )
    }
    Write-Host "StateIsCorrect: $StateIsCorrect"

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sharing Domain Restriction is already correctly configured' -sev Info
        } else {
            $Body = @{
                sharingDomainRestrictionMode = $mode
            }

            if ($mode -eq 'AllowList') {
                $Body.Add('sharingAllowedDomainList', $SelectedDomains)
            } elseif ($mode -eq 'BlockList') {
                $Body.Add('sharingBlockedDomainList', $SelectedDomains)
            }

            $cmdParams = @{
                tenantid = $tenant
                uri      = 'https://graph.microsoft.com/beta/admin/sharepoint/settings'
                AsApp    = $true
                Type     = 'PATCH'
                body     = ($Body | ConvertTo-Json)
            }

            Write-Host ($cmdParams | ConvertTo-Json -Depth 5)

            try {
                $null = New-GraphPostRequest @cmdParams
                Write-LogMessage -API 'Standards' -tenant $tenant -message 'Successfully updated Sharing Domain Restriction settings' -sev Info
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to update Sharing Domain Restriction settings. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sharing Domain Restriction is correctly configured' -sev Info
        } else {
            Write-StandardsAlert -message 'Sharing Domain Restriction is not correctly configured' -object $CurrentState -tenant $tenant -standardName 'sharingDomainRestriction' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'Sharing Domain Restriction is not correctly configured' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        Add-CIPPBPAField -FieldName 'sharingDomainRestriction' -FieldValue [bool]$StateIsCorrect -StoreAs bool -Tenant $tenant

        if ($StateIsCorrect) {
            $FieldValue = $true
        } else {
            $FieldValue = $CurrentState | Select-Object sharingAllowedDomainList, sharingDomainRestrictionMode
        }
        Set-CIPPStandardsCompareField -FieldName 'standards.sharingDomainRestriction' -FieldValue $FieldValue -Tenant $Tenant
    }
}
