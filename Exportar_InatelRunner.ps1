# Script de Exportação Completa - InatelRunner
# Este script automatiza o processo de exportação do Godot e garante que todas as dependências estejam inclusas.

$ProjectDir = Get-Location
$ExportDir = Join-Path $ProjectDir "builds\export_final"
$ExportExe = Join-Path $ExportDir "InatelRunner.exe"
$PresetName = "Windows" # Deve corresponder ao nome no export_presets.cfg

# 1. Tenta localizar o executável do Godot
$GodotPath = "godot" # Tenta no PATH primeiro
if (!(Get-Command $GodotPath -ErrorAction SilentlyContinue)) {
    # Procura em locais comuns se não estiver no PATH
    $CommonPaths = @(
	"C:\Godot_v4.5.1-stable_mono_win64\Godot_v4.5.1-stable_mono_win64.exe"
        "$env:USERPROFILE\Downloads\godot.exe"
    )
    foreach ($Path in $CommonPaths) {
        if (Test-Path $Path) {
            $GodotPath = $Path
            break
        }
    }
}

if (!(Get-Command $GodotPath -ErrorAction SilentlyContinue) -and !(Test-Path $GodotPath)) {
    Write-Error "Não foi possível encontrar o executável do Godot. Por favor, adicione o Godot ao seu PATH ou edite este script com o caminho correto."
    exit 1
}

Write-Host "--- Iniciando Exportação para $ExportDir ---" -ForegroundColor Cyan

# 2. Prepara a pasta de exportação
if (Test-Path $ExportDir) {
    Remove-Item -Recurse -Force $ExportDir
}
New-Item -ItemType Directory -Path $ExportDir | Out-Null

# 3. Executa a exportação do Godot
Write-Host "Exportando projeto..." -ForegroundColor Yellow
& $GodotPath --headless --export-release $PresetName $ExportExe

if ($LASTEXITCODE -ne 0) {
    Write-Error "Falha na exportação do Godot."
    exit $LASTEXITCODE
}

# 4. Copia dependências extras (DLLs nativas)
$DepDir = Join-Path $ProjectDir "export_dependencies"
if (Test-Path $DepDir) {
    Write-Host "Copiando dependências externas de $DepDir..." -ForegroundColor Yellow
    Copy-Item -Path "$DepDir\*" -Destination $ExportDir -Force
}

# 5. Verifica se o modelo ONNX está na raiz (caso não tenha sido embutido)
$OnnxModel = Join-Path $ProjectDir "yolo11n-pose.onnx"
if (Test-Path $OnnxModel) {
    Write-Host "Garantindo que o modelo ONNX está presente..." -ForegroundColor Yellow
    Copy-Item -Path $OnnxModel -Destination $ExportDir -Force
}

# 6. Cria um ZIP (Opcional)
$ZipFile = Join-Path $ProjectDir "InatelRunner_Exportado.zip"
if (Test-Path $ZipFile) { Remove-Item $ZipFile }
Write-Host "Criando pacote ZIP..." -ForegroundColor Yellow
Compress-Archive -Path "$ExportDir\*" -DestinationPath $ZipFile

Write-Host "--- Exportação Concluída com Sucesso! ---" -ForegroundColor Green
Write-Host "Local: $ExportDir"
Write-Host "Pacote: $ZipFile"
