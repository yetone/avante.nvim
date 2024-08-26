param (
    [string]$Version = "luajit"
)

$BuildDir = "build"
$BuildFromSource = $true

function Build-FromSource($feature) {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }

    $tempDir = Join-Path $BuildDir "lua-tiktoken-temp"
    git clone --branch v0.2.2 --depth 1 https://github.com/gptlang/lua-tiktoken.git $tempDir

    Push-Location $tempDir
    cargo build --features=$feature
    Pop-Location

    $targetFile = "tiktoken_core.dll"
    Copy-Item (Join-Path $tempDir "target\debug\tiktoken_core.dll") (Join-Path $BuildDir $targetFile)

    Remove-Item -Recurse -Force $tempDir
}

function Main {
    Write-Host "Building for $Version..."
    Build-FromSource $Version
}

# Run the main function
Main
