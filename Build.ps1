param (
    [string]$Version = "luajit",
    [string]$BuildFromSource = "false"
)

$Build = [System.Convert]::ToBoolean($BuildFromSource)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$BuildDir = "build"

function Build-FromSource($feature) {
    if (-not (Test-Path $BuildDir)) {
        New-Item -ItemType Directory -Path $BuildDir | Out-Null
    }

    cargo build --release --features=$feature

    $SCRIPT_DIR = $PSScriptRoot
    $targetTokenizerFile = "avante_tokenizers.dll"
    $targetTemplatesFile = "avante_templates.dll"
    $targetRepoMapFile = "avante_repo_map.dll"
    Copy-Item (Join-Path $SCRIPT_DIR "target\release\avante_tokenizers.dll") (Join-Path $BuildDir $targetTokenizerFile)
    Copy-Item (Join-Path $SCRIPT_DIR "target\release\avante_templates.dll") (Join-Path $BuildDir $targetTemplatesFile)
    Copy-Item (Join-Path $SCRIPT_DIR "target\release\avante_repo_map.dll") (Join-Path $BuildDir $targetRepoMapFile)

    Remove-Item -Recurse -Force "target"
}

function Test-Command($cmdname) {
    return $null -ne (Get-Command $cmdname -ErrorAction SilentlyContinue)
}

function Test-GHAuth {
    try {
        $null = gh api user
        return $true
    } catch {
        return $false
    }
}

function Download-Prebuilt($feature) {
    $REPO_OWNER = "yetone"
    $REPO_NAME = "avante.nvim"

    $SCRIPT_DIR = $PSScriptRoot
    # Set the target directory to clone the artifact
    $TARGET_DIR = Join-Path $SCRIPT_DIR "build"

    # Set the platform to Windows
    $PLATFORM = "windows"
    $ARCH = "x86_64"
    if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
        $ARCH = "aarch64"
    }

    # Set the Lua version (lua51 or luajit)
    $LUA_VERSION = if ($feature) { $feature } else { "luajit" }

    # Set the artifact name pattern
    $ARTIFACT_NAME_PATTERN = "avante_lib-$PLATFORM-$ARCH-$LUA_VERSION"

    $TempFile = Get-Item ([System.IO.Path]::GetTempFilename()) | Rename-Item -NewName { $_.Name + ".zip" } -PassThru

    if ((Test-Command "gh") -and (Test-GHAuth)) {
        gh release download --repo "$REPO_OWNER/$REPO_NAME" --pattern "*$ARTIFACT_NAME_PATTERN*" --output $TempFile --clobber
    } else {
      # Get the artifact download URL
      $LATEST_RELEASE = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest"
      $ARTIFACT_URL = $LATEST_RELEASE.assets | Where-Object { $_.name -like "*$ARTIFACT_NAME_PATTERN*" } | Select-Object -ExpandProperty browser_download_url

      # Download and extract the artifact
      Invoke-WebRequest -Uri $ARTIFACT_URL -OutFile $TempFile
    }

    # Create target directory if it doesn't exist
    if (-not (Test-Path $TARGET_DIR)) {
        New-Item -ItemType Directory -Path $TARGET_DIR | Out-Null
    }
    Expand-Archive -Path $TempFile -DestinationPath $TARGET_DIR -Force
    Remove-Item $TempFile
}

function Main {
    Set-Location $PSScriptRoot
    if ($Build) {
        Write-Host "Building for $Version..."
        Build-FromSource $Version
    } else {
        $latestTag = git describe --tags --abbrev=0 2>&1 | Where-Object { $_ -ne $null }
        $builtTag = if (Test-Path "build/.tag") {
            Get-Content "build/.tag"
        } else {
            $null
        }

        function Save-Tag($tag) {
            $tag | Set-Content "build/.tag"
        }

        if ($latestTag -eq $builtTag -and $latestTag) {
            Write-Host "Local build is up to date. No download needed."
        } elseif ($latestTag -ne $builtTag -and $latestTag) {
            if (Test-Command "gh" -and Test-GHAuth) {
                gh release download $latestTag --repo "github.com/$REPO_OWNER/$REPO_NAME" --pattern "*$ARTIFACT_NAME_PATTERN*" --clobber --output - | tar -zxvf - -C $TARGET_DIR
                Save-Tag $latestTag
            } else {
                $ARTIFACT_URL = Invoke-RestMethod -Uri "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/tags/$latestTag" | Select-String -Pattern "browser_download_url" | ForEach-Object { $_.Matches.Groups[1].Value } | Where-Object { $_ -match $ARTIFACT_NAME_PATTERN }

                Invoke-WebRequest -Uri $ARTIFACT_URL -OutFile "$TempFile"
                Expand-Archive -Path "$TempFile" -DestinationPath "$TARGET_DIR" -Force
                Remove-Item "$TempFile"
                Save-Tag $latestTag
            }
        } else {
            cargo build --release --features=$Version
            Get-ChildItem -Path "target/release/avante_*.dll" | ForEach-Object {
                Copy-Item $_.FullName "build/$($_.Name)"
            }
        }
    }
    Write-Host "Completed!"
}

# Run the main function
Main
