#requires -Version 7.0
<#
.SYNOPSIS
Install a local source package with Windows R in a verified UTF-8 environment.
.EXAMPLE
./tools/install-r-windows.ps1 -PackagePath E:/Rpackage/RegR -Library C:/Users/ouyan/AppData/Local/R/win-library/4.4
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackagePath,

    [Parameter(Mandatory)]
    [string]$Library,

    [string]$RHome = 'D:/software/R/R-4.4.3'
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) {
    throw 'This installer is for Windows R only. Use the existing WSL workflow on Linux.'
}

$PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$Library = (Resolve-Path -LiteralPath $Library).Path
if (-not (Test-Path -LiteralPath (Join-Path $PackagePath 'DESCRIPTION') -PathType Leaf)) {
    throw 'PackagePath must be a source package directory containing DESCRIPTION.'
}
if (-not (Test-Path -LiteralPath $Library -PathType Container)) {
    throw 'Library must be an existing Windows R library directory.'
}
$rExe = Join-Path $RHome 'bin/x64/R.exe'
$rscriptExe = Join-Path $RHome 'bin/x64/Rscript.exe'
foreach ($exe in @($rExe, $rscriptExe)) {
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        throw "Windows R executable not found: $exe"
    }
}

function Invoke-WindowsR {
    param([string]$Executable, [string[]]$Arguments)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    # Codex injects C.UTF-8, which Windows R cannot use. Change only this child.
    $localeKeys = @($startInfo.Environment.Keys | Where-Object { $_ -eq 'LANG' -or $_ -like 'LC_*' })
    foreach ($key in $localeKeys) {
        [void]$startInfo.Environment.Remove($key)
    }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        [Console]::Out.Write($stdout.GetAwaiter().GetResult())
        [Console]::Error.Write($stderr.GetAwaiter().GetResult())
        if ($process.ExitCode -ne 0) {
            throw "Windows R command failed with exit code $($process.ExitCode): $Executable"
        }
    }
    finally {
        $process.Dispose()
    }
}

$probeFile = [System.IO.Path]::GetTempFileName()
$verifyFile = [System.IO.Path]::GetTempFileName()
try {
    @'
if (.Platform[["OS.type"]] != "windows" || !isTRUE(l10n_info()[["UTF-8"]])) {
    stop("Windows R must start in UTF-8; actual LC_CTYPE: ", Sys.getlocale("LC_CTYPE"))
}
cat("Windows R UTF-8 preflight: ", Sys.getlocale("LC_CTYPE"), "\n", sep = "")
'@ | Set-Content -LiteralPath $probeFile -Encoding utf8NoBOM

    @'
args <- commandArgs(TRUE)
stopifnot(.Platform[["OS.type"]] == "windows", isTRUE(l10n_info()[["UTF-8"]]))
pkg <- unname(read.dcf(file.path(args[[1L]], "DESCRIPTION"))[1L, "Package"])
ns <- loadNamespace(pkg, lib.loc = args[[2L]])
expected <- normalizePath(file.path(args[[2L]], pkg), winslash = "/", mustWork = TRUE)
actual <- normalizePath(getNamespaceInfo(ns, "path"), winslash = "/", mustWork = TRUE)
stopifnot(identical(actual, expected))
# library() alone may leave the problematic functions as unevaluated promises.
exports <- getNamespaceExports(ns)
for (name in exports) invisible(getExportedValue(pkg, name))
stopifnot(isTRUE(l10n_info()[["UTF-8"]]))
cat("Verified ", pkg, " ", as.character(getNamespaceVersion(ns)),
    ": UTF-8; ", length(exports), " exports loaded; ", actual, "\n", sep = "")
'@ | Set-Content -LiteralPath $verifyFile -Encoding utf8NoBOM

    Invoke-WindowsR $rscriptExe @('--vanilla', $probeFile)
    Invoke-WindowsR $rExe @('CMD', 'INSTALL', '--no-multiarch', '-l', $Library, $PackagePath)
    Invoke-WindowsR $rscriptExe @('--vanilla', $verifyFile, $PackagePath, $Library)
}
finally {
    Remove-Item -LiteralPath $probeFile, $verifyFile -ErrorAction SilentlyContinue
}
