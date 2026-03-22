Import-Module build.psm1
Import-Module tools/ci.psm1
Start-PSBootstrap -Scenario Dotnet
$releaseTag = Get-ReleaseTag
Start-PSBuild -Clean -PSModuleRestore -Runtime win7-x64 -Configuration Release
Start-PSPackage -ReleaseTag $releaseTag -Type msix -WindowsRuntime win7-x64
