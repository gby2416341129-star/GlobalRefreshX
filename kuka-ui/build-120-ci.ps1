$ErrorActionPreference = 'Stop'

function Expand-GzipBase64Patch([string]$source, [string]$targetGz, [string]$targetPatch, [string]$expectedHash) {
    if (-not (Test-Path $source)) { throw "Missing payload: $source" }
    $actual = (Get-FileHash $source -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $expectedHash) { throw "Payload checksum mismatch: $source => $actual" }
    $b64 = (Get-Content $source -Raw -Encoding ASCII).Trim()
    [IO.File]::WriteAllBytes($targetGz, [Convert]::FromBase64String($b64))
    $input = [IO.File]::OpenRead($targetGz)
    $output = [IO.File]::Create($targetPatch)
    try {
        $gz = [IO.Compression.GzipStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
        try { $gz.CopyTo($output) } finally { $gz.Dispose() }
    }
    finally {
        $output.Dispose()
        $input.Dispose()
    }
}

Write-Host '=== Reconstruct verified 1.0.6 source ==='
$chunkInfo = @(
    @{ Path='kuka-ci/parts/part-00.txt'; Hash='cbeb917a1b42f6706fd4ac934681c34527a6bec84de2035c27365eeee8dbaa2d' },
    @{ Path='kuka-ci/parts/part-01.txt'; Hash='7f4d5e46183e9104da87f2554b8dcb09b0a75c7a2a682d18d2a696e62441e2a2' },
    @{ Path='kuka-ci/parts/p2-0.txt'; Hash='00e17ff8a538c8e0040ef3d822c2fd344b0e4e7cbc7ce59c9fa186957206f430' },
    @{ Path='kuka-ci/parts/p2-1.txt'; Hash='a75345d829ee56f831a657e450b0187f8135a3d061a301d5ffcf0a1731dfac65' },
    @{ Path='kuka-ci/parts/p2-2.txt'; Hash='38db8298eda6e74ae240496fff63c8924831f8b90d089d965ec2cf3e7b80682f' },
    @{ Path='kuka-ci/parts/p2-3.txt'; Hash='65980abc047124ed16ed9dd80ec996d4763aec381a5ec0955458e2dd32ef16a6' },
    @{ Path='kuka-ci/parts/part-03.txt'; Hash='30cd50942f029f256276a182d71f922c46fb67d91f2ab4b3c0d81daf3b877c15' },
    @{ Path='kuka-ci/parts/part-04.txt'; Hash='40762de1bf88dbf7cf053f2331955c1fe38229cccfdb3723b487112e9b1d22f2' }
)
$parts = @()
foreach ($chunk in $chunkInfo) {
    if (-not (Test-Path $chunk.Path)) { throw "Missing $($chunk.Path)" }
    $actual = (Get-FileHash $chunk.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $chunk.Hash) { throw "Chunk checksum mismatch: $($chunk.Path)" }
    $parts += (Get-Content $chunk.Path -Raw -Encoding ASCII).Trim()
}
$b64 = ($parts -join '')
if ($b64.Length -ne 63168) { throw "Unexpected source base64 length: $($b64.Length)" }
[IO.File]::WriteAllText('source.b64', $b64, [Text.Encoding]::ASCII)
if ((Get-FileHash source.b64 -Algorithm SHA256).Hash.ToLowerInvariant() -ne '7e406b7bddabd6aa206cf151e3313af67e2d33baf1bc9cc25509c71f45cb5039') { throw 'Base64 checksum mismatch' }
[IO.File]::WriteAllBytes('source.tar.xz', [Convert]::FromBase64String($b64))
if ((Get-FileHash source.tar.xz -Algorithm SHA256).Hash.ToLowerInvariant() -ne '796cf89de00eb700817a0aa16e38b5c31955218ca857fd7b27f84bd1a4fae12d') { throw 'Archive checksum mismatch' }
tar -xf source.tar.xz
if ($LASTEXITCODE -ne 0) { throw "tar extraction failed: $LASTEXITCODE" }
if (-not (Test-Path 'src/KukaManager/KukaManager.csproj')) { throw 'Project not extracted' }

$testPath = 'tests/KukaManager.SmokeTests/Program.cs'
$test = Get-Content $testPath -Raw -Encoding UTF8
if ($test -notmatch '(?m)^using System\.IO;') {
    [IO.File]::WriteAllText($testPath, "using System.IO;`r`n" + $test, [Text.UTF8Encoding]::new($false))
}

Write-Host '=== Apply 1.1.0 UI foundation ==='
Expand-GzipBase64Patch 'kuka-ui/patch.gz.b64' 'kuka-ui-110.patch.gz' 'kuka-ui-110.patch' 'a14ad60f0d3ae54af10cca88dcfa7a568e9927a5263c67be912f420d38abf07e'
git apply --check --binary --exclude=src/KukaManager/KukaManager.csproj kuka-ui-110.patch
if ($LASTEXITCODE -ne 0) { throw '1.1.0 patch check failed' }
git apply --binary --exclude=src/KukaManager/KukaManager.csproj kuka-ui-110.patch
if ($LASTEXITCODE -ne 0) { throw '1.1.0 patch apply failed' }

Write-Host '=== Apply 1.1.1 runtime XAML correction ==='
Expand-GzipBase64Patch 'kuka-ui/fix-111.patch.gz.b64' 'kuka-ui-111.patch.gz' 'kuka-ui-111.patch' '2c7036849ba76d453a4976ec9a2adc23ff4b461bc56a89119b066663b6b03665'
git apply --check --binary --exclude=src/KukaManager/KukaManager.csproj kuka-ui-111.patch
if ($LASTEXITCODE -ne 0) { throw '1.1.1 patch check failed' }
git apply --binary --exclude=src/KukaManager/KukaManager.csproj kuka-ui-111.patch
if ($LASTEXITCODE -ne 0) { throw '1.1.1 patch apply failed' }

Write-Host '=== Apply 1.2.0 typography, DPI and alignment overhaul ==='
Expand-GzipBase64Patch 'kuka-ui/ui-120.patch.gz.b64' 'kuka-ui-120.patch.gz' 'kuka-ui-120.patch' '53becf01bbb09769ae0d6c9a4c362f16b9f3818754995dc03f63f713e95d955b'
git apply --check --binary --exclude=src/KukaManager/KukaManager.csproj kuka-ui-120.patch
if ($LASTEXITCODE -ne 0) { throw '1.2.0 patch check failed' }
git apply --binary --exclude=src/KukaManager/KukaManager.csproj kuka-ui-120.patch
if ($LASTEXITCODE -ne 0) { throw '1.2.0 patch apply failed' }

$projectPath = 'src/KukaManager/KukaManager.csproj'
$project = Get-Content $projectPath -Raw -Encoding UTF8
$project = [Regex]::Replace($project, '<Version>[^<]+</Version>', '<Version>1.2.0</Version>', 1)
if ($project -notmatch '<ApplicationManifest>app\.manifest</ApplicationManifest>') {
    $closing = $project.IndexOf('</PropertyGroup>', [StringComparison]::Ordinal)
    if ($closing -lt 0) { throw 'PropertyGroup closing tag missing in csproj' }
    $project = $project.Insert($closing, "    <ApplicationManifest>app.manifest</ApplicationManifest>`r`n  ")
}
[IO.File]::WriteAllText($projectPath, $project, [Text.UTF8Encoding]::new($false))

Copy-Item 'kuka-ui/app-120.manifest' 'src/KukaManager/app.manifest' -Force
& 'kuka-ui/augment-120-tests.ps1'
if ($LASTEXITCODE -ne 0) { throw '1.2.0 smoke augmentation failed' }

$theme = Get-Content 'src/KukaManager/Design/Theme.cs' -Raw -Encoding UTF8
if ($theme -notmatch 'Segoe UI Variable Text') { throw 'Segoe UI Variable typography missing' }
if ($theme -notmatch 'Microsoft YaHei UI') { throw 'Chinese UI fallback font missing' }
if ($theme -notmatch 'TextFormattingMode') { throw 'Crisp text rendering settings missing' }
$manifest = Get-Content 'src/KukaManager/app.manifest' -Raw -Encoding UTF8
if ($manifest -notmatch 'PerMonitorV2') { throw 'PerMonitorV2 manifest missing' }
$appPaths = Get-Content 'src/KukaManager/Utils/AppPaths.cs' -Raw -Encoding UTF8
if ($appPaths -notmatch '1\.2\.0') { throw 'App version did not update to 1.2.0' }
$project = Get-Content $projectPath -Raw -Encoding UTF8
if ($project -notmatch '<Version>1\.2\.0</Version>') { throw 'Project version did not update to 1.2.0' }
if ($project -notmatch '<ApplicationManifest>app\.manifest</ApplicationManifest>') { throw 'Application manifest project setting missing' }

Write-Host '=== Restore and compile ==='
dotnet restore .\src\KukaManager\KukaManager.csproj --source https://api.nuget.org/v3/index.json
if ($LASTEXITCODE -ne 0) { throw 'Main restore failed' }
dotnet build .\src\KukaManager\KukaManager.csproj -c Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Main build failed' }
dotnet restore .\tests\KukaManager.SmokeTests\KukaManager.SmokeTests.csproj --source https://api.nuget.org/v3/index.json
if ($LASTEXITCODE -ne 0) { throw 'Test restore failed' }
dotnet build .\tests\KukaManager.SmokeTests\KukaManager.SmokeTests.csproj -c Release --no-restore
if ($LASTEXITCODE -ne 0) { throw 'Test build failed' }
dotnet run --project .\tests\KukaManager.SmokeTests\KukaManager.SmokeTests.csproj -c Release --no-build
if ($LASTEXITCODE -ne 0) { throw 'Smoke tests failed' }

Write-Host '=== Publish self-contained win-x64 ==='
dotnet restore .\src\KukaManager\KukaManager.csproj -r win-x64 --source https://api.nuget.org/v3/index.json
if ($LASTEXITCODE -ne 0) { throw 'win-x64 restore failed' }
dotnet publish .\src\KukaManager\KukaManager.csproj -c Release -r win-x64 --self-contained true --no-restore -o .\dist\KukaManager
if ($LASTEXITCODE -ne 0) { throw 'Publish failed' }

$exe = Resolve-Path '.\dist\KukaManager\KukaManager.exe'
$size = (Get-Item $exe).Length
if ($size -lt 100000) { throw "Executable unexpectedly small: $size" }
Write-Host "Verified executable: $exe ($size bytes)"

Write-Host '=== Startup smoke test ==='
$p = Start-Process -FilePath $exe -PassThru
Start-Sleep -Seconds 5
if ($p.HasExited) { throw "KukaManager exited during startup with code $($p.ExitCode)" }
Stop-Process -Id $p.Id -Force
Write-Host 'KukaManager 1.2.0 stayed alive for 5 seconds.'

Write-Host '=== Package ==='
Compress-Archive -Path '.\dist\KukaManager\*' -DestinationPath '.\KukaManager-CSharp-1.2.0-win-x64.zip' -Force
if (-not (Test-Path '.\KukaManager-CSharp-1.2.0-win-x64.zip')) { throw 'Package was not created' }
Write-Host 'KUKA 1.2.0 VERIFIED BUILD COMPLETE'
