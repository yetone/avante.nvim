param (
    [string]$Version = "luajit"
)

$BuildDir = "build"
$BuildFromSource = $true

function Build-FromSource($feature) {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }

    cargo build --release --features=$feature

    $targetFile = "libavante_tokenizers.dll"
    Copy-Item (Join-Path "target\release\libavante_tokenizers.dll") (Join-Path $BuildDir $targetFile)

    Remove-Item -Recurse -Force "target"
}

function Main {
    Set-Location $PSScriptRoot
    Write-Host "Building for $Version..."
    Build-FromSource $Version
    Write-Host "Completed!"
}

# Run the main function
Main
