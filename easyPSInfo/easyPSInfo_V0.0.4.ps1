#############################################
# Teil 1: Konfiguration, Logging und Utility-Funktionen
#############################################

# Benötigte Assemblies laden (für WPF und Windows Forms)
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

# Logging initialisieren
$script:logFolder = Join-Path -Path $PSScriptRoot -ChildPath "Logs"
$script:logFile = Join-Path -Path $script:logFolder -ChildPath "easySTARTUP_Setup.log"

if (-not (Test-Path -Path $script:logFolder)) {
    New-Item -Path $script:logFolder -ItemType Directory -Force | Out-Null
}

# Zentrale Logging-Funktion
function Write-Log {
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Type = "Info"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Type] $Message"
    Add-Content -Path $script:logFile -Value $logEntry -Encoding UTF8
    
    switch ($Type) {
        "Info"    { Write-Host $logEntry -ForegroundColor Gray }
        "Warning" { Write-Host $logEntry -ForegroundColor Yellow }
        "Error"   { Write-Host $logEntry -ForegroundColor Red }
        "Success" { Write-Host $logEntry -ForegroundColor Green }
    }
}

# Konsolidierte Funktion zur Aktualisierung der Log-Anzeige in der GUI
function Update-LogDisplay {
    param (
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Type = "Info"
    )
    Write-Log -Message $Message -Type $Type

    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] "
    switch ($Type) {
        "Info"    { $logEntry += "[INFO] " }
        "Warning" { $logEntry += "[WARNING] " }
        "Error"   { $logEntry += "[ERROR] " }
        "Success" { $logEntry += "[SUCCESS] " }
    }
    $logEntry += $Message

    if ($Global:txtLog) {
        $Global:txtLog.AppendText("$logEntry`n")
        $Global:txtLog.ScrollToEnd()
    }
}

# Definition der Module
$requiredModules = @(
    @{
        Name         = "ExchangeOnlineManagement"
        MinVersion   = "3.8.0"
        Description  = "Exchange Online Verwaltung"
        Webseite     = "https://www.powershellgallery.com/packages/ExchangeOnlineManagement/"
        Install      = "Install-Module -Name ExchangeOnlineManagement -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Graph"
        MinVersion   = "2.28.0"
        Description  = "Microsoft Graph API"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Graph/"
        Install      = "Install-Module -Name Microsoft.Graph -Scope CurrentUser"
    },
    @{
        Name         = "PowerShellGet"
        MinVersion   = "2.2.5"
        Description  = "PS Module Management"
        Webseite     = "https://www.powershellgallery.com/packages/PowerShellGet/"
        Install      = "Install-Module -Name PowerShellGet -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Graph.Beta"
        MinVersion   = "2.28.0"
        Description  = "Microsoft Graph Beta"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Graph.Beta/"
        Install      = "Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Entra"
        MinVersion   = "1.0.7"
        Description  = "Entra ID PowerShell"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Entra/"
        Install      = "Install-Module -Name Microsoft.Entra -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Entra.Beta"
        MinVersion   = "1.0.7"
        Description  = "Entra ID PowerShell (Beta)"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Entra.Beta/"
        Install      = "Install-Module -Name Microsoft.Entra.Beta -Scope CurrentUser"
    },
    @{
        Name         = "PnP.PowerShell"
        MinVersion   = "3.1.0"
        Description  = "SharePoint PnP"
        Webseite     = "https://www.powershellgallery.com/packages/PnP.PowerShell/"
        Install      = "Install-Module -Name PnP.PowerShell -Scope CurrentUser"
    },
    @{
        Name         = "AzureAD"
        MinVersion   = "2.0.2.182"
        Description  = "Azure AD (legacy)"
        Webseite     = "https://www.powershellgallery.com/packages/AzureAD/"
        Install      = "Install-Module -Name AzureAD -Scope CurrentUser"
    },
    @{
        Name         = "MSOnline"
        MinVersion   = "1.1.183.81"
        Description  = "Azure AD V1 (legacy)"
        Webseite     = "https://www.powershellgallery.com/packages/MSOnline/"
        Install      = "Install-Module -Name MSOnline -Scope CurrentUser"
    },
    @{
        Name         = "Microsoft.Online.SharePoint.PowerShell"
        MinVersion   = "16.0.26017.12000"
        Description  = "SharePoint Online"
        Webseite     = "https://www.powershellgallery.com/packages/Microsoft.Online.SharePoint.PowerShell/"
        Install      = "Install-Module -Name Microsoft.Online.SharePoint.PowerShell -Scope CurrentUser"
    }
)

# Funktion zur Prüfung, ob ein Modul installiert ist
function Test-ModuleInstalled {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $false)]
        [version]$MinVersion
    )
    $module = Get-Module -ListAvailable -Name $ModuleName
    if (-not $module) {
        return $false
    }
    if ($MinVersion) {
        $latestVersion = $module | Sort-Object Version -Descending | Select-Object -First 1
        if ($latestVersion.Version -lt $MinVersion) {
            return $false
        }
    }
    return $true
}

