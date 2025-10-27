@echo off
%windir%\System32\more +8 "%~f0" > "%temp%\%~n0.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%temp%\%~n0.ps1" %*
del %temp%\%~n0.ps1
pause
exit /b

::PowerShell script  nach zeile 8
$state = [ordered]@{
    KonnektorIp     = $null
    TiReachable     = $false
    ConnectorValid  = $false
    ShouldFixRoutes = $false
    ManagedTI       = $null
    DNSlookup       = $null
}

function ask_user ($text){
    while($true){
        $answer = (read-host "$text (y/n)").ToLower()
        if($answer -eq "y" -or $answer -eq "yes"){
            return $true
        }
        elseif ($answer -eq "n" -or $answer -eq "no") {
            return $false
        }
        else {
            write-host "ja: (y/yes), nein: (n/no)"
        }
    }
}
function read-kocoip{
    do{
        $ip = Read-Host "Bitte Konnektorip angeben"
    }until ([System.Net.IPAddress]::TryParse($ip, [ref]$null))
    return $ip
}
function set_erzptroutes($kocoip){
    write-host "[debug]use $kocoip"
    route delete 100.102.0.0  >$null
    route delete 100.103.0.0 >$null
    route delete 100.102.128.0 >$null
    route delete 188.144.0.0 >$null
    route add 100.103.0.0 MASK 255.255.0.0 $kocoip METRIC 99 -p  >$null
    route add 100.102.0.0 MASK 255.254.0.0 $kocoip METRIC 99 -p  >$null
    route add 188.144.0.0 mask 255.254.0.0 $kocoip METRIC 99 -p  >$null
    if ($LASTEXITCODE -ne 0) {
        throw "FAILED to add route (route.exe exit code: $LASTEXITCODE)"
    }
}
function check_connectorsds($kocoip){
    if(Test-Connection $kocoip -IPv4 -Count 1){
        Write-Host "Konnektorip im Netzwerk erreichbar" -ForegroundColor Green
    }
    else{
        Write-Host "Ping test Fehlgeschlagen!`n Ist der Konnektor eingeschaltet? - GGF IP Adresse auf dem Display prüfen ($kocoip)" -ForegroundColor Red
        return $false
    }
    # connector.sds
    $urlsds = "https://$kocoip/connector.sds"
    if(Invoke-WebRequest $urlsds -Method Head -TimeoutSec 3 -SkipCertificateCheck){0
        Write-Host "Konnektorip ist korrekt!" -ForegroundColor Green
        return $true
    }else{
        Write-Host "Die IP-Adresse ($kocoip) ist erreichbar, aber die Endpunke können nicht ermittelt werden. Ist die IP korrekt?" -ForegroundColor Yellow
        return $false
    }
}
function test-ticonnection{
    Write-Host "Starte TI-Verbindungscheck.." -ForegroundColor Cyan
    $idp_url = "https://idp.zentral.idp.splitdns.ti-dienste.de/.well-known/openid-configuration"
    $outfile = Join-Path $env:tmp "well-knownconfiguration"
    try {
        Invoke-WebRequest -Uri $idp_url -OutFile $outfile -ErrorAction Stop -TimeoutSec 5 > $null
        #if this test succed, everything is fine
        Write-Host "TI-Check erfolgreich" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "TI-Check fehlgeschlagen" -ForegroundColor Red
        return $false
    }
}
function test-dnslookup{
    try {
        Resolve-DnsName idp.zentral.idp.splitdns.ti-dienste.de -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "DNS lookup fehlgeschlagen!" -ForegroundColor Red
        return $false
    } 
}

# check well know configuration, if succes -> fine

$state.TiReachable = test-ticonnection
if($state.TiReachable){
    # exit early, everything fine
    exit 0
}

Write-Host "Führe weitere checks aus.." -ForegroundColor Cyan
Write-Host "Prüfe Konnektorverbidnung" -ForegroundColor Cyan
# check konnektor
$potentialkonnektorip = (Get-NetRoute "100.102.*").NextHop | Select-Object -Unique
if($potentialkonnektorip.count -ne 1 -or $potentialkonnektorip -eq "0.0.0.0"){
    Write-Host "Konnte Konnektorip nicht finden" -ForegroundColor Yellow
    $state.konnektorip = read-kocoip
    Write-Host "Es wird die IP-Adresse $($state.konnektorip) benutzt."

}else{
    Write-Host "Konnektorip gefunden: $potentialkonnektorip" -ForegroundColor Green
    if(check_connectorsds $potentialkonnektorip){
        Write-Host "Die Konnektorendpunke sind erreichbar -> Konnektorip ist korrekt" -ForegroundColor Green
        $state.konnektorip = $potentialkonnektorip
    }
    elseif(ask_user "Ist die IP korrekt?"){
        write-host "Konnektorendpunkte konnten nicht abgerufen werden: ($potentialkonnektorip)" -ForegroundColor Red
        exit 1
    }
    else{
        $state.konnektorip = read-kocoip
    }
}
#check dns
Write-Host "Prüfe DNS lookup.."
$state.DNSlookup = test-dnslookup
# fix stuff 
if(-not (ask_user "Sollen die Routen neu gesetzt werden?")){write-host "ok Tschüss!",exit 0} # lol
$state.ShouldFixRoutes = $true
#route korregieren
if(ask_user "wird managed ti verwendet?"){
    $state.ManagedTI = $true
}
else{
    $state.ManagedTI = $false 
}

#dns
if(-not $state.DNSlookup){
    write-host "DNS Auflösung funktioniert nicht korrekt." -ForegroundColor Red
    Write-Host "Teste DNS Auflösung mit Konnektorip" -ForegroundColor Cyan
    try {
        Resolve-DnsName idp.zentral.idp.splitdns.ti-dien ste.de -Server $state.konnektorip -ErrorAction Stop >$null
        Write-Host "DNS-Auflösung funktioniert mit Konnektorip..." -ForegroundColor Yellow

    }
    catch {
        Write-Host "DNS-Auflösung schlägt weiterhin fehl.`n Bitte Technikertermin planen" -ForegroundColor Red
    }
    

}


if($state.ManagedTI){
    #managed ti case, this is kinda tricky
    #not implemented yes
    Write-Host "Bitte Techniker Termin vereinbaren" -ForegroundColor Yellow
    Write-Host "Weitere Informationen (bitte Screenshot im Ticket ablegen):"
    Get-NetRoute 100.1*
    ipconfig.exe

    exit 0
}
else{
    try {
        set_erzptroutes $state.konnektorip
        Write-Host "Routen wurden gesetzt!" -ForegroundColor Green
    }
    catch {
        Write-Host "Routen konnten nicht gesetzt werden! - bitte als Admin ausführen" -ForegroundColor Red
    }
    
}
exit 0