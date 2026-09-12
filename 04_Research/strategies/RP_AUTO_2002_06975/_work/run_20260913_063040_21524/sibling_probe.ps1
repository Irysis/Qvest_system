$n = (Get-CimInstance Win32_Process -Filter "Name='python.exe'" | Where-Object { $_.CommandLine -like '*dnn_rolling*' } | Measure-Object).Count
Write-Output $n