# Funktion zur Installation eines erforderlichen Moduls
function Install-RequiredModule {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $false)]
        [version]$MinVersion
    )
    try {
        if (-not (Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue)) {
            Write-Log "Installing NuGet Provider..." -Type "Info"
            Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
        }
        if ((Get-PSRepository -Name PSGallery).InstallationPolicy -ne "Trusted") {
            Write-Log "Setting PSGallery as trusted source..." -Type "Info"
            Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
        }
        $installParams = @{
            Name         = $ModuleName
            Force        = $true
            AllowClobber = $true
            Scope        = "CurrentUser"
            Repository   = "PSGallery"
        }
        if ($MinVersion) {
            $installParams.MinimumVersion = $MinVersion
            Write-Log "Installing $ModuleName (minimum version $MinVersion)..." -Type "Info"
        }
        else {
            Write-Log "Installing $ModuleName..." -Type "Info"
        }
        Install-Module @installParams -ErrorAction Stop
        Write-Log "Module $ModuleName successfully installed." -Type "Success"
        return $true
    }
    catch {
        Write-Log "Error installing $ModuleName - $($_.Exception.Message)" -Type "Error"
        return $false
    }
}

# Funktion zur Ermittlung von Moduldaten
function Get-ModuleData {
    $moduleData = @()
    foreach ($module in $requiredModules) {
        $moduleName    = $module.Name
        $minVersion    = $module.MinVersion
        $description   = $module.Description
        $webseite      = $module.Webseite
        $installCmd    = $module.Install

        $installed       = Test-ModuleInstalled -ModuleName $moduleName -MinVersion $minVersion
        $installedModule = Get-Module -ListAvailable -Name $moduleName | Sort-Object Version -Descending | Select-Object -First 1
        $installedVersion = if ($installedModule) { $installedModule.Version.ToString() } else { "Not installed" }
        
        $installEnabled = -not $installed
        
        $moduleData += [PSCustomObject]@{
            Name             = $moduleName
            Description      = $description
            MinVersion       = $minVersion
            InstalledVersion = $installedVersion
            InstallEnabled   = $installEnabled
            Webseite         = $webseite
            InstallCmd       = $installCmd
        }
    }
    return $moduleData
}

# Funktion zur Aktualisierung der Module
function Check-AllModules {
    Update-LogDisplay -Message "Checking modules..." -Type "Info"
    $moduleData = Get-ModuleData
    if ($Global:lvModules) {
        $Global:lvModules.ItemsSource = $moduleData
        Update-LogDisplay -Message "Modules loaded in ListView." -Type "Info"
    }
    else {
        Update-LogDisplay -Message "ListView element not found!" -Type "Error"
    }
}

# ExecutionPolicy-Funktionen
function Get-CurrentExecutionPolicies {
    $policies = Get-ExecutionPolicy -List | Select-Object Scope, ExecutionPolicy
    $policyData = @()
    
    $scopeDescriptions = @{
        "MachinePolicy" = "MachinePolicy (GPO - All users of this computer)"
        "UserPolicy"    = "UserPolicy (GPO - Current user)"
        "Process"       = "Process (Only for current PowerShell session)"
        "CurrentUser"   = "CurrentUser (Settings for current user)"
        "LocalMachine"  = "LocalMachine (Default for all users of this computer)"
    }
    
    foreach ($policy in $policies) {
        $scopeName = $policy.Scope.ToString()
        $canModify = $scopeName -notin @("MachinePolicy", "UserPolicy")
        
        $policyData += [PSCustomObject]@{
            Scope = $scopeName
            Description = $scopeDescriptions[$scopeName]
            CurrentPolicy = $policy.ExecutionPolicy.ToString()
            CanModify = $canModify
            PolicyOptions = @("Restricted", "AllSigned", "RemoteSigned", "Unrestricted", "Bypass", "Undefined")
        }
    }
    
    # Add effective policy
    try {
        $effectivePolicy = Get-ExecutionPolicy
        $policyData += [PSCustomObject]@{
            Scope = "Effective"
            Description = "Effective Policy (current session)"
            CurrentPolicy = $effectivePolicy.ToString()
            CanModify = $false
            PolicyOptions = @()
        }
    }
    catch {
        Update-LogDisplay -Message "Error getting effective policy: $($_.Exception.Message)" -Type "Warning"
    }
    
    return $policyData
}

function Update-ExecutionPolicyDisplay {
    $policyData = Get-CurrentExecutionPolicies
    if ($Global:lvExecutionPolicies) {
        $Global:lvExecutionPolicies.ItemsSource = $policyData
        Update-LogDisplay -Message "Execution policies updated." -Type "Info"
    }
}

