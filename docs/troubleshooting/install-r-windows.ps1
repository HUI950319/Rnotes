#requires -Version 5.1
<#
.SYNOPSIS
Install a local source directory or tarball with Windows R in a verified UTF-8 environment.
Runs under Windows PowerShell 5.1 (built into Windows) and PowerShell 7.
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
if ($env:OS -ne 'Windows_NT') {
    throw 'This installer is for Windows R only. Use the existing WSL workflow on Linux.'
}

$PackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$Library = (Resolve-Path -LiteralPath $Library).Path
$isSourceDirectory = Test-Path -LiteralPath $PackagePath -PathType Container
if ($isSourceDirectory) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackagePath 'DESCRIPTION') -PathType Leaf)) {
        throw 'A source package directory must contain DESCRIPTION.'
    }
}
elseif (-not ((Test-Path -LiteralPath $PackagePath -PathType Leaf) -and $PackagePath.EndsWith('.tar.gz'))) {
    throw 'PackagePath must be a source package directory or a .tar.gz source archive.'
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

function ConvertTo-WindowsArgument {
    param([string]$Value)
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    # CommandLineToArgvW rules: double the backslashes before a quote and at the end.
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
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
    # ArgumentList exists only on .NET Core; build the quoted string for 5.1.
    $startInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-WindowsArgument $_ })) -join ' '
    # Codex injects C.UTF-8, which Windows R cannot use. Change only this child.
    $localeKeys = @($startInfo.EnvironmentVariables.Keys | Where-Object { $_ -eq 'LANG' -or $_ -like 'LC_*' })
    foreach ($key in $localeKeys) {
        $startInfo.EnvironmentVariables.Remove($key)
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
# Set-Content has no BOM-free UTF-8 option in Windows PowerShell 5.1.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
try {
    $probeCode = @'
if (.Platform[["OS.type"]] != "windows" || !isTRUE(l10n_info()[["UTF-8"]])) {
    stop("Windows R must start in UTF-8; actual LC_CTYPE: ", Sys.getlocale("LC_CTYPE"))
}
cat("Windows R UTF-8 preflight: ", Sys.getlocale("LC_CTYPE"), "\n", sep = "")
'@
    [System.IO.File]::WriteAllText($probeFile, $probeCode, $utf8NoBom)

    $verifyCode = @'
args <- commandArgs(TRUE)
stopifnot(.Platform[["OS.type"]] == "windows", isTRUE(l10n_info()[["UTF-8"]]))
read_source_description <- function(source) {
    if (dir.exists(source)) return(read.dcf(file.path(source, "DESCRIPTION")))
    entries <- utils::untar(source, list = TRUE)
    desc <- grep("^[A-Za-z][A-Za-z0-9.]+/DESCRIPTION$", entries, value = TRUE)
    if (length(desc) != 1L) stop("Source archive must contain one package DESCRIPTION")
    scratch <- tempfile("source-description-")
    dir.create(scratch)
    on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
    utils::untar(source, files = desc, exdir = scratch)
    read.dcf(file.path(scratch, desc))
}
source_desc <- read_source_description(args[[1L]])
pkg <- unname(source_desc[1L, "Package"])
ns <- loadNamespace(pkg, lib.loc = args[[2L]])
expected <- normalizePath(file.path(args[[2L]], pkg), winslash = "/", mustWork = TRUE)
actual <- normalizePath(getNamespaceInfo(ns, "path"), winslash = "/", mustWork = TRUE)
stopifnot(identical(actual, expected),
          identical(as.character(getNamespaceVersion(ns)), unname(source_desc[1L, "Version"])))
# library() alone may leave the problematic functions as unevaluated promises.
exports <- getNamespaceExports(ns)
for (name in exports) invisible(getExportedValue(pkg, name))
stopifnot(isTRUE(l10n_info()[["UTF-8"]]))
cat("Verified ", pkg, " ", as.character(getNamespaceVersion(ns)),
    ": UTF-8; ", length(exports), " exports loaded; ", actual, "\n", sep = "")
'@
    [System.IO.File]::WriteAllText($verifyFile, $verifyCode, $utf8NoBom)

    Invoke-WindowsR $rscriptExe @('--vanilla', $probeFile)
    Invoke-WindowsR $rExe @('CMD', 'INSTALL', '--no-multiarch', '-l', $Library, $PackagePath)
    Invoke-WindowsR $rscriptExe @('--vanilla', $verifyFile, $PackagePath, $Library)
}
finally {
    Remove-Item -LiteralPath $probeFile, $verifyFile -ErrorAction SilentlyContinue
}
