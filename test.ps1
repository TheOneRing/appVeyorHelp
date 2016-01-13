$env:APPVEYOR_REPO_COMMIT="mdaidsadasdasd2381o0ad0a"
$env:COMPILER="msvc2013_64"
Import-Module .\appveyorHelp.psm1 -Force

Write-Host "test delete empty folder"
mkdir test
mkdir test\lvl1
mkdir test\lvl1\lvl2
mkdir test\lvl1.2
mkdir test\nonempty
echo "test" > test\nonempty\file.txt
DeleteEmptyFodlers test