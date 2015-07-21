$script:MAKE=""
$script:CMAKE_GENERATOR=""

$script:INSTALL_DIR="$env:APPVEYOR_BUILD_FOLDER\work\install"
$CMAKE_INSTALL_ROOT=$INSTALL_DIR -replace "\\", "/"
$env:PATH="$env:PATH;$script:INSTALL_DIR"

#Set environment variables for Visual Studio Command Prompt
#http://stackoverflow.com/questions/2124753/how-i-can-use-powershell-with-the-visual-studio-command-prompt
function BAT-CALL([string] $path, [string] $arg)
{
    Write-Host "Calling `"$path`" `"$arg`""
    cmd /c  "$path" "$arg" `& set |
    foreach {
      if ($_ -match "=") {
        $v = $_.split("=")
        #Write-Host "ENV:\$($v[0])=$($v[1])"
        set-item -force -path "ENV:\$($v[0])"  -value "$($v[1])"
      }
    }
}

function CMAKE-IMAGE-INSTALL([string] $destDir)
{
    $destDir=$destDir -replace "/", "\\"
    Write-Host "tCmakeInstall", $destDir
    Write-Host "make", $script:MAKE
    $env:DESTDIR=$destDir
    & $script:MAKE install
    $env:DESTDIR=$null
    $prefix=$script:INSTALL_DIR
    if( $prefix.substring(1,1) -eq ":")
    {
        $prefix=$prefix.substring(3)
    }
    Write-Host "move $destDir\$prefix to $destDir"
    mv "$destDir\$prefix\*" "$destDir"
    $rootLeftOver = $prefix.substring(0, $prefix.indexOf("\\"))
    Write-Host "rm $destDir\$rootLeftOver"
    rm -Recurse "$destDir\$rootLeftOver"
}

function SETUP-QT()
{
    if ( $env:COMPILER -eq "MINGW" )
    {
        BAT-CALL "C:\Qt\5.5\mingw492_32\bin\qtenv2.bat"
        #remove sh.exe from path
        $env:PATH=$env:PATH -replace "C:\\Program Files \(x86\)\\Git\\bin", ""
        $script:MAKE="mingw32-make"
        $script:CMAKE_GENERATOR="MinGW Makefiles"
    }
    elseif ( $env:COMPILER -eq "MSVC" )
    {
        BAT-CALL "C:\Qt\5.5\msvc2013_64\bin\qtenv2.bat"
        BAT-CALL "C:\Program Files (x86)\Microsoft Visual Studio 12.0\VC\vcvarsall.bat" amd64
        $script:MAKE="nmake"
        $script:CMAKE_GENERATOR="NMake Makefiles"
    }
}

function INIT([string[]] $modules)
{
    SETUP-QT
    mkdir $env:APPVEYOR_BUILD_FOLDER\work\image
    mkdir $env:APPVEYOR_BUILD_FOLDER\work\build
    
    if($modules -contains "ninja") {
        $script:CMAKE_GENERATOR="Ninja"
        $script:MAKE="ninja"
        $env:PATH="$env:PATH;C:/tools/ninja"
    }
    
    if ( !(Test-Path "$env:APPVEYOR_BUILD_FOLDER\work\install" ) )
    {
        mkdir $env:APPVEYOR_BUILD_FOLDER\work\install
        mkdir $env:APPVEYOR_BUILD_FOLDER\work\git
        
        if($modules -contains "ninja") {
            cinst ninja
        }
        
        if($modules -contains "extra-cmake-modules") {
            mkdir $env:APPVEYOR_BUILD_FOLDER\work\build\extra-cmake-modules
            cd $env:APPVEYOR_BUILD_FOLDER\work\git
            git clone -q git://anongit.kde.org/extra-cmake-modules.git
            
            cd $env:APPVEYOR_BUILD_FOLDER\work\build\extra-cmake-modules
            cmake -G $script:CMAKE_GENERATOR $env:APPVEYOR_BUILD_FOLDER\work\git\extra-cmake-modules -DCMAKE_INSTALL_PREFIX="$CMAKE_INSTALL_ROOT"
            & $script:MAKE install
        }
    }
}

Export-ModuleMember -Function @("INIT","CMAKE-IMAGE-INSTALL") -Variable @("CMAKE_INSTALL_ROOT")
