Write-Host ""
Write-Host "STATUS CHECK"
Write-Host ""

Write-Host "Nombre del equipo: "
Write-Host $env:COMPUTERNAME
Write-Host ""

Write-Host "Direccion IP: "
Get-NetIPAddress -AddressFamily IPv4 |
Where-Object {$_.InterfaceAlias -like "*Ethernet*"} |
ForEach-Object { $_.IPAddress }
Write-Host ""

Write-Host "Espacio en disco: "
Get-PSDrive C

Write-Host ""