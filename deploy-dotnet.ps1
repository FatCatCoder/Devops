#####################################################################
# Deploy-Dotnet - automation devops pipline to Backup, Git & Deploy #
#####################################################################

param([string]$name="null")

if($name -eq "null")
{
    Write-Host "Error: -name | field Required ... please add a name of the folder going here \\UFWeb3\InetPub\mobile\'name'" -ForegroundColor Red;
    Exit;
}
else {

# Literally The BEST USE OF TIME
$cooltext = @"
_____        _              _     _____ _            _ _            
|  __ \      | |            | |   |  __ (_)          | (_)           
| |  | | ___ | |_ _ __   ___| |_  | |__) | _ __   ___| |_ _ __   ___ 
| |  | |/ _ \| __| '_ \ / _ \ __| |  ___/ | '_ \ / _ \ | | '_ \ / _ \
| |__| | (_) | |_| | | |  __/ |_  | |   | | |_) |  __/ | | | | |  __/
|_____/ \___/ \__|_| |_|\___|\__| |_|   |_| .__/ \___|_|_|_| |_|\___|
                                          | |                        
                                          |_|                                                                                                                                                                                                                                                                                         
"@ 
Write-Host $cooltext -ForegroundColor Cyan;

# Variables
$Env:ASPNETCORE_ENVIRONMENT = "Production"
$backupspath = "U:\_backups" #"C:\Users\cclaudeaux\testbackups";
$path= "\\UFWeb3\InetPub\mobile\"; #  "C:\Users\cclaudeaux\testdir\"
$serverpath = "$($path)$name";




# Check for Valid IIS folder path
$vaildiisfolder = Test-Path -Path $serverpath;
if($vaildiisfolder -eq $false -or $null -eq $vaildiisfolder)
{
    Write-Host "Not A valid path or folder name on iis, PATH: $serverpath" -ForegroundColor Red
    Write-Host "Exiting Pipeline" -ForegroundColor Red
    Exit;
}


# -- ZIP CONTROL -- Copy, Zip, Del (tmp folder) => continue...
try {
    Write-Host "Copying items for backup...." -ForegroundColor Cyan
    Copy-Item -Path "$($serverpath)" -Container -Force -Recurse -Destination "$($backupspath)\$($name)" -Confirm:$false
    Compress-Archive -Path "$($backupspath)\$($name)\*"  -DestinationPath "$($backupspath)\$($name).zip" -Force -Confirm:$false
    Remove-Item -Path "$($backupspath)\$($name)" -Recurse -Confirm:$false
    Write-Host "Zip control complete, moving on..." -ForegroundColor Cyan
}
catch {
    Write-Host "WARN, Couldnt make backup" -ForegroundColor Yellow
    $confirmation = Read-Host "Are you Sure You Want To Proceed: y / n"
    if ($confirmation -eq 'y'-or $confirmation -eq 'Y' -or $confirmation -eq 'yes') {
        continue;
    }
    else { Exit }
}

