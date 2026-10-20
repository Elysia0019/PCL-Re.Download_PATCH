$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot/Mono.Cecil.dll"
$before = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("$PSScriptRoot/release/Plain Craft Launcher 2.exe")
$after = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("$PSScriptRoot/../PCL-Download-Restored.exe")
function Get-Types($roots) {
    foreach ($t in $roots) { $t; Get-Types $t.NestedTypes }
}
function Body-Text($method) {
    if (!$method.HasBody) { return '' }
    $instructions = @($method.Body.Instructions)
    $parts = foreach ($i in $instructions) {
        $o = $i.Operand
        if ($o -is [Mono.Cecil.Cil.Instruction]) { $o = 'jump:' + [array]::IndexOf($instructions, $o) }
        elseif ($o -is [Mono.Cecil.Cil.Instruction[]]) { $o = 'switch:' + (($o | ForEach-Object {[array]::IndexOf($instructions, $_)}) -join ',') }
        elseif ($o -is [Mono.Cecil.MemberReference]) { $o = $o.FullName }
        "$($i.OpCode.Name) $o"
    }
    return $parts -join "`n"
}
$oldMethods = @{}
foreach ($t in (Get-Types $before.MainModule.Types)) { foreach ($m in $t.Methods) {$oldMethods[$m.FullName] = $m} }
$changed = 0
foreach ($t in (Get-Types $after.MainModule.Types)) {
    foreach ($m in $t.Methods) {
        if (!$oldMethods.ContainsKey($m.FullName)) { Write-Output "ADDED $($m.FullName)"; continue }
        if ((Body-Text $m) -cne (Body-Text $oldMethods[$m.FullName])) {
            Write-Output "CHANGED $($m.FullName)"
            $changed++
        }
    }
}
if ($changed -ne 5) {throw "Unexpected changed method count: $changed"}
foreach ($r in $before.MainModule.Resources) {
    $s = $after.MainModule.Resources | Where-Object Name -eq $r.Name
    if ([Convert]::ToBase64String($r.GetResourceData()) -cne [Convert]::ToBase64String($s.GetResourceData())) {throw "Resource changed: $($r.Name)"}
}
Write-Output 'PASS - Exactly five original methods changed; embedded resources unchanged'

$depRoot = "$PSScriptRoot/release"
[AppDomain]::CurrentDomain.add_AssemblyResolve({
    param($sender, $eventArgs)
    $name = ([Reflection.AssemblyName]::new($eventArgs.Name)).Name
    $path = Join-Path $depRoot ($name + '.dll')
    if (Test-Path -LiteralPath $path) {
        try {return [Reflection.Assembly]::LoadFrom($path)} catch {[Console]::WriteLine($_.Exception.ToString());throw}
    }
    [Console]::WriteLine("MISSING - $name")
    return $null
}.GetNewClosure())
[Reflection.Assembly]::LoadFrom("$depRoot/MeloongCore.dll") | Out-Null
$assembly = [Reflection.Assembly]::LoadFrom((Resolve-Path "$PSScriptRoot/../PCL-Download-Restored.exe").Path)
$jobs = @{
    'PCL.ModModpack' = @('ModpackInstall')
    'PCL.PageDownloadInstall' = @('LoaderInit', '_Lambda$__R3-3')
    'PCL.PageDownloadModify' = @('LoadInstanceFinished')
    'PCL.PageDownloadResourceDetail' = @('InitializeStackResourceVersions')
}
foreach ($name in $jobs.Keys) {
    $type = $assembly.GetType($name, $true)
    foreach ($m in $type.GetMethods([Reflection.BindingFlags]'Public,NonPublic,Instance,Static,DeclaredOnly') | Where-Object {$_.Name -in $jobs[$name]}) {
        [Runtime.CompilerServices.RuntimeHelpers]::PrepareMethod($m.MethodHandle)
        Write-Output "JIT OK - $m"
    }
}