function Set-ExecutionPolicyHandler {
    param($scope, $policy)
    
    # Check for admin rights if needed
    if ($scope -eq "LocalMachine") {
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            $result = [System.Windows.MessageBox]::Show(
                "Admin rights are required to modify LocalMachine scope. Restart as administrator?",
                "Admin Rights Required",
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)
            
            if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                try {
                    Start-Process PowerShell -Verb RunAs -ArgumentList ("-File `"{0}`"" -f $MyInvocation.MyCommand.Path)
                    $Global:window.Close()
                }
                catch {
                    Update-LogDisplay -Message "Error restarting as admin: $($_.Exception.Message)" -Type "Error"
                }
            }
            return
        }
    }
    
    try {
        Update-LogDisplay -Message "Setting ExecutionPolicy for scope '$scope' to '$policy'..." -Type "Info"
        Set-ExecutionPolicy -ExecutionPolicy $policy -Scope $scope -Force -ErrorAction Stop
        Update-LogDisplay -Message "ExecutionPolicy successfully set for scope '$scope'." -Type "Success"
        Update-ExecutionPolicyDisplay
    }
    catch {
        Update-LogDisplay -Message "Error setting ExecutionPolicy for scope '$scope': $($_.Exception.Message)" -Type "Error"
    }
}

# Funktion zum Öffnen von Web Links
function Open-WebLink {
    param($url)
    try {
        if (-not [string]::IsNullOrEmpty($url)) {
            Start-Process $url
            Update-LogDisplay -Message "Opening web link: $url" -Type "Info"
        } else {
            Update-LogDisplay -Message "No web link available for this module." -Type "Warning"
        }
    }
    catch {
        Update-LogDisplay -Message "Error opening web link: $($_.Exception.Message)" -Type "Error"
    }
}

function Install-ModuleHandler {
    param($buttonSender, $e)
    $button = [System.Windows.Controls.Button]$buttonSender
    $moduleName = $button.Tag.ToString()
    
    $moduleInfo = $requiredModules | Where-Object { $_.Name -eq $moduleName } | Select-Object -First 1
    
    if ($moduleInfo) {
        Update-LogDisplay -Message "Starting installation of $moduleName..." -Type "Info"
        $button.IsEnabled = $false
        $button.Content = "Installing..."
        
        $success = Install-RequiredModule -ModuleName $moduleName -MinVersion $moduleInfo.MinVersion
        
        if ($success) {
            Update-LogDisplay -Message "Module $moduleName successfully installed." -Type "Success"
        } else {
            Update-LogDisplay -Message "Error installing module $moduleName." -Type "Error"
        }
        
        Check-AllModules
    }
}

# XAML für die GUI (ohne Connect-Funktionen, mit ExecutionPolicy)
$xaml = @"
<Window 
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="easyIT | PowerShell Module &amp; Policy Manager - with Script Launcher" 
    Height="1000" 
    Width="1450"
    WindowStartupLocation="CenterScreen"
    Background="#FFFFFF"
    FontFamily="Segoe UI"
    FontSize="12">
    <Window.Resources>
        <!-- Modern Button Style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#0078D4" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="12,6" />
            <Setter Property="Margin" Value="4" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="MinWidth" Value="80" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#106EBE" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#005A9E" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SmallModernButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="FontSize" Value="10"/>
            <Setter Property="MinWidth" Value="60"/>
        </Style>

        <Style x:Key="ExitButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#D32F2F"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E57373" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#C62828" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.5" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="LinkButton" TargetType="Button" BasedOn="{StaticResource SmallModernButton}">
            <Setter Property="Background" Value="#E8F4FD"/>
            <Setter Property="Foreground" Value="#0078D4"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#D0E0F0" />
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#B0C0D0" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Card Style for GroupBox -->
        <Style x:Key="CardGroupBox" TargetType="GroupBox">
            <Setter Property="BorderBrush" Value="#E0E0E0" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Padding" Value="12,8,12,12" />
            <Setter Property="Margin" Value="0,0,0,10" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GroupBox">
                        <Border Background="White"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <Border Background="#F7F7F7" CornerRadius="8,8,0,0" Padding="10,6" BorderThickness="0,0,0,1" BorderBrush="#E0E0E0">
                                    <ContentPresenter ContentSource="Header"/>
                                </Border>
                                <ContentPresenter Grid.Row="1" Margin="{TemplateBinding Padding}"/>
                            </Grid>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Script Button Style -->
        <Style x:Key="ScriptButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="#F9F9F9" />
            <Setter Property="Foreground" Value="#333333" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="BorderBrush" Value="#E0E0E0"/>
            <Setter Property="Padding" Value="10,8"/>
            <Setter Property="Margin" Value="0,3"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="4">
                            <ContentPresenter Margin="{TemplateBinding Padding}" HorizontalAlignment="{TemplateBinding HorizontalContentAlignment}" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E3F2FD" />
                                <Setter TargetName="border" Property="BorderBrush" Value="#0078D4"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#BBDEFB" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Opacity" Value="0.6" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style x:Key="ScriptListHeaderBorderStyle" TargetType="Border">
            <Setter Property="Background" Value="#E3F2FD"/>
            <Setter Property="Margin" Value="0,10,0,5"/>
            <Setter Property="Padding" Value="8,4"/>
            <Setter Property="CornerRadius" Value="3"/>
        </Style>

    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <!-- Header -->
        <Border Grid.Row="0" Background="#FF1C323C" Padding="20,15">
            <StackPanel>
                <TextBlock Text="easyIT | PowerShell Module &amp; Policy Manager - with Script Launcher" FontSize="20" FontWeight="SemiBold" Foreground="#e2e2e2"/>
                <TextBlock Text="Manage PowerShell modules and execution policies | Launch scripts from subfolders" FontSize="12" Foreground="#d0e8ff" Margin="0,5,0,0"/>
            </StackPanel>
        </Border>
        <!-- Content with Split Layout -->
        <Grid Grid.Row="1" Margin="15">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="2.2*"/>
                <!-- Status area: slightly larger -->
                <ColumnDefinition Width="1*"/>
                <!-- Script selection: 1/3 -->
            </Grid.ColumnDefinitions>
            <!-- Left side - Status area -->
            <Grid Grid.Column="0" Margin="0,0,10,0">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <!-- Module Check Section -->
                <GroupBox Grid.Row="0" Header="PowerShell Modules" Style="{StaticResource CardGroupBox}">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="*"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <ListView Grid.Row="0" x:Name="lvModules" Margin="0,5,0,10" BorderThickness="1" BorderBrush="#E0E0E0" Height="260">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Module" Width="410">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <TextBlock Text="{Binding Name}" ToolTip="{Binding Description}" VerticalAlignment="Center"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Required" DisplayMemberBinding="{Binding MinVersion}" Width="100"/>
                                    <GridViewColumn Header="Installed" DisplayMemberBinding="{Binding InstalledVersion}" Width="100"/>
                                    <GridViewColumn Header="Action" Width="120">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <Button Content="Install/Update" 
                                                        Style="{StaticResource SmallModernButton}"
                                                        IsEnabled="{Binding InstallEnabled}"
                                                        Tag="{Binding Name}"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                    <GridViewColumn Header="Link" Width="90">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <Button Content="Web Link" 
                                                        Style="{StaticResource LinkButton}"
                                                        Tag="{Binding Webseite}"/>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <Button Grid.Row="1" x:Name="btnRefreshModules" Content="Refresh Modules" Style="{StaticResource ModernButton}" HorizontalAlignment="Left" Width="180" Height="25" Margin="0,5,0,0"/>
                    </Grid>
                </GroupBox>
                <!-- ExecutionPolicy Section -->
                <GroupBox Grid.Row="1" Header="PowerShell Execution Policies" Style="{StaticResource CardGroupBox}">
                    <Grid>
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto"/>
                            <RowDefinition Height="Auto"/>
                        </Grid.RowDefinitions>
                        <ListView Grid.Row="0" x:Name="lvExecutionPolicies" Margin="0,0,0,10" BorderThickness="1" BorderBrush="#E0E0E0" Height="165">
                            <ListView.View>
                                <GridView>
                                    <GridViewColumn Header="Scope" DisplayMemberBinding="{Binding Description}" Width="330"/>
                                    <GridViewColumn Header="Current Policy" DisplayMemberBinding="{Binding CurrentPolicy}" Width="150"/>
                                    <GridViewColumn Header="Modify" Width="400">
                                        <GridViewColumn.CellTemplate>
                                            <DataTemplate>
                                                <StackPanel Orientation="Horizontal">
                                                    <Button Content="Restricted" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="65"/>
                                                    <Button Content="AllSigned" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="65"/>
                                                    <Button Content="RemoteSigned" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="90"/>
                                                    <Button Content="Unrestricted" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="80"/>
                                                    <Button Content="Bypass" Style="{StaticResource SmallModernButton}" Margin="2,0" Tag="{Binding Scope}" Width="55"/>
                                                </StackPanel>
                                            </DataTemplate>
                                        </GridViewColumn.CellTemplate>
                                    </GridViewColumn>
                                </GridView>
                            </ListView.View>
                        </ListView>
                        <Button Grid.Row="1" x:Name="btnRefreshPolicies" Content="Refresh Execution Policies" Style="{StaticResource ModernButton}" HorizontalAlignment="Left" Width="200" Height="25"/>
                    </Grid>
                </GroupBox>
                <!-- Status Log -->
                <GroupBox Grid.Row="2" Header="Status and Log" Style="{StaticResource CardGroupBox}" Margin="0,10,0,0">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <TextBox x:Name="txtLog" IsReadOnly="True" TextWrapping="Wrap" 
                                 FontFamily="Consolas" FontSize="11" Background="#1E1E1E" Foreground="#A0D2A0" BorderThickness="0" Padding="5"/>
                    </ScrollViewer>
                </GroupBox>
            </Grid>
            <!-- Right side - Script selection -->
            <GroupBox Grid.Column="1" Header="Available PowerShell Scripts" Style="{StaticResource CardGroupBox}" Margin="10,0,0,0">
                <Grid>
                    <Grid.RowDefinitions>
                        <!-- Suchfeld (optional, hier nicht implementiert) -->
                        <!-- <RowDefinition Height="Auto"/> -->
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <!-- Script list -->
                    <ScrollViewer Grid.Row="0" VerticalScrollBarVisibility="Auto" Margin="0,0,0,10">
                        <StackPanel x:Name="spScriptList" Orientation="Vertical" Margin="0,3,0,3">
                            <!-- Script buttons will be added dynamically -->
                        </StackPanel>
                    </ScrollViewer>
                    <!-- Refresh button -->
                    <Button Grid.Row="1" x:Name="btnRefreshScripts" 
                            Content="Refresh Script List" Style="{StaticResource ModernButton}"
                            Height="32"/>
                </Grid>
            </GroupBox>
        </Grid>
        <!-- Footer with Buttons and Info -->
        <Border Grid.Row="2" Background="#FF1C323C" Padding="20,10">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Vertical" HorizontalAlignment="Left" VerticalAlignment="Center">
                    <TextBlock Text="PSscripts.de | Andreas Hepp  | easyPSinfo  -  Version: 0.0.3  -  Update: 23.05.2025" FontSize="10" Foreground="#d0e8ff"/>
                </StackPanel>

                <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Center">
                    <Button x:Name="btnExit" Content="Exit" Style="{StaticResource ExitButton}" Width="120" Height="32"/>
                </StackPanel>
            </Grid>
        </Border>
    </Grid>
</Window>
"@

#############################################
# Teil 2: GUI-Funktionen, Event-Handler und Main Block
#############################################

# Funktion zum Laden der XAML-GUI
function Import-XamlGui {
    try {
        if ([string]::IsNullOrEmpty($xaml)) {
            throw "XAML content is empty"
        }
        
        $xmlReaderSettings = New-Object System.Xml.XmlReaderSettings
        $xmlReaderSettings.IgnoreWhitespace = $true
        $xmlReaderSettings.IgnoreComments = $true
        $xmlReaderSettings.IgnoreProcessingInstructions = $true

        $reader = $null
        $stringReader = $null
        
        try {
            $stringReader = New-Object System.IO.StringReader($xaml)
            $reader = [System.Xml.XmlReader]::Create($stringReader, $xmlReaderSettings)
            
            $window = [System.Windows.Markup.XamlReader]::Load($reader)
            
            $regex = New-Object System.Text.RegularExpressions.Regex('x:Name="([^"]*)"')
            $matches = $regex.Matches($xaml)
            
            foreach ($match in $matches) {
                if ($match.Groups.Count -gt 1) {
                    $name = $match.Groups[1].Value
                    $element = $window.FindName($name)
                    
                    if ($null -ne $element) {
                        Set-Variable -Name $name -Value $element -Scope Global
                    }
                }
            }
            
            return $window
        }
        finally {
            if ($null -ne $reader) { $reader.Close() }
            if ($null -ne $stringReader) { $stringReader.Close() }
        }
    }
    catch {
        Write-Log "Error loading XAML: $($_.Exception.Message)" -Type "Error"
        throw
    }
}

# Funktion zur Aktualisierung der Skriptliste
function Update-ScriptList {
    try {
        Update-LogDisplay -Message "Loading available PowerShell scripts..." -Type "Info"
        
        $spScriptList = $Global:window.FindName("spScriptList")
        if ($null -eq $spScriptList) {
            Update-LogDisplay -Message "Script list element not found!" -Type "Error"
            return
        }
        
        $spScriptList.Children.Clear()
        
        $scriptFolders = @()
        # $initialBaseFolder wird als Referenz für die hierarchische Anzeige verwendet
        $initialBaseFolder = $PSScriptRoot
        if ([string]::IsNullOrEmpty($initialBaseFolder)) {
            Update-LogDisplay -Message "PSScriptRoot nicht verfügbar, versuche alternativen Pfad..." -Type "Warning"
            if ($MyInvocation.MyCommand.Path) {
                $initialBaseFolder = Split-Path -Parent $MyInvocation.MyCommand.Path
            }
            else {
                # Potenzielle Pfade, die dynamisch oder benutzerbezogen sind
                $potentialPaths = @(
                    Join-Path -Path $env:USERPROFILE -ChildPath "Documents\PowerShell\Scripts", # Standard-Benutzer-Skriptverzeichnis
                    (Get-Location).Path # Aktuelles Arbeitsverzeichnis
                )
                # Versuche, einen Standard-Modulpfad zu finden, falls vorhanden
                $defaultUserModulePath = Join-Path -Path $env:USERPROFILE -ChildPath "Documents\WindowsPowerShell\Modules"
                if (Test-Path -Path $defaultUserModulePath) {
                    $potentialPaths += $defaultUserModulePath
                }

                foreach ($path in $potentialPaths) {
                    if (Test-Path -Path $path -ErrorAction SilentlyContinue) {
                        $initialBaseFolder = $path
                        Update-LogDisplay -Message "Verwende gefundenen Pfad als Basis für die Skriptsuche: $initialBaseFolder" -Type "Info"
                        break
                    }
                }
            }
        }
        
        if ([string]::IsNullOrEmpty($initialBaseFolder)) {
            Update-LogDisplay -Message "No valid script directory base found." -Type "Error"
            return
        }
        
        # Ausschlussmuster für Ordnernamen (case-insensitive durch -like)
        $excludeFolderPatterns = @("*old*", "*#old*", "*# old*")

        if (Test-Path -Path $initialBaseFolder -ErrorAction SilentlyContinue) {
            $baseFolderLeafName = (Split-Path -Leaf $initialBaseFolder)
            $skipBaseFolderSearch = $false
            foreach ($pattern in $excludeFolderPatterns) {
                if ($baseFolderLeafName -like $pattern) {
                    $skipBaseFolderSearch = $true
                    Update-LogDisplay -Message "Base folder '$initialBaseFolder' is excluded from direct script search because its name matches pattern '$pattern'." -Type "Warning"
                    break
                }
            }

            if (-not $skipBaseFolderSearch) {
                Update-LogDisplay -Message "Adding base path for script search: $initialBaseFolder" -Type "Info"
                $scriptFolders += $initialBaseFolder 
            }
            # else: $initialBaseFolder is skipped for direct script search, but still acts as categorization root.

            # Alle Unterordner rekursiv hinzufügen, die nicht den Ausschlussmustern entsprechen
            try {
                # Hole ALLE Unterverzeichnisse zuerst
                $allSubDirectories = Get-ChildItem -Path $initialBaseFolder -Directory -Recurse -ErrorAction SilentlyContinue
                
                $validSubDirectories = @()
                $trimmedInitialBaseFolder = $initialBaseFolder.TrimEnd([System.IO.Path]::DirectorySeparatorChar)

                foreach ($dirInfoObject in $allSubDirectories) {
                    $currentDirFullName = $dirInfoObject.FullName
                    $isAnySegmentExcluded = $false
                    
                    $relativePathString = $null
                    if ($currentDirFullName.Length -gt $trimmedInitialBaseFolder.Length) {
                        if ($currentDirFullName.StartsWith($trimmedInitialBaseFolder + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
                            $relativePathString = $currentDirFullName.Substring($trimmedInitialBaseFolder.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                        } else {
                            # Nicht wirklich ein Unterpfad im Sinne der Hierarchie vom initialBaseFolder, überspringen
                            continue
                        }
                    } else {
                         # $currentDirFullName ist $initialBaseFolder selbst oder kürzer
                        continue
                    }
                    
                    if (-not ([string]::IsNullOrEmpty($relativePathString))) {
                        $pathSegments = $relativePathString.Split([System.IO.Path]::DirectorySeparatorChar)
                        foreach ($segment in $pathSegments) {
                            if ([string]::IsNullOrEmpty($segment)) { continue } 
                            foreach ($pattern in $excludeFolderPatterns) {
                                if ($segment -like $pattern) {
                                    $isAnySegmentExcluded = $true
                                    break # pattern loop
                                }
                            }
                            if ($isAnySegmentExcluded) { break } # segment loop
                        }
                    }

                    if (-not $isAnySegmentExcluded) {
                        $validSubDirectories += $currentDirFullName
                    }
                }
                
                $scriptFolders += $validSubDirectories
                
                if ($validSubDirectories.Count -gt 0) {
                    Update-LogDisplay -Message "Added $($validSubDirectories.Count) subfolders to script search (after filtering path segments)." -Type "Info"
                } else {
                     Update-LogDisplay -Message "No subfolders added to script search after path segment filtering." -Type "Info"
                }
            }
            catch {
                Update-LogDisplay -Message "Error processing subfolders from ${initialBaseFolder}: $($_.Exception.Message)" -Type "Warning"
            }
        }
        else {
            Update-LogDisplay -Message "Initial base folder for scripts $initialBaseFolder does not exist or is not accessible." -Type "Error"
            return 
        }
        
        if ($scriptFolders.Count -gt 0) {
            Update-LogDisplay -Message "Searching for scripts in $($scriptFolders.Count) locations." -Type "Info"
        } else {
            Update-LogDisplay -Message "No script folders to search (base folder might be excluded or contain no valid subfolders after exclusions)." -Type "Warning"
        }
        
        $scripts = @()
        foreach ($folder in $scriptFolders) { 
            if (-not [string]::IsNullOrEmpty($folder) -and (Test-Path -Path $folder -ErrorAction SilentlyContinue)) {
                try {
                    $currentScriptName = $null
                    if ($MyInvocation.MyCommand.Path) {
                        $currentScriptName = Split-Path -Leaf $MyInvocation.MyCommand.Path
                    }
                    # Get scripts only from the current $folder, not its subdirectories (Depth 0 implicitly)
                    $folderScripts = Get-ChildItem -Path $folder -Filter "*.ps1" -File -ErrorAction Stop | 
                                     Where-Object { $currentScriptName -eq $null -or $_.Name -ne $currentScriptName }
                    if ($folderScripts -and $folderScripts.Count -gt 0) {
                        $scripts += $folderScripts
                    }
                }
                catch {
                    Update-LogDisplay -Message "Error searching for scripts in $folder - $($_.Exception.Message)" -Type "Error"
                }
            }
        }
        
        if ($scripts.Count -eq 0) {
            Update-LogDisplay -Message "No PowerShell scripts found in any searched location (after applying exclusions)." -Type "Warning"
            $textBlock = New-Object System.Windows.Controls.TextBlock
            $textBlock.Text = "No scripts found."
            $textBlock.Margin = "9"
            $textBlock.Foreground = "Gray"
            $textBlock.FontStyle = "Italic"
            $spScriptList.Children.Add($textBlock)
            return
        }
        
        $categorizationBase = $initialBaseFolder 

        $scriptsByExactDirectory = $scripts | Group-Object -Property DirectoryName

        # Erstelle eine korrekte hierarchische Sortierung
        $sortedDirectoryGroups = $scriptsByExactDirectory | Sort-Object {
            $dirPath = $_.Name # Full path of the directory being grouped
            if ($dirPath -eq $categorizationBase) {
                "000000_ROOT" # Root folder always first
            } else {
                # Berechne den relativen Pfad für hierarchische Sortierung
                $relativePath = ""
                if ($dirPath.StartsWith($categorizationBase, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $relativePath = $dirPath.Substring($categorizationBase.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                } else {
                    $relativePath = $dirPath
                }
                
                # Ersetze Backslashes durch Forward-Slashes für konsistente Sortierung
                $normalizedPath = $relativePath.Replace('\', '/')
                
                # Teile den Pfad in Segmente und sortiere hierarchisch
                $segments = $normalizedPath -split '/' | Where-Object { $_ -ne '' }
                $depth = $segments.Count
                
                # Erstelle Sortier-Key: Tiefe + normalisierter Pfad für korrekte Hierarchie
                "{0:D3}_{1}" -f $depth, $normalizedPath.ToLower()
            }
        }
        
        foreach ($directoryGroup in $sortedDirectoryGroups) {
            $currentDirectoryPath = $directoryGroup.Name 
            $scriptsInDirectory = $directoryGroup.Group | Sort-Object -Property Name

            $headerTextString = ""
            $headerMarginValueString = "0,10,0,5"
            $buttonLeftMarginValue = 10
            $currentDepth = 0

            if ($currentDirectoryPath -eq $categorizationBase) {
                $headerTextString = "Folder Root" 
            }
            else {
                # Berechne die korrekte Tiefe und den Display-Namen
                $relativePath = ""
                if ($currentDirectoryPath.StartsWith($categorizationBase, [System.StringComparison]::OrdinalIgnoreCase) `
                    -and $currentDirectoryPath.Length -gt $categorizationBase.Length) {
                    
                    $relativePath = $currentDirectoryPath.Substring($categorizationBase.Length).TrimStart([System.IO.Path]::DirectorySeparatorChar)
                    $pathSegments = $relativePath -split '[\\/]' | Where-Object { $_ -ne '' }
                    $currentDepth = $pathSegments.Count
                    
                    # Zeige den vollen relativen Pfad für bessere Klarheit
                    $displayPath = $pathSegments -join ' -> '
                    $indentPrefix = "  " * $currentDepth
                    $headerTextString = "$indentPrefix$displayPath"
                } else {
                    # Fallback für Pfade außerhalb der Basis
                    $headerTextString = (Split-Path -Leaf $currentDirectoryPath)
                }
                
                # Anpassung der Button-Einrückung basierend auf der Tiefe
                $buttonLeftMarginValue = 10 + ($currentDepth * 15)
            }

            $headerBorder = New-Object System.Windows.Controls.Border
            $headerBorder.Background = "#E3F2FD"
            $headerBorder.Margin = $headerMarginValueString
            $headerBorder.Padding = "8,4"
            $headerBorder.CornerRadius = "3"
            
            $headerTextElement = New-Object System.Windows.Controls.TextBlock
            $headerTextElement.Text = $headerTextString
            $headerTextElement.FontWeight = "Bold"
            $headerTextElement.FontSize = "10"
            $headerBorder.Child = $headerTextElement
            $spScriptList.Children.Add($headerBorder)
            
            foreach ($script in $scriptsInDirectory) {
                $button = New-Object System.Windows.Controls.Button
                $button.Style = $Global:window.FindResource("ScriptButtonStyle")
                $button.Tag = $script.FullName
                $button.Margin = "$($buttonLeftMarginValue),2,5,2"
                
                $buttonContent = New-Object System.Windows.Controls.StackPanel
                $buttonContent.Orientation = "Vertical"
                
                $nameText = New-Object System.Windows.Controls.TextBlock
                $nameText.Text = $script.Name
                $nameText.FontWeight = "SemiBold"
                $buttonContent.Children.Add($nameText)
                
                try {
                    $scriptFileContent = Get-Content -Path $script.FullName -TotalCount 20 -ErrorAction SilentlyContinue
                    $synopsisDirectiveLine = $scriptFileContent | Where-Object { $_ -match "\.SYNOPSIS" } | Select-Object -First 1
                    
                    if ($synopsisDirectiveLine) {
                        $synopsisDirectiveIndex = -1
                        for ($i = 0; $i -lt $scriptFileContent.Count; $i++) {
                            if ($scriptFileContent[$i] -eq $synopsisDirectiveLine) {
                                $synopsisDirectiveIndex = $i
                                break
                            }
                        }

                        if ($synopsisDirectiveIndex -ne -1) {
                            for ($i = $synopsisDirectiveIndex + 1; $i -lt $scriptFileContent.Count; $i++) {
                                $potentialDescription = $scriptFileContent[$i].Trim()
                                if (-not [string]::IsNullOrWhiteSpace($potentialDescription) -and -not $potentialDescription.StartsWith("#")) {
                                    $descText = New-Object System.Windows.Controls.TextBlock
                                    $descText.Text = $potentialDescription
                                    $descText.TextTrimming = "CharacterEllipsis"
                                    $descText.Opacity = 0.7
                                    $descText.FontSize = "10"
                                    $buttonContent.Children.Add($descText)
                                    break
                                }
                            }
                        }
                    }
                }
                catch { }
                
                $button.Content = $buttonContent
                
                $button.Add_Click({
                    param($buttonSender, $e)
                    $scriptPathToExecute = $buttonSender.Tag
                    $scriptFileName = Split-Path -Leaf $scriptPathToExecute
                    $result = [System.Windows.MessageBox]::Show(
                        "Do you want to execute the script '$scriptFileName' in the current session?",
                        "Execute Script",
                        [System.Windows.MessageBoxButton]::YesNo,
                        [System.Windows.MessageBoxImage]::Question)
                    if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
                        try {
                            Update-LogDisplay -Message "Executing script: $scriptPathToExecute" -Type "Info"
                            Start-MainScript -ScriptPath $scriptPathToExecute -KeepSetupWindowOpen
                        }
                        catch {
                            Update-LogDisplay -Message "Error executing script '$scriptFileName': $($_.Exception.Message)" -Type "Error"
                            [System.Windows.MessageBox]::Show(
                                "Error executing script '$scriptFileName': $($_.Exception.Message)",
                                "Script Execution Error",
                                [System.Windows.MessageBoxButton]::OK,
                                [System.Windows.MessageBoxImage]::Error)
                        }
                    }
                })
                $spScriptList.Children.Add($button)
            }
        }
        Update-LogDisplay -Message "Script list loaded - $($scripts.Count) scripts found and displayed hierarchically." -Type "Success"
    }
    catch {
        Update-LogDisplay -Message "Critical error while updating script list: $($_.Exception.Message)" -Type "Error"
        # Consider if re-throwing is appropriate: throw $_
    }
}