# Fullstack FE / BE deployment -- Run in root folder with Solution File (.sln)
if(Test-Path -Path "*.sln")
{
    # Delete * items from IIS folder (doesnt delete api folder, only its children)
    Write-Host "Deleting files from server folder..." -ForegroundColor Cyan

    Get-ChildItem -Path "$($serverpath)" -Recurse -exclude "backup.zip", "api" |
    Select -ExpandProperty FullName |
    Where {$_ -notlike 'backup.zip' -and $_.Parent -notin ("api")} |
    sort length -Descending |
    Remove-Item -Force -Recurse -Confirm:$false

    # Recurse solution for publish profiles
    Get-Content '*.sln' |
    Select-String 'Project\(' |
      ForEach-Object {
        $projectParts = $_ -Split '[,=]' | ForEach-Object { $_.Trim('[ "{}]') };
        $projItem = New-Object PSObject -Property @{
          Name = $projectParts[1];
          File = $projectParts[2];
        }
         $pubpath = ".\$($projItem.Name)\Properties\PublishProfiles\FolderProfile.pubxml";
         $pubpathexists = Test-Path -Path $pubpath;
 
         if($pubpathexists)
         {           
            $pubxml = [Xml] (Get-Content $pubpath);
 
            Push-Location -Path $projItem.Name
            Write-Host "Executing: dotnet publish $($projItem.Name).csproj --self-contained true -c Release -f net6.0 -r $($pubxml.Project.PropertyGroup.RuntimeIdentifier) -o $($pubxml.Project.PropertyGroup.PublishUrl)" -ForegroundColor Cyan

            # publish each 
            dotnet publish --self-contained true -c Release -f net6.0 -r $($pubxml.Project.PropertyGroup.RuntimeIdentifier) -o $($pubxml.Project.PropertyGroup.PublishUrl)  /p:EnvironmentName=Production /p:PublishProfile=FolderProfile
            Pop-Location
         }
      }
}
else {
    $pubpath = ".\Properties\PublishProfiles\FolderProfile.pubxml";
    $pubxml = [Xml] (Get-Content $pubpath);

    # Deletes all files in folder execept any backup zip folders & excludes
    # - Blazor
    if($pubxml.Project.PropertyGroup.RuntimeIdentifier -eq "browser-wasm") 
    {
        # Has to recurse non root and non excluded folders then remove * root items not excluded
        Get-ChildItem -Path $($pubxml.Project.PropertyGroup.PublishUrl) -exclude "backup.zip", "api" |
        Select -ExpandProperty FullName |
        Where {$_ -notlike 'backup.zip' -and $_.Parent -notin ("api")} |
        sort length -Descending |
        Remove-Item -Force  -Recurse -Confirm:$false
    
        Get-ChildItem -Path $($pubxml.Project.PropertyGroup.PublishUrl) -exclude "backup.zip", "api"  |
        Get-ChildItem -Recurse |
        Select -ExpandProperty FullName |
        Where {$_ -notlike 'backup.zip' -and $_.Parent -notin ("api")} |
        sort length -Descending |
        Remove-Item -Force -Recurse -Confirm:$false
    }
    # - API
    elseif ($pubxml.Project.PropertyGroup.RuntimeIdentifier -eq "win-x64") { 
        Get-ChildItem -Path "$($pubxml.Project.PropertyGroup.PublishUrl)" -Recurse -exclude "backup.zip" |
        Select -ExpandProperty FullName |
        Where {$_ -notlike 'backup.zip'} |
        sort length -Descending |
        Remove-Item -Force  -Confirm:$false
    }

    dotnet publish --self-contained true -c Release -f net6.0 -r $($pubxml.Project.PropertyGroup.RuntimeIdentifier) -o $($pubxml.Project.PropertyGroup.PublishUrl)  /p:EnvironmentName=Production /p:PublishProfile=FolderProfile
}
}

Try{
    # Run Git Sync to remote production branch
    Write-Host "Trying to sync git..." -ForegroundColor Cyan
    if(git status --porcelain | Where {$_ -notmatch '^\?\?' -or $_ -match '^\?\?'}) {  # Uncommitted/staged changes
        Write-Host "Committing Changes..." -ForegroundColor Cyan
        git add .
        git commit -m "Hi From the Pipeline, meaningful deployment message goes here"
    }
    else {  # No changes
        Write-Host "No Changes, tree is clean..." -ForegroundColor Cyan
    }

    $ProdRemote = git ls-remote origin Production 
    if($ProdRemote -eq $null) {
        Write-Host "No remote 'Production' branch, please create one then sync your git changes manually (Also branch names are case sensitive, check P over p, 'required P'" -ForegroundColor DarkYellow
    }
    else{
        $branch = git rev-parse --abbrev-ref HEAD 
        if($branch -eq "Production"){
            git push origin $branch
        }
        else{ # merge branch to production
            git push origin $branch
            git checkout Production
            git merge $branch
            git push origin Production
            git checkout $branch
        }

        Write-Host "Pushed to remote branch" -ForegroundColor Cyan
    }

    Write-Host "Git Remote/Local is Sync'd" -ForegroundColor Cyan
}
Catch {
    # uncommit local
    git reset --soft HEAD^
}


#############################################################
# DEPLOYMENT COMPLETE - revert to dev ENV and show messages #
#############################################################

$Env:ASPNETCORE_ENVIRONMENT = "Development"

Write-Host "Have a good day & best of luck with the deployment!" -ForegroundColor Green

# Toast Notifcation
$PsPath = $MyInvocation.MyCommand.Path | Split-Path
Import-Module $PsPath\modules\toast.psm1
Show-Toast -ToastTitle "Deployment Complete" -ToastText "Have a good day & best of luck with the deployment!"


############
# Snippets #
############

# Gets username
# [System.Security.Principal.WindowsIdentity]::GetCurrent().Name

# health check 
# $response = Invoke-RestMethod 'https://localhost:8181/health' -Method 'GET'
# $response | ConvertTo-Json


# Teams Webhook URL - VitruvixNotificaions Channel
# https://upgamerica.webhook.office.com/webhookb2/47584067-0805-4326-9e4e-c6610950f5e0@f8ac18d2-b418-4d34-a51a-2f2718aeba9f/IncomingWebhook/a0af6618a53f4d45a18bbb54b89986ac/1dc305bd-1f5d-4f4e-9c3e-5e7720360ea5


############
### OLD ####
############

#$ZipName = -join $(Split-Path -Path ((get-item "$(Get-Location)" ).parent.FullName) -Leaf).Split(".");