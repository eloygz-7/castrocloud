# CastroCloud · Crea en Windows unha MV de VirtualBox lista para instalar Proxmox VE (nodo pve2).
#
# Uso (PowerShell, desde este cartafol):
#   powershell -ExecutionPolicy Bypass -File .\crear-nodo-proxmox.ps1 -Iso C:\ISOs\proxmox-ve_9.2-1.iso -Adaptador "Wi-Fi"
#
# -Adaptador: nome da tarxeta wifi (ou de cable) tal e como o mostra
#   & "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list bridgedifs   (liña "Name:")
#
# Valores pensados para un portátil con poucos recursos: 4 GB de RAM, sen
# virtualización aniñada (a demo usa contedores LXC, que non a precisan) e con
# caché de E/S do anfitrión no disco. Con 6 GB e virtualización aniñada, a
# instalación de Proxmox paraba cun «Guru Meditation» no 69 %.
# Se Windows ten Hyper-V ou a «integridade da memoria» activada, VirtualBox vai
# máis lento e menos estable: convén desactivalos (bcdedit /set hypervisorlaunchtype off).

param(
    [string]$Nome = "pve2",
    [int]$RamMB = 4096,
    [int]$Cpus = 2,
    [int]$DiscoGB = 32,
    # Segundo disco para o pool ZFS «datos» (replicación e alta dispoñibilidade); 0 = sen el
    [int]$DatosGB = 16,
    [Parameter(Mandatory = $true)][string]$Iso,
    [Parameter(Mandatory = $true)][string]$Adaptador
)

$ErrorActionPreference = "Stop"
$VBox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"

function Executar { & $VBox @args; if ($LASTEXITCODE -ne 0) { throw "Fallou: VBoxManage $args" } }

if (-not (Test-Path $VBox)) { throw "Non se atopa VBoxManage.exe (está instalado VirtualBox?)" }
if (-not (Test-Path $Iso)) { throw "Non se atopa a ISO: $Iso" }

# Compróbase coa lista de MV (showvminfo con redirección dá un código de saída falso en PowerShell 5.1)
if (& $VBox list vms | Select-String -SimpleMatch "`"$Nome`"") { throw "Xa existe unha MV chamada '$Nome'" }

$Ponte = (& $VBox list bridgedifs | Select-String "^Name:\s+(.+)$" | ForEach-Object { $_.Matches[0].Groups[1].Value.Trim() })
if ($Ponte -notcontains $Adaptador) {
    Write-Host "Adaptadores dispoñibles:"; $Ponte | ForEach-Object { Write-Host "  $_" }
    throw "O adaptador '$Adaptador' non existe"
}

# Suma SHA-256 publicada por Proxmox para proxmox-ve_9.2-1.iso
$SumaEsperada = "4e88fe416df9b527624a175f24c9aa07c714d3332afb1ee3dbf3879573ef2c6c"
if ((Split-Path $Iso -Leaf) -eq "proxmox-ve_9.2-1.iso") {
    Write-Host "==> Comprobando a suma SHA-256 da ISO"
    $Suma = (Get-FileHash -Algorithm SHA256 $Iso).Hash.ToLower()
    if ($Suma -ne $SumaEsperada) { throw "A suma da ISO non coincide: volve descargala" }
}

$Cartafol = (& $VBox list systemproperties | Select-String "^Default machine folder:\s+(.+)$").Matches[0].Groups[1].Value.Trim()
$Disco = Join-Path $Cartafol "$Nome\$Nome.vdi"

Write-Host "==> Creando a MV $Nome ($RamMB MB de RAM, $Cpus CPU, $DiscoGB GB de disco, ponte en $Adaptador)"
Executar createvm --name $Nome --ostype Debian_64 --groups /CastroCloud --register
Executar modifyvm $Nome --memory $RamMB --cpus $Cpus --ioapic on `
    --firmware bios --rtc-use-utc on --graphicscontroller vmsvga --vram 32 `
    --nic1 bridged --bridge-adapter1 $Adaptador --nictype1 82540EM --nic-promisc1 allow-all `
    --boot1 disk --boot2 dvd --boot3 none --boot4 none --nested-hw-virt off

Executar storagectl $Nome --name SATA --add sata --controller IntelAhci --portcount 3 --hostiocache on
Executar createmedium disk --filename $Disco --size ($DiscoGB * 1024) --format VDI
Executar storageattach $Nome --storagectl SATA --port 0 --device 0 --type hdd --medium $Disco
Executar storageattach $Nome --storagectl SATA --port 1 --device 0 --type dvddrive --medium $Iso

# Disco de datos para ZFS: dentro do nodo verase como /dev/sdb
if ($DatosGB -gt 0) {
    $DiscoDatos = Join-Path $Cartafol "$Nome\$Nome-zfs.vdi"
    Write-Host "==> Engadindo un disco de datos de $DatosGB GB para ZFS"
    Executar createmedium disk --filename $DiscoDatos --size ($DatosGB * 1024) --format VDI
    Executar storageattach $Nome --storagectl SATA --port 2 --device 0 --type hdd --medium $DiscoDatos
}

Write-Host "==> Feito. Arrancar desde a xanela de VirtualBox ou con:"
Write-Host "    & `"$VBox`" startvm $Nome"
