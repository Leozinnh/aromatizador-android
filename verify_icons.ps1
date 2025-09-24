# Script para verificar se os ícones não têm transparência
Add-Type -AssemblyName System.Drawing

function Test-ImageTransparency {
    param(
        [string]$ImagePath
    )
    
    try {
        $image = [System.Drawing.Image]::FromFile($ImagePath)
        $bitmap = New-Object System.Drawing.Bitmap($image)
        
        # Verificar se tem canal alpha
        $hasAlpha = $bitmap.PixelFormat -match "Alpha"
        
        # Para PNG, verificar alguns pixels para transparência
        $hasTransparentPixels = $false
        if ($bitmap.PixelFormat -match "32bpp") {
            # Verificar alguns pixels aleatórios
            for ($i = 0; $i -lt [Math]::Min(100, $bitmap.Width * $bitmap.Height); $i++) {
                $x = Get-Random -Maximum $bitmap.Width
                $y = Get-Random -Maximum $bitmap.Height
                $pixel = $bitmap.GetPixel($x, $y)
                if ($pixel.A -lt 255) {
                    $hasTransparentPixels = $true
                    break
                }
            }
        }
        
        $bitmap.Dispose()
        $image.Dispose()
        
        return @{
            HasAlpha = $hasAlpha
            HasTransparentPixels = $hasTransparentPixels
            PixelFormat = $bitmap.PixelFormat.ToString()
        }
    }
    catch {
        return @{
            Error = $_.Exception.Message
        }
    }
}

Write-Host "Verificando transparência nos ícones do iOS..." -ForegroundColor Yellow
Write-Host ""

$iconDir = "ios\Runner\Assets.xcassets\AppIcon.appiconset"
$iconFiles = Get-ChildItem -Path $iconDir -Filter "*.png" | Where-Object { $_.Name -notlike "*.backup" }

$problemIcons = @()

foreach ($iconFile in $iconFiles) {
    $result = Test-ImageTransparency -ImagePath $iconFile.FullName
    
    if ($result.Error) {
        Write-Host "ERRO - $($iconFile.Name): $($result.Error)" -ForegroundColor Red
        $problemIcons += $iconFile.Name
    }
    elseif ($result.HasTransparentPixels) {
        Write-Host "PROBLEMA - $($iconFile.Name): TEM TRANSPARENCIA" -ForegroundColor Red
        $problemIcons += $iconFile.Name
    }
    elseif ($result.HasAlpha) {
        Write-Host "AVISO - $($iconFile.Name): Canal Alpha detectado ($($result.PixelFormat))" -ForegroundColor Yellow
    }
    else {
        Write-Host "OK - $($iconFile.Name): ($($result.PixelFormat))" -ForegroundColor Green
    }
}

Write-Host ""
if ($problemIcons.Count -eq 0) {
    Write-Host "SUCESSO: Todos os icones parecem estar sem transparencia!" -ForegroundColor Green
    Write-Host "O problema do upload para App Store deve estar resolvido." -ForegroundColor Green
}
else {
    Write-Host "PROBLEMA: Ainda ha $($problemIcons.Count) icone(s) com transparencia:" -ForegroundColor Red
    $problemIcons | ForEach-Object { Write-Host "   - $_" -ForegroundColor Red }
}

# Verificar especificamente o ícone de 1024x1024 que foi mencionado no erro
$mainIcon = Join-Path $iconDir "Icon-App-1024x1024@1x.png"
if (Test-Path $mainIcon) {
    Write-Host ""
    Write-Host "Verificacao especial do icone principal (1024x1024):" -ForegroundColor Cyan
    $mainResult = Test-ImageTransparency -ImagePath $mainIcon
    if ($mainResult.Error) {
        Write-Host "ERRO: $($mainResult.Error)" -ForegroundColor Red
    }
    else {
        Write-Host "   Formato: $($mainResult.PixelFormat)" -ForegroundColor White
        Write-Host "   Canal Alpha: $($mainResult.HasAlpha)" -ForegroundColor White
        Write-Host "   Pixels transparentes: $($mainResult.HasTransparentPixels)" -ForegroundColor White
        
        if (-not $mainResult.HasTransparentPixels) {
            Write-Host "O icone principal esta OK para upload!" -ForegroundColor Green
        }
    }
}