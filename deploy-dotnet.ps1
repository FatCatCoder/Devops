param([string]$name="null")

if($name -eq "null")
{
    Write-Host "Error: -name | field Required ... please add a name of the folder going here \\UFWeb3\InetPub\mobile\'name'" -ForegroundColor Red;
    Exit;
}
else {

# Literally The BEST USE OF TIME
$cooltext = @"
________          __                __    __________.__              .__  .__               
\______ \   _____/  |_ ____   _____/  |_  \______   |________   ____ |  | |__| ____   ____  
    |    |  \ /  _ \   __/    \_/ __ \   __\  |     ___|  \____ \_/ __ \|  | |  |/    \_/ __ \ 
    |    `   (  <_> |  ||   |  \  ___/|  |    |    |   |  |  |_> \  ___/|  |_|  |   |  \  ___/ 
/_______  /\____/|__||___|  /\___  |__|    |____|   |__|   __/ \___  |____|__|___|  /\___  >
        \/                \/     \/                    |__|        \/             \/     \/ 
"@ 
Write-Host $cooltext -ForegroundColor Cyan;


$Env:ASPNETCORE_ENVIRONMENT = "Production"

# Variables
$backupspath = "Z:\backups" 
$path= "\\Path\To\Server";
$serverpath = "$($path)$name";

# Check for Valid IIS folder path
$vaildiisfolder = Test-Path -Path $serverpath;
if($vaildiisfolder -eq $false -or $null -eq $vaildiisfolder)
{
    Write-Host "Not A valid path or folder name on iis, PATH: $serverpath" -ForegroundColor Red
    Write-Host "Exiting Pipeline" -ForegroundColor Red
    Exit;
}


# -- ZIP CONTROL --
# Copy => Zip => Del (copy tmp folder) => continue...
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
    # Delete * items from IIS folder (doenst delete api folder, only its children)
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

            dotnet publish --self-contained true -c Release -f net6.0 -r $($pubxml.Project.PropertyGroup.RuntimeIdentifier) -o $($pubxml.Project.PropertyGroup.PublishUrl)
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
    elseif ($pubxml.Project.PropertyGroup.RuntimeIdentifier -eq "win-64") { 
        Get-ChildItem -Path "$($pubxml.Project.PropertyGroup.PublishUrl)" -Recurse -exclude "backup.zip" |
        Select -ExpandProperty FullName |
        Where {$_ -notlike 'backup.zip'} |
        sort length -Descending |
        Remove-Item -Force  -Confirm:$false
    }

    dotnet publish --self-contained true -c Release -f net6.0 -r $($pubxml.Project.PropertyGroup.RuntimeIdentifier) -o $($pubxml.Project.PropertyGroup.PublishUrl)
}
}

Try{
    # Run Git Sync to remote production branch
    Write-Host "Trying to sync git..." -ForegroundColor Cyan
    if(git status --porcelain | Where {$_ -notmatch '^\?\?' -or $_ -match '^\?\?'}) {  # Uncommitted/staged changes
        Write-Output "Has Changes To Be Committed";

        $ProdRemote = git ls-remote origin Production 

        if($ProdRemote -eq $null) {
            Write-Host "No remote 'Production' branch, please create one then sync your git changes manually (Also branch names are case sensitive, check P over p, 'required P'" -ForegroundColor DarkYellow
        }
        else{
            $branch = &git rev-parse --abbrev-ref HEAD 

            git add .
    
            git commit -m "Hi From the Pipeline, meaningful deployment message goes here"
            
            git push origin "$($branch):Production"

            Write-Host "Git Remote/Local is Sync'd" -ForegroundColor Cyan
        } 
    }
    else {  # No changes
        Write-Host "No Changes, tree is clean...." -ForegroundColor Cyan
    }
}
Catch {
    # uncommit local
    git reset --soft HEAD^
}

$Env:ASPNETCORE_ENVIRONMENT = "Development"

Write-Host "Have a good day & best of luck with the deployment!" -ForegroundColor Green