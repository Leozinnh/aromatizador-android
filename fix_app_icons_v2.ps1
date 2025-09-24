# Script PowerShell melhorado para corrigir ícones do iOS
Add-Type -AssemblyName System.Drawing

function Remove-Transparency-Fixed {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [System.Drawing.Color]$BackgroundColor = [System.Drawing.Color]::White
    )
    
    Write-Host "Processando: $InputPath"
    
    try {
        # Carregar a imagem original
        $originalImage = [System.Drawing.Image]::FromFile($InputPath)
        
        # Criar nova imagem com fundo sólido
        $newImage = New-Object System.Drawing.Bitmap($originalImage.Width, $originalImage.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($newImage)
        
        # Preencher com cor de fundo
        $graphics.Clear($BackgroundColor)
        
        # Desenhar a imagem original sobre o fundo
        $graphics.DrawImage($originalImage, 0, 0)
        
        # Liberar recursos antes de salvar
        $graphics.Dispose()
        $originalImage.Dispose()
        
        # Salvar como PNG sem transparência
        $newImage.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $newImage.Dispose()
        
        Write-Host "Sucesso: $OutputPath"
        return $true
    }
    catch {
        Write-Host "Erro: $($_.Exception.Message)"
        return $false
    }
}

# Primeiro, vamos usar o ícone do diretório assets como base
$sourceIcon = "assets\icon.png"
$iconDir = "ios\Runner\Assets.xcassets\AppIcon.appiconset"

if (-not (Test-Path $sourceIcon)) {
    Write-Host "Erro: Arquivo $sourceIcon não encontrado!"
    exit 1
}

Write-Host "Usando $sourceIcon como ícone base..."

# Configurações de tamanhos para iOS
$iconSizes = @{
    "Icon-App-1024x1024@1x.png" = 1024
    "Icon-App-20x20@1x.png" = 20
    "Icon-App-20x20@2x.png" = 40
    "Icon-App-20x20@3x.png" = 60
    "Icon-App-29x29@1x.png" = 29
    "Icon-App-29x29@2x.png" = 58
    "Icon-App-29x29@3x.png" = 87
    "Icon-App-40x40@1x.png" = 40
    "Icon-App-40x40@2x.png" = 80
    "Icon-App-40x40@3x.png" = 120
    "Icon-App-50x50@1x.png" = 50
    "Icon-App-50x50@2x.png" = 100
    "Icon-App-57x57@1x.png" = 57
    "Icon-App-57x57@2x.png" = 114
    "Icon-App-60x60@2x.png" = 120
    "Icon-App-60x60@3x.png" = 180
    "Icon-App-72x72@1x.png" = 72
    "Icon-App-72x72@2x.png" = 144
    "Icon-App-76x76@1x.png" = 76
    "Icon-App-76x76@2x.png" = 152
    "Icon-App-83.5x83.5@2x.png" = 167
}

function Resize-Image {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [int]$NewSize
    )
    
    try {
        $originalImage = [System.Drawing.Image]::FromFile($InputPath)
        $newImage = New-Object System.Drawing.Bitmap($NewSize, $NewSize, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
        $graphics = [System.Drawing.Graphics]::FromImage($newImage)
        
        # Configurar qualidade alta para redimensionamento
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        
        # Fundo branco
        $graphics.Clear([System.Drawing.Color]::White)
        
        # Redimensionar e desenhar
        $graphics.DrawImage($originalImage, 0, 0, $NewSize, $NewSize)
        
        # Liberar recursos
        $graphics.Dispose()
        $originalImage.Dispose()
        
        # Salvar
        $newImage.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $newImage.Dispose()
        
        Write-Host "Criado: $OutputPath (${NewSize}x${NewSize})"
        return $true
    }
    catch {
        Write-Host "Erro ao criar $OutputPath : $($_.Exception.Message)"
        return $false
    }
}

Write-Host "Gerando novos ícones sem transparência..."

$successCount = 0
$totalCount = $iconSizes.Count

foreach ($iconFile in $iconSizes.GetEnumerator()) {
    $outputPath = Join-Path $iconDir $iconFile.Key
    $size = $iconFile.Value
    
    # Fazer backup se existir
    if (Test-Path $outputPath) {
        $backupPath = $outputPath + ".backup"
        Copy-Item -Path $outputPath -Destination $backupPath -Force
    }
    
    # Criar novo ícone redimensionado sem transparência
    if (Resize-Image -InputPath $sourceIcon -OutputPath $outputPath -NewSize $size) {
        $successCount++
    }
}

Write-Host ""
Write-Host "Processamento concluído!"
Write-Host "Sucessos: $successCount/$totalCount"
Write-Host "Os ícones agora não devem ter canal alpha/transparência."
Write-Host "Backups dos arquivos originais foram criados com extensão .backup"