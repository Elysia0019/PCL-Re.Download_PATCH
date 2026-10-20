[CmdletBinding()]
param(
    [string]$TargetExe,
    [string]$OutputPath,
    [string]$SourceArchive,
    [switch]$Restore,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Management\Microsoft.PowerShell.Management.psd1') -ErrorAction Stop
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Utility\Microsoft.PowerShell.Utility.psd1') -ErrorAction Stop
$originalHash = '6b6e1260cb5a1d6a303855f1c60cab3d0bc1aebba7e40a964180188b271e7386'
$patchedHash = 'd4fe05b8c713c573fcd46e0efa1dc9b5463f5ec4fd03c3d9279d523e48f8d0bd'
$deltaHash = '6babd1946a33e433e187683ebbef6e0910e15144e18e8d97f274e15623bc06a7'
$releaseUrl = 'https://raw.githubusercontent.com/Meloong-Git/PCL/6b9a50df911c9d68b69b24c979efba477fb14b67/%E6%9C%80%E6%96%B0%E6%AD%A3%E5%BC%8F%E7%89%88.zip'

function Get-BytesHash([byte[]]$Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()}
    finally {$sha.Dispose()}
}

function Assert-NotRunning([string]$Path) {
    foreach ($process in (Get-Process -ErrorAction SilentlyContinue)) {
        try {$processPath = $process.Path} catch {continue}
        if ($processPath -and [string]::Equals($processPath, $Path, [StringComparison]::OrdinalIgnoreCase)) {
            throw '请先关闭目标 PCL，再应用补丁或恢复原版'
        }
    }
}

function Write-Atomic([string]$Path, [byte[]]$Bytes, [string]$ExpectedCurrentHash) {
    Assert-NotRunning $Path
    $directory = [IO.Path]::GetDirectoryName($Path)
    if (![IO.Directory]::Exists($directory)) {throw "输出目录不存在：$directory"}
    $tempPath = Join-Path $directory ('.pcl-patch-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $stream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {$stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true)} finally {$stream.Dispose()}
        if ([IO.File]::Exists($Path)) {
            if (!$ExpectedCurrentHash -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $ExpectedCurrentHash) {
                throw '运行期间目标文件发生变化，已停止操作，没有替换文件'
            }
            [IO.File]::Replace($tempPath, $Path, [NullString]::Value)
        } else {
            if ($ExpectedCurrentHash) {throw '运行期间目标文件被移除，已停止操作'}
            [IO.File]::Move($tempPath, $Path)
        }
    } finally {
        if ([IO.File]::Exists($tempPath)) {[IO.File]::Delete($tempPath)}
    }
}

function Get-OfficialBytes {
    Add-Type -AssemblyName System.IO.Compression
    $temporaryArchive = $null
    try {
        if ($SourceArchive) {
            $archivePath = (Resolve-Path -LiteralPath $SourceArchive).Path
        } else {
            $temporaryArchive = Join-Path ([IO.Path]::GetTempPath()) ('pcl-2.99-' + [Guid]::NewGuid().ToString('N') + '.zip')
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
            Write-Host '正在下载官方 PCL 2.99.0.0 原版...'
            Invoke-WebRequest -Uri $releaseUrl -OutFile $temporaryArchive -UseBasicParsing -TimeoutSec 90
            $archivePath = $temporaryArchive
        }
        $stream = [IO.File]::OpenRead($archivePath)
        try {
            $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
            try {
                $entry = $zip.GetEntry('Plain Craft Launcher 2.exe')
                if (!$entry -or $entry.Length -ne 5980160) {throw '压缩包内容与支持的官方版本不符'}
                $input = $entry.Open()
                $memory = [IO.MemoryStream]::new()
                try {$input.CopyTo($memory); return ,$memory.ToArray()} finally {$input.Dispose(); $memory.Dispose()}
            } finally {$zip.Dispose()}
        } finally {$stream.Dispose()}
    } finally {
        if ($temporaryArchive -and [IO.File]::Exists($temporaryArchive)) {[IO.File]::Delete($temporaryArchive)}
    }
}

