$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$destination = Join-Path $root 'inst\thermo'
[void][IO.Directory]::CreateDirectory($destination)
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:exe /platform:x64 /optimize+ /r:System.Web.Extensions.dll /r:System.Core.dll "/out:$destination\aidia-thermo-method.exe" (Join-Path $PSScriptRoot 'Aidia.ThermoMethod.cs')
if ($LASTEXITCODE -ne 0) { throw 'Thermo helper build failed.' }
Get-FileHash -LiteralPath (Join-Path $destination 'aidia-thermo-method.exe') -Algorithm SHA256
