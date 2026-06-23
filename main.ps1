param(
    [string]$ParamsPath
)

Add-Type -AssemblyName System.Drawing

$script:sizes = @(16, 32, 48, 64, 128, 256)

function ConvertTo-Ico {
    param([string]$ImagePath)

    $dir = Split-Path $ImagePath -Parent
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($ImagePath)
    $icoPath = Join-Path $dir "$baseName.ico"

    $bitmap = [System.Drawing.Bitmap]::new($ImagePath)
    $pngList = [System.Collections.Generic.List[byte[]]]::new()

    foreach ($size in $script:sizes) {
        $resized = [System.Drawing.Bitmap]::new($size, $size)
        $graphics = [System.Drawing.Graphics]::FromImage($resized)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($bitmap, 0, 0, $size, $size)
        $graphics.Dispose()

        $ms = [System.IO.MemoryStream]::new()
        $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
        $pngList.Add($ms.ToArray())
        $ms.Dispose()
        $resized.Dispose()
    }

    $bitmap.Dispose()

    $icoStream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($icoStream)

    $writer.Write([UInt16]0)
    $writer.Write([UInt16]1)
    $writer.Write([UInt16]$script:sizes.Count)

    $offset = 6 + $script:sizes.Count * 16
    for ($i = 0; $i -lt $script:sizes.Count; $i++) {
        $w = if ($script:sizes[$i] -eq 256) { 0 } else { $script:sizes[$i] }
        $h = if ($script:sizes[$i] -eq 256) { 0 } else { $script:sizes[$i] }
        $writer.Write([Byte]$w)
        $writer.Write([Byte]$h)
        $writer.Write([Byte]0)
        $writer.Write([Byte]0)
        $writer.Write([UInt16]1)
        $writer.Write([UInt16]32)
        $writer.Write([UInt32]$pngList[$i].Length)
        $writer.Write([UInt32]$offset)
        $offset += $pngList[$i].Length
    }

    foreach ($png in $pngList) {
        $writer.Write($png)
    }

    $writer.Flush()
    [System.IO.File]::WriteAllBytes($icoPath, $icoStream.ToArray())
    $writer.Dispose()
    $icoStream.Dispose()

    return $icoPath
}

function Show-Notification {
    param([string]$Title, [string]$Text, [string]$Type = "info")
    try {
        $duration = if ($Type -in @("warning", "error")) { 5000 } else { 3000 }
        $body = @{ message = "$Title`: $Text"; notify_type = $Type; duration = $duration } | ConvertTo-Json -Compress
        $wc = New-Object System.Net.WebClient
        $wc.Encoding = [System.Text.Encoding]::UTF8
        $wc.Headers.Add("Content-Type", "application/json")
        $wc.UploadString("http://127.0.0.1:9527/api/notify", "POST", $body) | Out-Null
    } catch {
        # 盒子未运行则静默忽略
    }
}

$paramsPath = $ParamsPath
if (-not $paramsPath -or -not (Test-Path $paramsPath)) {
    Show-Notification -Title "图片转ICO" -Text "未传入参数文件，请选中图片后通过右键菜单使用" -Type "warning"
    exit 0
}

$json = Get-Content -Path $paramsPath -Encoding UTF8 | ConvertFrom-Json
$paths = $json.data.target_paths

if (-not $paths -or $paths.Count -eq 0) {
    Show-Notification -Title "图片转ICO" -Text "未检测到文件路径，请选中图片后通过右键菜单使用" -Type "warning"
    exit 0
}

$imageExts = @(".jpg", ".jpeg", ".png", ".bmp", ".gif", ".tiff", ".tif", ".ico")
$results = @()
$success = 0
$fail = 0
$skipped = 0

foreach ($path in $paths) {
    $ext = [System.IO.Path]::GetExtension($path).ToLower()
    if ($ext -notin $imageExts) {
        $results += @{ input = $path; status = "skipped"; error = "不支持的图片格式: $ext" }
        $skipped++
        continue
    }
    try {
        $icoPath = ConvertTo-Ico -ImagePath $path
        $results += @{ input = $path; status = "ok"; output = $icoPath }
        $success++
    } catch {
        $results += @{ input = $path; status = "error"; error = $_.Exception.Message }
        $fail++
    }
}

if ($skipped -gt 0) {
    $extList = @()
    foreach ($r in $results) {
        if ($r.status -eq "skipped" -and $r.error -match "不支持的图片格式: (.+)") {
            $e = $matches[1] -replace '^\.'
            if ($e -and $e -notin $extList) { $extList += $e }
        }
    }
    Show-Notification -Title "图片转ICO" -Text "跳过了 $skipped 个不支持的格式: $($extList -join ', ')" -Type "warning"
}

$summary = @{
    total   = $paths.Count
    success = $success
    fail    = $fail
}

$output = @{ summary = $summary; details = $results }
$outputJson = $output | ConvertTo-Json -Depth 3 -Compress
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Write-Output $outputJson







