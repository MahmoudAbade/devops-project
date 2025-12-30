# PowerShell script to package Lambda function

Write-Host "Packaging Lambda function..." -ForegroundColor Green

# Create a temporary directory
$tempDir = "lambda_package"
if (Test-Path $tempDir) {
    Remove-Item -Recurse -Force $tempDir
}
New-Item -ItemType Directory -Path $tempDir | Out-Null

# Copy Lambda function
Copy-Item lambda_function.py -Destination $tempDir

# Create ZIP file
$zipPath = "lambda_function.zip"
if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

Compress-Archive -Path "$tempDir\*" -DestinationPath $zipPath

# Cleanup
Remove-Item -Recurse -Force $tempDir

Write-Host "Lambda function packaged successfully: $zipPath" -ForegroundColor Green
Write-Host "File size: $((Get-Item $zipPath).Length) bytes" -ForegroundColor Cyan
