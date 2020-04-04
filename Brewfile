# Install macOS dependecies with 'brew bundle' (requires Homebrew)
# https://github.com/Homebrew/homebrew-bundle

tap "microsoft/azdata-cli-release"
tap "microsoft/mssql-release", "https://github.com/Microsoft/homebrew-mssql-release"

# Scripting
brew "azure-cli"
brew "jq"
cask "powershell"

# SQL Server
brew "msodbcsql"
brew "mssql-tools"

# Visual Studio Code
cask "visual-studio-code"

# Terraform
brew "terraform" 
brew "tfenv" 

# Required for Azure Functions with PowerShell Core
cask "dotnet-sdk"
tap "azure/functions"
brew "azure-functions-core-tools"

# .NET Core
tap "isen-ng/dotnet-sdk-versions"
cask "dotnet-sdk-2.2.400"