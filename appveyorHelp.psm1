$ErrorActionPreference="Stop"

$script:INSTALL_DIR="$env:APPVEYOR_BUILD_FOLDER\work\install"
$CMAKE_INSTALL_ROOT="`"$INSTALL_DIR`"" -replace "\\", "/"
Write-Host "CMAKE_INSTALL_ROOT = $CMAKE_INSTALL_ROOT"
$env:PATH="$env:PATH;$script:INSTALL_DIR"

    
function LogExec()
{
    $OldErrorActionPreference=$ErrorActionPreference
    $ErrorActionPreference="Continue"
    $LastExitCode = 0
    Write-Host $Args
    & $Args[0] $Args[1..$Args.Count]
    if(!$LastExitCode -eq 0)
    {
        exit $LastExitCode
    }
    $ErrorActionPreference=$OldErrorActionPreference
}

#Set environment variables for Visual Studio Command Prompt
#http://stackoverflow.com/questions/2124753/how-i-can-use-powershell-with-the-visual-studio-command-prompt
function BAT-CALL([string] $path, [string] $arg)
{
    Write-Host "Calling `"$path`" `"$arg`""
    cmd /c  "$path" "$arg" `&`& set `|`| exit 1|
    foreach {
      if ($_ -match "=") {
        $v = $_.split("=")
        #Write-Host "ENV:\$($v[0])=$($v[1])"
        set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
      }
    }
    if($LastExitCode -eq 1) {
        Write-Error "$path not found."
    }
}