# Vereinfachte Funktion zum Starten des Hauptskripts
function Start-MainScript {
    param (
        [string]$ScriptPath,
        [switch]$KeepSetupWindowOpen
    )
    try {
        if (-not (Test-Path -Path $ScriptPath)) {
            Write-Log "Main script not found: $ScriptPath" -Type "Error"
            return $false
        }
        Write-Log "Loading main script: $ScriptPath" -Type "Info"
        if ($KeepSetupWindowOpen -and $Global:window) {
            Update-LogDisplay -Message "Main window stays open to maintain sessions" -Type "Info"
            $Global:window.WindowState = [System.Windows.WindowState]::Minimized
            $Global:window.Title = "easyIT Setup (Script running...)"
        }
        
        $scriptTimer = [System.Diagnostics.Stopwatch]::StartNew()
        Update-LogDisplay -Message "Executing script: $ScriptPath" -Type "Info"
        & $ScriptPath
        
        return $true
    }
    catch {
        Write-Log "Error executing main script: $($_.Exception.Message)" -Type "Error"
        return $false
    }
    finally {
        if ($scriptTimer) {
            $scriptTimer.Stop()
            Update-LogDisplay -Message "Script execution time: $($scriptTimer.Elapsed.ToString())" -Type "Info"
        }
        
        if ($KeepSetupWindowOpen -and $Global:window) {
            $Global:window.WindowState = [System.Windows.WindowState]::Normal
            $Global:window.Title = "easyIT PowerShell Setup & Module Manager"
        }
    }
}

