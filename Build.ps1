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

    $targetTokenizerFile = "avante_tokenizers.dll"
    $targetTemplatesFile = "avante_templates.dll"
    Copy-Item (Join-Path "target\release\libavante_tokenizers.dll") (Join-Path $BuildDir $targetTokenizerFile)
    Copy-Item (Join-Path "target\release\libavante_templates.dll") (Join-Path $BuildDir $targetTemplatesFile)

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
