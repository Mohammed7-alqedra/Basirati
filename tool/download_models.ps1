# Downloads the exact Android inference models into Flutter assets.
# Run once on the developer machine before flutter pub get / flutter build.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$destination = Join-Path $root "assets\models"
New-Item -ItemType Directory -Force -Path $destination | Out-Null

function Get-TfliteModel {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][long]$MinimumBytes
    )
    $target = Join-Path $destination $Name
    $temporary = "$target.partial"
    if (Test-Path $temporary) { Remove-Item -Force $temporary }

    $valid = $false
    if (Test-Path $target) {
        $size = (Get-Item $target).Length
        if ($size -ge $MinimumBytes) {
            $stream = [System.IO.File]::OpenRead($target)
            try {
                $bytes = New-Object byte[] 8
                $count = $stream.Read($bytes, 0, 8)
                $valid = ($count -eq 8 -and [System.Text.Encoding]::ASCII.GetString($bytes, 4, 4) -eq "TFL3")
            } finally { $stream.Dispose() }
        }
    }
    if ($valid) {
        Write-Host "Already present: $Name"
        return
    }
    Write-Host "Downloading $Name..."
    try {
        & curl.exe --location --fail --retry 3 --retry-delay 2 --show-error --output $temporary $Url
        if ($LASTEXITCODE -ne 0) { throw "curl.exe failed with exit code $LASTEXITCODE" }

        $size = (Get-Item $temporary).Length
        if ($size -lt $MinimumBytes) { throw "Model was too small ($size bytes): $Name" }
        $stream = [System.IO.File]::OpenRead($temporary)
        try {
            $header = New-Object byte[] 8
            $count = $stream.Read($header, 0, 8)
            if ($count -ne 8 -or [System.Text.Encoding]::ASCII.GetString($header, 4, 4) -ne "TFL3") {
                throw "This file is not a TFLite model: $Name"
            }
        } finally { $stream.Dispose() }
        Move-Item -Force $temporary $target
        Write-Host "Saved $Name ($size bytes)"
    } catch {
        if (Test-Path $temporary) { Remove-Item -Force $temporary }
        throw
    }
}

Get-TfliteModel `
    -Url "https://github.com/ultralytics/yolo-flutter-app/releases/download/v0.7.0/yolo26n_w8a32.tflite" `
    -Name "yolo26n_w8a32.tflite" `
    -MinimumBytes 2500000

Get-TfliteModel `
    -Url "https://huggingface.co/litert-community/Depth-Anything-V2-Metric-Hypersim-Small/resolve/main/Depth-Anything-V2-Metric-Hypersim-Small-fp32.tflite" `
    -Name "depth_anything_v2_metric_hypersim_small.tflite" `
    -MinimumBytes 90000000

Write-Host "Both models are ready. Build the Android APK with Flutter."