# Funktion zum Registrieren der Event-Handler der GUI
function Register-EventHandlers {
    try {
        Update-LogDisplay -Message "Registering GUI event handlers..." -Type "Info"
        
        # Button events
        $btnRefreshScripts = $Global:window.FindName("btnRefreshScripts")
        if ($btnRefreshScripts) {
            $btnRefreshScripts.Add_Click({ Update-ScriptList })
            Update-LogDisplay -Message "Script list refresh button event registered." -Type "Info"
        }
        
        $btnRefresh = $Global:window.FindName("btnRefresh")
        if ($btnRefresh) {
            $btnRefresh.Add_Click({ Check-AllModules })
            Update-LogDisplay -Message "Module list refresh button event registered." -Type "Info"
        }
        
        $btnRefreshPolicies = $Global:window.FindName("btnRefreshPolicies")
        if ($btnRefreshPolicies) {
            $btnRefreshPolicies.Add_Click({ Update-ExecutionPolicyDisplay })
            Update-LogDisplay -Message "Execution policy refresh button event registered." -Type "Info"
        }
        
        $btnExit = $Global:window.FindName("btnExit")
        if ($btnExit) {
            $btnExit.Add_Click({ $Global:window.Close() })
            Update-LogDisplay -Message "Exit button event registered." -Type "Info"
        }
        
        # Module ListView events
        $lvModules = $Global:window.FindName("lvModules")
        if ($lvModules) {
            $lvModules.AddHandler(
                [System.Windows.Controls.Button]::ClickEvent, 
                [System.Windows.RoutedEventHandler]{
                    $button = $_.OriginalSource -as [System.Windows.Controls.Button]
                    if ($button) {
                        if ($button.Content -eq "Install/Update") {
                            Install-ModuleHandler -buttonSender $button -e $_
                        }
                        elseif ($button.Content -eq "WEB LINK") {
                            $webUrl = $button.Tag.ToString()
                            Open-WebLink -url $webUrl
                        }
                    }
                }
            )
            Update-LogDisplay -Message "Module ListView button events registered." -Type "Info"
        }
        
        # ExecutionPolicy ListView events
        $lvExecutionPolicies = $Global:window.FindName("lvExecutionPolicies")
        if ($lvExecutionPolicies) {
            $lvExecutionPolicies.AddHandler(
                [System.Windows.Controls.Button]::ClickEvent, 
                [System.Windows.RoutedEventHandler]{
                    $button = $_.OriginalSource -as [System.Windows.Controls.Button]
                    if ($button) {
                        $scope = $button.Tag.ToString()
                        $policy = $button.Content.ToString()
                        
                        # Only allow modification for certain scopes
                        if ($scope -in @("Process", "CurrentUser", "LocalMachine")) {
                            Set-ExecutionPolicyHandler -scope $scope -policy $policy
                        }
                        else {
                            Update-LogDisplay -Message "Cannot modify $scope - controlled by Group Policy." -Type "Warning"
                        }
                    }
                }
            )
            Update-LogDisplay -Message "ExecutionPolicy ListView button events registered." -Type "Info"
        }
        
        Update-LogDisplay -Message "All event handlers successfully registered." -Type "Success"
        return $true
    }
    catch {
        Update-LogDisplay -Message "Error registering event handlers: $($_.Exception.Message)" -Type "Error"
        return $false
    }
}

