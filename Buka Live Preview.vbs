Set objShell = CreateObject("WScript.Shell")
strPath = "C:\Users\admin\OneDrive\Documents\Liquidity Flow Check List\live-preview-launcher.ps1"
objShell.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & strPath & """", 0, False