function CmakeImageInstall([string] $destDir)
{
    rm -Recurse "$destDir"
    $destDir=$destDir -replace "/", "\\"
    $env:DESTDIR=$destDir
    LogExec $script:MAKE install
    if(!$LastExitCode -eq 0)
    {
        Write-Error "Build Failed"
    }
    $env:DESTDIR=$null
    $prefix=$script:INSTALL_DIR
    if( $prefix.substring(1,1) -eq ":")
    {
        $prefix=$prefix.substring(3)
    }
    Write-Host "move $destDir\$prefix to $destDir"
    mv -Force "$destDir\$prefix\*" "$destDir"
    Write-Host "prefix", $prefix
    $rootLeftOver = $prefix.substring(0, $prefix.indexOf("\"))
    Write-Host "rm $destDir\$rootLeftOver"
    rm -Recurse "$destDir\$rootLeftOver"
}

function Get-QtDir()
{
    return "C:\Qt\$env:QT_VER\$env:COMPILER\"
} 

function SETUP-QT()
{
    [string] $compiler=$env:COMPILER
    $qtDir = Get-QtDir
    BAT-CALL  "$qtDir\bin\qtenv2.bat"
    if ($compiler.StartsWith("mingw"))
    {
        #remove sh.exe from path
        $env:PATH=$env:PATH -replace "C:\\Program Files \(x86\)\\Git\\bin", ""
        $script:MAKE="mingw32-make"
        $script:CMAKE_GENERATOR="MinGW Makefiles"
        $script:STRIP=@("strip", "-s")
    }
    elseif ($compiler.StartsWith("msvc"))
    {
        $arch = "x86"
        if($compiler.EndsWith("64"))
        {
            $arch = "amd64"
        }
        $compilerDirs = @{
                "msvc2010" = "VS100COMNTOOLS";
                "msvc2012" = "VS110COMNTOOLS";
                "msvc2013" = "VS120COMNTOOLS";
                "msvc2015" = "VS140COMNTOOLS"
            }

        $compilerVar = $compilerDirs[$compiler.Split("_")[0]]
        $compilerDir = (get-item -path "env:\$($compilerVar)").Value
        BAT-CALL "$compilerDir\..\..\VC\vcvarsall.bat" $arch
        $script:MAKE="nmake"
        $script:CMAKE_GENERATOR="NMake Makefiles"
    }
}

function GetArtifactName([string] $name)
{
    return "$name-Qt$env:QT_VER-$env:COMPILER.zip"
}

function FetchArtifact([string] $name){
    $fileName = GetArtifactName $name
    Write-Host "Installing artifact: $fileName"
    Start-FileDownload "$env:FETCH_ARTIFATCS_HOST/work/$fileName" -FileName "$env:APPVEYOR_BUILD_FOLDER\work\artifacts\$fileName"
    LogExec 7z x "$env:APPVEYOR_BUILD_FOLDER\work\artifacts\$fileName" -o"$env:APPVEYOR_BUILD_FOLDER\work\install"
}

function Init([string[]] $modules, [string[]] $artifacts)
{
    $script:ARTIFACTS = $artifacts
    $script:MAKE=""
    $script:CMAKE_GENERATOR=""
    $script:STRIP=$null

    mkdir -Force $env:APPVEYOR_BUILD_FOLDER\work\image | Out-Null
    mkdir -Force $env:APPVEYOR_BUILD_FOLDER\work\build | Out-Null
    mkdir -Force $env:APPVEYOR_BUILD_FOLDER\work\artifacts | Out-Null
    
    SETUP-QT
    
    if($modules -contains "ninja") {
        $script:CMAKE_GENERATOR="Ninja"
        $script:MAKE="ninja"
    }
    
    if ( !(Test-Path "$env:APPVEYOR_BUILD_FOLDER\work\install" ) )
    {
        mkdir -Force $env:APPVEYOR_BUILD_FOLDER\work\install | Out-Null
        mkdir -Force $env:APPVEYOR_BUILD_FOLDER\work\git | Out-Null
        
        foreach($module in $modules) {
            if($module -eq "extra-cmake-modules") {
                mkdir -Force $env:APPVEYOR_BUILD_FOLDER\work\build\extra-cmake-modules
                pushd $env:APPVEYOR_BUILD_FOLDER\work\git
                LogExec git clone -q git://anongit.kde.org/extra-cmake-modules.git
                popd
                pushd  $env:APPVEYOR_BUILD_FOLDER\work\build\extra-cmake-modules
                LogExec cmake -G $script:CMAKE_GENERATOR $env:APPVEYOR_BUILD_FOLDER\work\git\extra-cmake-modules -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_ROOT"
                LogExec  $script:MAKE install
                popd
                continue
            }
            Write-Host "Install chocolately package $module"
            cinst @module -y
        }
        
        foreach($artifact in $artifacts) {
            FetchArtifact $artifact
        }

    }
}

function relativePath([string] $root, [string] $path)
{
    pushd $root
    $out = Resolve-Path -Relative $path
    popd
    return $out
}

function StripFile([string] $name)
{
    if($script:STRIP) {
        if( $name.EndsWith(".dll") -or $name.EndsWith(".exe")) 
        {
            Write-Host "strip file $name"
            LogExec @script:STRIP $name
        }
    }
}

function Get-Version()
{
    if($env:APPVEYOR_REPO_TAG -eq "true") {
        return $env:APPVEYOR_REPO_TAG_NAME
    }else{
        $commit = ([string]$env:APPVEYOR_REPO_COMMIT).SubString(0,6)
        return $commit
    }
}

function Get-DeployImageName()
{
    $version = Get-Version
    if($env:APPVEYOR_REPO_TAG -eq "true") {
        return "$env:APPVEYOR_PROJECT_NAME-$version-Qt$env:QT_VER-$env:COMPILER"
    }else{
        return "$env:APPVEYOR_PROJECT_NAME-$env:APPVEYOR_REPO_BRANCH-$version-Qt$env:QT_VER-$env:COMPILER"
    }
}
function CreateDeployImage([string[]] $whiteList) 
{
    $imageName = Get-DeployImageName
    $deployPath = "$env:APPVEYOR_BUILD_FOLDER\work\deployImage\$imageName"
    
    function copyWithWhitelist([string] $root)
    {
        $files = ls $root -Recurse
        foreach($fileName in $files.FullName)
        {
            $relPath = (relativePath $root $fileName).SubString(2)
            if($whiteList | Where {$relPath -match $_})
            {
                Write-Host "copy $fileName to $deployPath\$relPath"
                mkdir -Force (Split-Path -Parent $deployPath\$relPath) | Out-Null
                cp -Force $fileName $deployPath\$relPath
                StripFile $deployPath\$relPath
            }
        }
    }
    Write-Host "CreateDeployImage $imageName"
    mkdir $deployPath | Out-Null
    
    
    copyWithWhitelist "$env:APPVEYOR_BUILD_FOLDER\work\image\"
    copyWithWhitelist "$env:APPVEYOR_BUILD_FOLDER\work\install\"
    copyWithWhitelist (Get-QtDir)
    Write-Host "Deploy path $deployPath"
    return $deployPath 
}

function 7ZipDeployImage()
{
    $imageName = Get-DeployImageName
    LogExec 7z a "$env:APPVEYOR_BUILD_FOLDER\work\deployImage\$imageName.7z" "$env:APPVEYOR_BUILD_FOLDER\work\deployImage\$imageName"
    Push-AppveyorArtifact "$env:APPVEYOR_BUILD_FOLDER\work\deployImage\$imageName.7z"
}

function NsisDeployImage([string] $scriptName)
{
    $imageName = Get-DeployImageName
    $installerName = "$env:APPVEYOR_BUILD_FOLDER\work\deployImage\$imageName.exe"
    $nsisDir = (Get-ItemProperty HKLM:\SOFTWARE\Wow6432Node\NSIS)."(default)"
    $version = Get-Version    
    LogExec $nsisDir\makensis.exe /DgitDir=$env:APPVEYOR_BUILD_FOLDER /Dsetupname=$installerName /Dcaption=$imageName /Dversion=$version /Dsrcdir=$env:APPVEYOR_BUILD_FOLDER\work\deployImage\$imageName /V4 $scriptName 
    Push-AppveyorArtifact $installerName
}

Export-ModuleMember -Function @("Init","CmakeImageInstall", "CreateDeployImage", "LogExec", "7ZipDeployImage", "NsisDeployImage") -Variable @("CMAKE_INSTALL_ROOT")
