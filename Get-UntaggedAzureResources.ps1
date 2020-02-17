<#
    .SYNOPSIS
        List resources in Azure that are untagged and sends a report via email.
    
    .DESCRIPTION
        This script generates a list of untagged resources in all the subscriptions of an Azure tenant.  The collected results are sent via email to recipients.
    
    .PARAMETER x
        NA
 
    .EXAMPLE
        NA
     
    .INPUTS
        String
        
    .OUTPUTS
        PSResource
    
    .NOTES
        NAME: Get-UntaggedAzureResources.ps1
        AUTHOR: Edward Bernard, DevOps Engineer
        CREATED: 10/02/2019
        LASTEDIT: 12/13/2019
        VERSION: 1.5.0 - Added authentication retry logic and SendGrid details.
        VERSION: 1.0.0
                      
    .LINK
        https://        
#>
param (
    [int]$count         = $null,
    [array]$results     = @(),
    [string]$smtpserver = "smtp.sendgrid.net",
    [string]$from       = "NoReply-UntaggedResources@contosoazure.org",
    [string[]]$to       = ("someone@somewhere.com","DevOPs-DL@contoso.com"),
    [string]$subject    = "Untagged Azure Resources - ContosoAzure Organization"
)
 
filter timestamp {"[$(Get-Date -Format G)]: $_"}

$connection = Get-AutomationConnection -Name "AzureRunAsConnection"

# Wrap authentication in retry logic for transient network failures.
$logonAttempt = 0
while(!($connectionResult) -and ($logonAttempt -le 5))
{
    $LogonAttempt++
    # Logging in to Azure...
    $connectionResult = Add-AzureRmAccount `
                            -ServicePrincipal `
                            -Tenant $connection.TenantID `
                            -ApplicationID $connection.ApplicationID `
                            -CertificateThumbprint $connection.CertificateThumbprint

    Start-Sleep -Seconds 30
}

Write-Output "Authenticated with Automation Run As Account." | timestamp

Write-Output "Starting Script" | timestamp
 
# Fetch Azure resource details.
$subscriptions = (Get-AzureRmSubscription).Name

foreach ($subscription in $subscriptions) {
    Set-AzureRmContext -Subscription $subscription | Out-Null
    Write-Host "Getting untagged resources in $subscription..." -ForegroundColor Magenta
    $resources = Get-AzureRmResource -ErrorAction Stop
        foreach ($resource in $resources) {
            $tagCount = ($resources | Where-Object {$PSItem.Name -eq $resource.Name}).Tags.count
            $count ++
            $progressParams = @{
                'Activity'        = 'Checking Azure Resources'
                'Status'          = "Untaged Azure resources: {0} / {1} - {2:p}" -f $count, $resources.Count, ($count / $resources.Count)
                'PercentComplete' = (($count / $($resources.count)) * 100) -as [int]
            }
            Write-Progress @progressParams
        
            ForEach-Object {
                if($tagCount -eq 0) {
                    $hash = [PSCustomObject]@{
                        Name          = $resource.Name
                        ResourceGroup = $resource.ResourceGroupName
                        Subscription  = $subscription
                        ResourceType  = $resource.ResourceType
                        Location      = $resource.Location
                    }
                $results += $hash         
            }
        }
    }
    Write-Host "`tDone." -ForegroundColor Green
    $count = $null
}
 
Write-Host @"
`nComplete - Review collected data for details
Total number of untagged resources: $($results.Count) 
"@ -ForegroundColor Green

# Create a new mail message.
$message = New-Object System.Net.Mail.MailMessage
$message.Priority = [System.Net.Mail.MailPriority]::High
$Username = "<sendgrid_identity>@azure.com"
$Password = ConvertTo-SecureString '<sendgrid_identity_password>' -AsPlainText -Force
$credential = New-Object System.Management.Automation.PSCredential $Username, $Password

# Adds more styles to the table to make it look nice.
$style = "<style>BODY{font-family: segoe ui; font-size: 10pt;}"
$style = $style + "TABLE{border: 1px solid black; border-collapse: collapse;}"
$style = $style + "TH{border-width: 1px; padding: 3px; border-style: solid; border-color: black; background-color: #6495ED}"
$style = $style + "TD{border: 1px solid black; padding: 5px; }"
$style = $style +"</style>"
 
# Send email.
$emailParams = @{
    From       = $from
    To         = $to
    Body       = "$($results | ConvertTo-Html -Head $style -As Table -Body "<b>Non-compliant: $($results.count)<br><br>")"
    Subject    = $subject
    Priority   = $message.Priority
    SmtpServer = $smtpServer
    BodyAsHtml = $true
}
 
# Create the SMTP client object and send the mail message.
Write-Host "Sending email..." -ForegroundColor Yellow
Send-MailMessage @emailParams -Credential $credential -UseSsl -Port 587
Write-Host "Email sent." -ForegroundColor Green