try {
    if ($TargetExe) {
        $TargetExe = (Resolve-Path -LiteralPath $TargetExe).Path
        if ($OutputPath -and $Restore) {throw '恢复时只能指定 -TargetExe 或 -OutputPath 中的一项'}
        if (!$OutputPath) {$OutputPath = $TargetExe}
    } elseif (!$OutputPath) {
        $OutputPath = Join-Path $PSScriptRoot 'Plain Craft Launcher 2 - Download Restored.exe'
    }
    $OutputPath = [IO.Path]::GetFullPath($OutputPath)
    $backupPath = $OutputPath + '.pcl-original.bak'
    $currentHash = $null
    if ([IO.File]::Exists($OutputPath)) {$currentHash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()}

    if ($Restore) {
        if ($currentHash -eq $originalHash) {Write-Host '当前已是官方原版，无需恢复'; exit 0}
        if ($currentHash -ne $patchedHash) {throw '目标文件不是本补丁生成的版本，未执行恢复'}
        if (![IO.File]::Exists($backupPath)) {throw "找不到原版备份：$backupPath"}
        [byte[]]$original = [IO.File]::ReadAllBytes($backupPath)
        if ((Get-BytesHash $original) -ne $originalHash) {throw '原版备份的哈希不匹配，未执行恢复'}
        if ($CheckOnly) {
            Write-Host '校验通过 - 原版备份完整，未修改任何 EXE'
        } else {
            Write-Atomic $OutputPath $original $currentHash
            Write-Host "已恢复官方 PCL 2.99.0.0：$OutputPath"
        }
        exit 0
    }

    if ($currentHash -eq $patchedHash) {Write-Host "补丁已应用，无需重复操作：$OutputPath"; exit 0}
    if ($TargetExe) {
        [byte[]]$original = [IO.File]::ReadAllBytes($TargetExe)
    } else {
        [byte[]]$original = Get-OfficialBytes
    }
    if ((Get-BytesHash $original) -ne $originalHash) {
        throw '此补丁只支持已校验的官方 PCL 2.99.0.0，其他版本未修改'
    }
    if ($currentHash -and $currentHash -ne $originalHash) {throw '输出位置已有其他文件，未覆盖或修改'}

    $patchPath = Join-Path $PSScriptRoot 'download.patch.gz'
    if ((Get-FileHash -LiteralPath $patchPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $deltaHash) {throw '补丁数据的哈希不匹配，请重新获取补丁包'}
    $input = [IO.File]::OpenRead($patchPath)
    $gzip = [IO.Compression.GZipStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($gzip, [Text.Encoding]::UTF8)
    try {$patch = $reader.ReadToEnd() | ConvertFrom-Json} finally {$reader.Dispose(); $gzip.Dispose(); $input.Dispose()}
    if ($patch.format -ne 1 -or $patch.before -ne $originalHash -or $patch.after -ne $patchedHash -or $original.Length -ne $patch.beforeLength) {
        throw '补丁清单与当前版本不符，已停止操作'
    }
    $memory = [IO.MemoryStream]::new([int]$patch.afterLength)
    try {
        foreach ($operation in $patch.operations) {
            if ($operation.PSObject.Properties['copy']) {
                [int]$offset = $operation.copy[0]
                [int]$length = $operation.copy[1]
                if ($offset -lt 0 -or $length -lt 0 -or [long]$offset + $length -gt $original.Length) {throw '补丁数据的复制范围无效'}
                $memory.Write($original, $offset, $length)
            } elseif ($operation.PSObject.Properties['data']) {
                [byte[]]$data = [Convert]::FromBase64String($operation.data)
                $memory.Write($data, 0, $data.Length)
            } else {throw '补丁数据包含无效操作'}
            if ($memory.Length -gt $patch.afterLength) {throw '补丁输出大小超出预期'}
        }
        [byte[]]$output = $memory.ToArray()
    } finally {$memory.Dispose()}
    if ($output.Length -ne $patch.afterLength -or (Get-BytesHash $output) -ne $patchedHash) {throw '修补后的 EXE 校验失败，未写入目标文件'}
    if ($CheckOnly) {Write-Host '校验通过 - 原版、补丁和修补结果均匹配，未修改任何 EXE'; exit 0}

    if ([IO.File]::Exists($backupPath)) {
        if ((Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $originalHash) {throw '备份位置已有其他文件，未覆盖或修改'}
    } else {
        $backup = [IO.File]::Open($backupPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {$backup.Write($original, 0, $original.Length); $backup.Flush($true)} finally {$backup.Dispose()}
    }
    Write-Atomic $OutputPath $output $currentHash
    Write-Host "补丁已应用：$OutputPath"
    Write-Host "原版备份：$backupPath"
} catch {
    [Console]::Error.WriteLine('操作失败 - ' + $_.Exception.Message)
    exit 1
}
