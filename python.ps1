# Resolution de l'interpreteur Python qui porte graphify.
#
# POURQUOI CE FICHIER EXISTE :
# graphify a ete installe depuis l'application Claude, dont le bac a sable
# virtualise %APPDATA%. Vu de l'interieur, l'outil est dans
#   C:\Users\<moi>\AppData\Roaming\uv\tools\graphifyy\
# vu d'un vrai terminal, il est en realite dans
#   C:\Users\<moi>\AppData\Local\Packages\Claude_*\LocalCache\Roaming\uv\tools\graphifyy\
# Un chemin en dur marche donc d'un cote et echoue de l'autre. On resout a
# l'execution, en verifiant que l'interpreteur importe bien ce qu'il faut.

function Get-PythonECU {
    param([string]$Requiert = 'networkx')

    $cands = New-Object System.Collections.Generic.List[string]

    # 1. ce que uv declare lui-meme
    $uv = $null
    $c = Get-Command uv -ErrorAction SilentlyContinue
    if ($c) { $uv = $c.Source }
    elseif (Test-Path "$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe") {
        $uv = "$env:LOCALAPPDATA\Microsoft\WinGet\Links\uv.exe"
    }
    if ($uv) {
        $d = (& $uv tool dir 2>$null)
        if ($d) { $cands.Add((Join-Path $d.Trim() 'graphifyy\Scripts\python.exe')) }
    }

    # 2. emplacements usuels
    $cands.Add("$env:APPDATA\uv\tools\graphifyy\Scripts\python.exe")
    $cands.Add("$env:LOCALAPPDATA\uv\tools\graphifyy\Scripts\python.exe")
    $cands.Add("$env:USERPROFILE\pipx\venvs\graphifyy\Scripts\python.exe")

    # 3. toute application empaquetee (le nom du paquet Claude peut changer)
    Get-ChildItem "$env:LOCALAPPDATA\Packages" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $p = Join-Path $_.FullName 'LocalCache\Roaming\uv\tools\graphifyy\Scripts\python.exe'
            if (Test-Path $p) { $cands.Add($p) }
        }

    foreach ($p in $cands) {
        if (-not $p -or -not (Test-Path $p)) { continue }
        & $p -c "import graphify, $Requiert" 2>$null
        if ($LASTEXITCODE -eq 0) { return $p }
    }

    # 4. dernier recours : un python du PATH
    foreach ($n in @('python', 'python3')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) {
            & $c.Source -c "import graphify, $Requiert" 2>$null
            if ($LASTEXITCODE -eq 0) { return $c.Source }
        }
    }
    return $null
}
