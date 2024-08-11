
$results = @()
try
{
    $results = Get-Service dot3svc
    if (($results.status -eq "Stopped")){
 
        Write-Host "Match"
        exit 1
    }
    else{
      
        Write-Host "No_Match"        
        exit 0
    }   
}
catch{
    $errMsg = $_.Exception.Message
    Write-Error $errMsg
    exit 1
}