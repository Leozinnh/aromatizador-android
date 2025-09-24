# Script PowerShell para remover transparência dos ícones do app iOS
Add-Type -AssemblyName System.Drawing

function Remove-Transparency {
    param(
        [string]$InputPath,
        [string]$OutputPath,
        [System.Drawing.Color]$BackgroundColor = [System.Drawing.Color]::White
    )
    
    Write-Host "Processando: $InputPath"
    
    # Carregar a imagem original
    $originalImage = [System.Drawing.Image]::FromFile($InputPath)
    
    # Criar nova imagem com fundo sólido
    $newImage = New-Object System.Drawing.Bitmap($originalImage.Width, $originalImage.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($newImage)
    
    # Preencher com cor de fundo
    $graphics.Clear($BackgroundColor)
    
    # Desenhar a imagem original sobre o fundo
    $graphics.DrawImage($originalImage, 0, 0)
    
    # Salvar como PNG sem transparência
    $newImage.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    
    # Limpar recursos
    $graphics.Dispose()
    $newImage.Dispose()
    $originalImage.Dispose()
    
    Write-Host "Salvo: $OutputPath"
}

# Diretório dos ícones do iOS
$iconDir = "ios\Runner\Assets.xcassets\AppIcon.appiconset"

# Lista de todos os arquivos PNG no diretório de ícones
$iconFiles = Get-ChildItem -Path $iconDir -Filter "*.png"

Write-Host "Removendo transparência dos ícones do iOS..."

foreach ($iconFile in $iconFiles) {
    $inputPath = $iconFile.FullName
    $backupPath = $inputPath + ".backup"
    
    # Fazer backup do arquivo original
    Copy-Item -Path $inputPath -Destination $backupPath -Force
    
    # Remover transparência (usar fundo branco)
    Remove-Transparency -InputPath $inputPath -OutputPath $inputPath -BackgroundColor ([System.Drawing.Color]::White)
}

Write-Host "Processamento concluído! Backups criados com extensão .backup"
Write-Host "Agora os ícones não devem ter transparência/canal alpha."