# Hauptblock zur Initialisierung und Anzeige der GUI
try {
    Write-Log "Starting easyIT PowerShell Setup Tool..." -Type "Info"
    
    # GUI laden
    $Global:window = Import-XamlGui
    if (-not $Global:window) { throw "GUI konnte nicht geladen werden." }
    
    # Module prüfen
    Check-AllModules
    
    # ExecutionPolicy anzeigen
    Update-ExecutionPolicyDisplay
    
    # Skriptliste laden
    Update-ScriptList
    
    # Event-Handler registrieren
    Register-EventHandlers

    Write-Log "GUI erfolgreich initialisiert und Event-Handler registriert." -Type "Success"
    
    # GUI anzeigen
    [void]$Global:window.ShowDialog()
}
catch {
    $exception = $_
    $errorMessage = $exception.Exception.Message
    $fullStackTrace = $exception.ToString() # Für detaillierte Protokollierung

    # Allgemeine Fehlerbehandlung
    $lineNumber = $exception.InvocationInfo.ScriptLineNumber
    Write-Log -Message "Fehler bei der Ausführung des Setup-Tools (Zeile $lineNumber): $errorMessage. FullError: $fullStackTrace" -Type "Error"
    [System.Windows.MessageBox]::Show("Ein unerwarteter Fehler ist aufgetreten: $errorMessage`nDetails finden Sie in den Protokollen.", "Fehler", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
}

