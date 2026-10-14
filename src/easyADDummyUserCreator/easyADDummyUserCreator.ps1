# ============================================
# Version:     0.0.4
# Autor:       Andreas Hepp | PhinIT (www.phinit.de)
# ============================================

#requires -Version 5.0
#requires -Modules ActiveDirectory

<#
.SYNOPSIS
    Erstellt Active-Directory-Testobjekte (Benutzer, Gruppen, OUs, Computer, Dienstkonten, Drucker) für Testumgebungen.
.DESCRIPTION
    Ein PowerShell-Skript mit WPF-GUI zum Erstellen und Bereinigen von AD-Testdaten.
    Alle Funktionen sind über die Oberfläche erreichbar; erstellte Objekte werden pro Sitzung nachverfolgt
    und können über die Lösch- bzw. Bereinigungsfunktionen wieder entfernt werden.

    Funktionen:
    - CSV-Import mit konfigurierbaren Attributzuordnungen und nachträglichem Befüllen von Attributen
    - Zufallsbenutzer, Benutzer aus Vorlage, Zufallsattribute, Profilbilder (thumbnailPhoto), Anmeldezeiten
    - Gruppen (automatisch, verschachtelt), OU-Strukturvorlagen nach Firmengröße
    - Computer, Dienstkonten, Drucker (printQueue), simulierte BitLocker- und LAPS-Daten
    - Testdaten-Sets, Chaos-Modus, Performance-Test, Kennwortrichtlinien, RBAC-Rollen
    - Export der erstellten Objekte, Protokollierung, Bestätigungsdialoge für kritische Operationen
.NOTES
    Version: 0.0.4
    Autor:   Andreas Hepp | PhinIT (www.phinit.de)
    Stellen Sie sicher, dass das ActiveDirectory PowerShell-Modul installiert ist und Sie über die erforderlichen Berechtigungen verfügen.
    Logdatei: <Skriptordner>\Logs\easyADDummyUserCreator.log
    Exporte:  <Skriptordner>\Exports\
    Passwörter: Es wird kein Standardpasswort mehr ausgeliefert. Für CSV-Benutzer kann im GUI ein Initial-Passwort
    eingegeben werden; bleibt das Feld leer, erhält jeder Benutzer ein eigenes, kryptografisch zufälliges Passwort.
    Passwörter werden niemals in die Logdatei geschrieben.
#>

#region Skriptweite Variablen und Konfiguration
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Basisverzeichnis des Skripts (unabhängig vom aktuellen Arbeitsverzeichnis)
$scriptRootPath = if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Path $MyInvocation.MyCommand.Path -Parent
} else {
    (Get-Location).ProviderPath
}

$script:AppConfig = @{
    AppName                = "easy DC Dummy Object Creator"
    ScriptVersion          = "0.0.4"
    Author                 = "Andreas Hepp  |  www.phinit.de"
    ScriptRoot             = $scriptRootPath
    DefaultCsvPath         = (Join-Path $scriptRootPath "AD_DummyUserList.csv") # Standardpfad, kann im GUI geändert werden
    EnablePasswordChange   = $true                     # Benutzer muss Passwort bei nächster Anmeldung ändern
    LogDirectory           = (Join-Path $scriptRootPath "Logs")
    LogFilePath            = (Join-Path (Join-Path $scriptRootPath "Logs") "easyADDummyUserCreator.log") # Pfad für Logdatei
    ExportDirectory        = (Join-Path $scriptRootPath "Exports") # Zielordner für Exporte/Berichte
}
$script:IsBusy = $false
$script:CryptoRng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$script:DomainInfoCache = $null

$script:Window = $null
$script:GuiControls = @{}
$script:CsvData = $null
$script:CreatedUsers = [System.Collections.Generic.List[object]]::new()
$script:CreatedGroups = [System.Collections.Generic.List[object]]::new()
$script:CreatedComputers = [System.Collections.Generic.List[object]]::new()
$script:CreatedOUs = [System.Collections.Generic.List[object]]::new()
$script:CreatedServiceAccounts = [System.Collections.Generic.List[object]]::new()
$script:CreatedPrinters = [System.Collections.Generic.List[object]]::new() # DistinguishedNames der printQueue-Objekte
# Benutzer des letzten Laufs von 'Benutzer aus CSV erstellen' (SamAccountName + CSV-Zeile) - Grundlage für 'Attribute befüllen'
$script:LastCsvImportUsers = [System.Collections.Generic.List[object]]::new()

# AD Attribute Mapping Konfiguration
$script:SelectableADAttributes = @(
    @{Name="SamAccountName"; CsvHeader="SamAccountName"; Required=$true}
    @{Name="GivenName"; CsvHeader="FirstName"; Required=$false}
    @{Name="Surname"; CsvHeader="LastName"; Required=$false}
    @{Name="DisplayName"; CsvHeader="DisplayName"; Required=$false}
    @{Name="EmailAddress"; CsvHeader="Email"; Required=$false}
    @{Name="UserPrincipalName"; CsvHeader="UserPrincipalName"; Required=$false}
    @{Name="Department"; CsvHeader="Department"; Required=$false}
    @{Name="Title"; CsvHeader="Title"; Required=$false}
    @{Name="Company"; CsvHeader="Company"; Required=$false}
    @{Name="Manager"; CsvHeader="Manager"; Required=$false}
    @{Name="Description"; CsvHeader="Description"; Required=$false}
    @{Name="Office"; CsvHeader="Office"; Required=$false}
    @{Name="StreetAddress"; CsvHeader="StreetAddress"; Required=$false}
    @{Name="City"; CsvHeader="City"; Required=$false}
    @{Name="State"; CsvHeader="State"; Required=$false}
    @{Name="PostalCode"; CsvHeader="PostalCode"; Required=$false}
    @{Name="Country"; CsvHeader="Country"; Required=$false}
    @{Name="OfficePhone"; CsvHeader="TelephoneNumber"; Required=$false}
    @{Name="MobilePhone"; CsvHeader="Mobile"; Required=$false}
    @{Name="proxyAddresses"; CsvHeader="proxyAddresses"; Required=$false}
    @{Name="EmployeeID"; CsvHeader="EmployeeID"; Required=$false}
    @{Name="EmployeeType"; CsvHeader="employeeType"; Required=$false}
    @{Name="Initials"; CsvHeader="initials"; Required=$false}
    @{Name="HomeDrive"; CsvHeader="homeDrive"; Required=$false}
    @{Name="HomeDirectory"; CsvHeader="homeDirectory"; Required=$false}
    @{Name="ScriptPath"; CsvHeader="scriptPath"; Required=$false}
    @{Name="ProfilePath"; CsvHeader="profilePath"; Required=$false}
)

# Zuordnung New-ADUser-Parametername -> LDAP-Attributname (für Set-ADUser -Replace / -OtherAttributes)
$script:ADAttributeLdapNames = @{
    GivenName         = 'givenName'
    Surname           = 'sn'
    DisplayName       = 'displayName'
    EmailAddress      = 'mail'
    UserPrincipalName = 'userPrincipalName'
    Department        = 'department'
    Title             = 'title'
    Company           = 'company'
    Manager           = 'manager'
    Description       = 'description'
    Office            = 'physicalDeliveryOfficeName'
    StreetAddress     = 'streetAddress'
    City              = 'l'
    State             = 'st'
    PostalCode        = 'postalCode'
    Country           = 'c'
    OfficePhone       = 'telephoneNumber'
    MobilePhone       = 'mobile'
    proxyAddresses    = 'proxyAddresses'
    EmployeeID        = 'employeeID'
    EmployeeType      = 'employeeType'
    Initials          = 'initials'
    HomeDrive         = 'homeDrive'
    HomeDirectory     = 'homeDirectory'
    ScriptPath        = 'scriptPath'
    ProfilePath       = 'profilePath'
}

# Attribute ohne eigenen New-ADUser-Parameter (werden über -OtherAttributes gesetzt)
$script:ADUserOtherAttributeNames = @('proxyAddresses', 'EmployeeType')
#endregion

#region XAML Definition
$XAML = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:sys="clr-namespace:System;assembly=mscorlib"
    Title="$($script:AppConfig.AppName) v$($script:AppConfig.ScriptVersion)"
    Width="1800"
    Height="1000"
    MinWidth="1000"
    MinHeight="700"
    Background="#F8F9FA"
    FontFamily="Segoe UI"
    WindowStartupLocation="CenterScreen"
    mc:Ignorable="d">
    <Window.Resources>
        <!--  Modern Color Palette  -->
        <SolidColorBrush x:Key="PrimaryBrush" Color="#0078D4" />
        <SolidColorBrush x:Key="PrimaryHoverBrush" Color="#106EBE" />
        <SolidColorBrush x:Key="PrimaryPressedBrush" Color="#005A9E" />
        <SolidColorBrush x:Key="SecondaryBrush" Color="#6C757D" />
        <SolidColorBrush x:Key="SuccessBrush" Color="#28A745" />
        <SolidColorBrush x:Key="DangerBrush" Color="#DC3545" />
        <SolidColorBrush x:Key="WarningBrush" Color="#FFC107" />
        <SolidColorBrush x:Key="SurfaceBrush" Color="#F8F9FA" />
        <SolidColorBrush x:Key="BorderBrush" Color="#DEE2E6" />
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="#212529" />
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="#6C757D" />

        <!--  Modern Button Styles  -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}" />
            <Setter Property="Foreground" Value="White" />
            <Setter Property="BorderThickness" Value="0" />
            <Setter Property="Padding" Value="12,6" />
            <Setter Property="Margin" Value="3" />
            <Setter Property="FontWeight" Value="Medium" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="MinWidth" Value="100" />
            <Setter Property="MinHeight" Value="32" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border
                            x:Name="border"
                            Background="{TemplateBinding Background}"
                            CornerRadius="6">
                            <ContentPresenter
                                Margin="{TemplateBinding Padding}"
                                HorizontalAlignment="Center"
                                VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource PrimaryHoverBrush}" />
                                <Setter TargetName="border" Property="Effect">
                                    <Setter.Value>
                                        <DropShadowEffect
                                            BlurRadius="6"
                                            Direction="270"
                                            Opacity="0.2"
                                            ShadowDepth="2"
                                            Color="Black" />
                                    </Setter.Value>
                                </Setter>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource PrimaryPressedBrush}" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Background" Value="#A0A0A0" />
                                <Setter Property="Foreground" Value="#D0D0D0" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style
            x:Key="SecondaryButton"
            BasedOn="{StaticResource ModernButton}"
            TargetType="Button">
            <Setter Property="Background" Value="{StaticResource SecondaryBrush}" />
        </Style>

        <Style
            x:Key="DangerButton"
            BasedOn="{StaticResource ModernButton}"
            TargetType="Button">
            <Setter Property="Background" Value="{StaticResource DangerBrush}" />
        </Style>

        <Style
            x:Key="SuccessButton"
            BasedOn="{StaticResource ModernButton}"
            TargetType="Button">
            <Setter Property="Background" Value="{StaticResource SuccessBrush}" />
        </Style>

        <!--  Modern Input Styles  -->
        <Style TargetType="Label">
            <Setter Property="Margin" Value="0,0,0,3" />
            <Setter Property="VerticalAlignment" Value="Center" />
            <Setter Property="FontWeight" Value="Medium" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        </Style>

        <Style TargetType="TextBox">
            <Setter Property="Margin" Value="0,0,0,8" />
            <Setter Property="Padding" Value="8,6" />
            <Setter Property="VerticalAlignment" Value="Center" />
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Background" Value="White" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="MinHeight" Value="28" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border
                            x:Name="border"
                            Background="{TemplateBinding Background}"
                            BorderBrush="{TemplateBinding BorderBrush}"
                            BorderThickness="{TemplateBinding BorderThickness}"
                            CornerRadius="4">
                            <ScrollViewer x:Name="PART_ContentHost" Margin="0" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource PrimaryBrush}" />
                            </Trigger>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter TargetName="border" Property="BorderBrush" Value="{StaticResource PrimaryBrush}" />
                                <Setter TargetName="border" Property="BorderThickness" Value="2" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style TargetType="ComboBox">
            <Setter Property="Margin" Value="0,0,0,8" />
            <Setter Property="Padding" Value="8,6" />
            <Setter Property="VerticalAlignment" Value="Center" />
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="Background" Value="White" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="MinHeight" Value="28" />
        </Style>

        <Style TargetType="CheckBox">
            <Setter Property="Margin" Value="0,0,0,6" />
            <Setter Property="VerticalAlignment" Value="Center" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        </Style>

        <!--  Modern GroupBox Style  -->
        <Style TargetType="GroupBox">
            <Setter Property="Margin" Value="0,0,0,12" />
            <Setter Property="Padding" Value="12" />
            <Setter Property="Background" Value="White" />
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="GroupBox">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="*" />
                            </Grid.RowDefinitions>
                            <Border
                                Grid.Row="0"
                                Padding="8,6"
                                Background="{StaticResource SurfaceBrush}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1,1,1,0"
                                CornerRadius="6,6,0,0">
                                <ContentPresenter ContentSource="Header" />
                            </Border>
                            <Border
                                Grid.Row="1"
                                Padding="{TemplateBinding Padding}"
                                Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="1,0,1,1"
                                CornerRadius="0,0,6,6">
                                <ContentPresenter />
                            </Border>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!--  Modern DataGrid Style  -->
        <Style TargetType="DataGrid">
            <Setter Property="Background" Value="White" />
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="GridLinesVisibility" Value="Horizontal" />
            <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource BorderBrush}" />
            <Setter Property="AlternatingRowBackground" Value="{StaticResource SurfaceBrush}" />
            <Setter Property="RowBackground" Value="White" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="Margin" Value="0,0,0,8" />
            <Setter Property="RowHeight" Value="24" />
            <Setter Property="ColumnHeaderHeight" Value="28" />
        </Style>

        <!--  Collapsible Expander Style  -->
        <Style TargetType="Expander">
            <Setter Property="Margin" Value="0,0,0,8" />
            <Setter Property="Background" Value="White" />
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="FontSize" Value="13" />
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}" />
        </Style>

        <!--  Small Button Style for compact areas  -->
        <Style
            x:Key="SmallButton"
            BasedOn="{StaticResource ModernButton}"
            TargetType="Button">
            <Setter Property="FontSize" Value="11" />
            <Setter Property="Padding" Value="8,4" />
            <Setter Property="MinHeight" Value="24" />
            <Setter Property="MinWidth" Value="80" />
        </Style>

        <!--  Warning Button Style  -->
        <Style
            x:Key="WarningButton"
            BasedOn="{StaticResource ModernButton}"
            TargetType="Button">
            <Setter Property="Background" Value="{StaticResource WarningBrush}" />
            <Setter Property="Foreground" Value="Black" />
        </Style>
    </Window.Resources>
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <!--  Header  -->
            <RowDefinition Height="*" />
            <!--  Main Content  -->
            <RowDefinition Height="Auto" />
            <!--  Footer / Status  -->
        </Grid.RowDefinitions>

        <!--  Header  -->
        <Border
            Grid.Row="0"
            Padding="16,12"
            Background="White"
            BorderBrush="{StaticResource BorderBrush}"
            BorderThickness="0,0,0,1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>
                <StackPanel
                    Grid.Column="0"
                    VerticalAlignment="Center"
                    Orientation="Horizontal">
                    <Border
                        Width="32"
                        Height="32"
                        Margin="0,0,10,0"
                        Background="{StaticResource PrimaryBrush}"
                        CornerRadius="6">
                        <TextBlock
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center"
                            FontSize="14"
                            FontWeight="Bold"
                            Foreground="White"
                            Text="AD" />
                    </Border>
                    <StackPanel>
                        <TextBlock
                            FontSize="16"
                            FontWeight="SemiBold"
                            Foreground="{StaticResource TextPrimaryBrush}"
                            Text="$($script:AppConfig.AppName)" />
                        <TextBlock
                            FontSize="11"
                            Foreground="{StaticResource TextSecondaryBrush}"
                            Text="Active-Directory-Testobjekte erstellen und verwalten" />
                    </StackPanel>
                </StackPanel>
                <StackPanel
                    Grid.Column="2"
                    VerticalAlignment="Center"
                    Orientation="Horizontal">
                    <Border
                        Margin="0,0,6,0"
                        Padding="6,3"
                        Background="{StaticResource SuccessBrush}"
                        CornerRadius="10">
                        <TextBlock
                            FontSize="10"
                            FontWeight="Medium"
                            Foreground="White"
                            Text="v$($script:AppConfig.ScriptVersion)" />
                    </Border>
                </StackPanel>
            </Grid>
        </Border>

        <!--  Main Content  -->
        <Grid Grid.Row="1" Margin="16">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*" MinWidth="600" />
                <ColumnDefinition Width="12" />
                <!--  Spacer  -->
                <ColumnDefinition Width="700" MinWidth="600" />
            </Grid.ColumnDefinitions>

            <!--  Left Panel: CSV-Based User Creation  -->
            <ScrollViewer Grid.Column="0" VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="0,0,0,16">
                    <!--  Test-Umgebung Setup  -->
                    <GroupBox Margin="0,0,0,12" Header="🏢 Test-Umgebung einrichten">
                        <StackPanel>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="Auto" />
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>
                                <Label Grid.Column="0" Content="Firmenname:" />
                                <TextBox
                                    x:Name="TextBoxCompanyName"
                                    Grid.Column="1"
                                    Height="39"
                                    Margin="10,0,491,0"
                                    ToolTip="Name der Wurzel-OU für Test-Umgebung und OU-Struktur (leer = TestCompany) und Wert des Firmenattributs bei Zufallsbenutzern (leer = Testfirma)" />
                                <Button
                                    x:Name="ButtonCreateTestEnvironment"
                                    Grid.Column="1"
                                    Margin="457,0,253,0"
                                    Content="🏗️ Umgebung erstellen"
                                    Style="{StaticResource SuccessButton}"
                                    ToolTip="Erstellt komplette Test-OU-Struktur" />
                                <TextBlock
                                    Grid.Column="1"
                                    Width="248"
                                    Height="24"
                                    Margin="695,0,0,0"
                                    HorizontalAlignment="Left"
                                    VerticalAlignment="Center"
                                    FontSize="9"
                                    Foreground="{StaticResource TextSecondaryBrush}"
                                    TextWrapping="Wrap"><Run Text="OU=&lt;Firmenname&gt;" /><Run Text=" mit " /><Run Text="Unter-OUs: " /><LineBreak /><Run Text="USERS, GROUPS, COMPUTERS, SERVICES, RESOURCES" /></TextBlock>
                            </Grid>
                        </StackPanel>
                    </GroupBox>

                    <!--  CSV-basierte Benutzererstellung (Einklappbar)  -->
                    <!--  CSV Datei laden  -->
                    <Expander Header="📁 CSV-Datei laden" IsExpanded="True">
                        <StackPanel>
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto" />
                                    <RowDefinition Height="Auto" />
                                </Grid.RowDefinitions>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="Auto" />
                                    <ColumnDefinition Width="Auto" />
                                </Grid.ColumnDefinitions>
                                <TextBox
                                    x:Name="TextBoxCsvPath"
                                    Grid.Row="1"
                                    Grid.Column="0"
                                    Margin="25,0,25,0"
                                    Text="$($script:AppConfig.DefaultCsvPath)" />
                                <Button
                                    x:Name="ButtonBrowseCsv"
                                    Grid.Row="1"
                                    Grid.Column="1"
                                    Margin="0,3,6,3"
                                    Content="📂 Durchsuchen"
                                    Style="{StaticResource ModernButton}"
                                    ToolTip="Durchsuchen" />
                                <Button
                                    x:Name="ButtonLoadCsv"
                                    Grid.Row="1"
                                    Grid.Column="2"
                                    Margin="10,3,3,3"
                                    Content="📋 Laden"
                                    Style="{StaticResource ModernButton}" />
                            </Grid>
                        </StackPanel>
                    </Expander>

                    <!--  CSV Inhalt anzeigen  -->
                    <GroupBox Header="📋 CSV Inhalt anzeigen">
                        <DataGrid
                            x:Name="DataGridCsvContent"
                            Width="1040"
                            MaxHeight="430"
                            AutoGenerateColumns="True"
                            IsReadOnly="True" />
                    </GroupBox>

                    <!--  Fortschrittsanzeige  -->
                    <Grid
                        x:Name="GridProgressArea"
                        Margin="0,8,0,0"
                        Visibility="Collapsed">
                        <Grid.RowDefinitions>
                            <RowDefinition Height="Auto" />
                            <RowDefinition Height="Auto" />
                        </Grid.RowDefinitions>
                        <Label
                            x:Name="LabelProgress"
                            Grid.Row="0"
                            HorizontalAlignment="Center"
                            Content="Fortschritt:" />
                        <ProgressBar
                            x:Name="ProgressBarMain"
                            Grid.Row="1"
                            Height="20"
                            Background="{StaticResource SurfaceBrush}"
                            Foreground="{StaticResource SuccessBrush}"
                            Maximum="100"
                            Minimum="0"
                            Value="0" />
                    </Grid>
                    <Expander Header="⚙️ CSV-Import Einstellungen" IsExpanded="False">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                            </Grid.RowDefinitions>

                            <Grid Grid.Row="0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="120" />
                                    <ColumnDefinition Width="*" />
                                </Grid.ColumnDefinitions>
                                <Label Grid.Column="0" Content="Ziel-OU:" />
                                <ComboBox
                                    x:Name="ComboBoxTargetOU"
                                    Grid.Column="1"
                                    Margin="0,0,10,0"
                                    VerticalAlignment="Top"
                                    IsEditable="True"
                                    ToolTip="Wählen Sie eine OU oder verwenden Sie die Test-Umgebung" />
                            </Grid>

                            <Grid Grid.Row="1" Margin="0,4,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="120" />
                                    <ColumnDefinition Width="*" />
                                </Grid.ColumnDefinitions>
                                <Label Grid.Column="0" Content="Anzahl:" />
                                <TextBox
                                    x:Name="TextBoxNumUsersToCreate"
                                    Grid.Column="1"
                                    Margin="0,0,10,0"
                                    VerticalAlignment="Top"
                                    ToolTip="Leer = alle Benutzer aus der CSV" />
                            </Grid>

                            <Grid Grid.Row="2" Margin="0,4,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="120" />
                                    <ColumnDefinition Width="*" />
                                </Grid.ColumnDefinitions>
                                <Label Grid.Column="0" Content="Initial-Passwort:" />
                                <PasswordBox
                                    x:Name="PasswordBoxInitialPassword"
                                    Grid.Column="1"
                                    Margin="0,0,10,0"
                                    VerticalAlignment="Top"
                                    ToolTip="Optional: Initial-Passwort für alle neu erstellten Benutzer (CSV, Zufall, Vorlage, Performance-Test). Leer = zufälliges, sicheres Passwort pro Benutzer (wird nicht gespeichert/protokolliert)" />
                            </Grid>

                            <Label
                                Grid.Row="3"
                                Margin="0,4,0,0"
                                Content="Zu importierende Attribute:" />
                            <ScrollViewer
                                Grid.Row="4"
                                MaxHeight="150"
                                Margin="0,4,0,0"
                                Background="White"
                                BorderBrush="{StaticResource BorderBrush}"
                                BorderThickness="1"
                                VerticalScrollBarVisibility="Auto">
                                <StackPanel
                                    x:Name="StackPanelAttributeSelection"
                                    Margin="4"
                                    Orientation="Vertical" />
                            </ScrollViewer>
                        </Grid>
                    </Expander>
                    <Expander Header="🔧 Erstellte Benutzer verwalten" IsExpanded="False">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                            </Grid.RowDefinitions>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>

                            <Label
                                Grid.Row="0"
                                Grid.Column="0"
                                Content="Anzahl:" />
                            <TextBox
                                x:Name="TextBoxNumUsersForAction"
                                Grid.Row="0"
                                Grid.ColumnSpan="2"
                                Margin="53,0,10,0"
                                VerticalAlignment="Top"
                                ToolTip="Anzahl der zuerst erstellten Benutzer dieser Sitzung (CSV, Zufall, Vorlage, Performance-Test). Leer = alle." />

                            <Grid
                                Grid.Row="1"
                                Grid.Column="0"
                                Grid.ColumnSpan="2"
                                Margin="0,4,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="*" />
                                </Grid.ColumnDefinitions>
                                <Button
                                    x:Name="ButtonDisableUsers"
                                    Grid.Column="0"
                                    Margin="10,0,2,0"
                                    Content="🚫 Deaktivieren"
                                    Style="{StaticResource WarningButton}"
                                    ToolTip="Deaktiviert die in dieser Sitzung erstellten Benutzer (Anzahl siehe oben)" />
                                <Button
                                    x:Name="ButtonDeleteUsers"
                                    Grid.Column="1"
                                    Margin="2,0,10,0"
                                    Content="🗑️ Löschen"
                                    Style="{StaticResource DangerButton}"
                                    ToolTip="Löscht die in dieser Sitzung erstellten Benutzer (Anzahl siehe oben) unwiderruflich" />
                            </Grid>
                        </Grid>
                    </Expander>
                    <Expander Header="🚀 CSV-Aktionen" IsExpanded="True">
                        <Grid Margin="0,6,0,5">
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*" />
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="Auto" />
                                <ColumnDefinition Width="*" />
                            </Grid.ColumnDefinitions>
                            <Button
                                x:Name="ButtonCreateADUsers"
                                Grid.Column="1"
                                Margin="0,0,4,0"
                                Content="👥 Benutzer aus CSV erstellen"
                                Style="{StaticResource SuccessButton}"
                                ToolTip="Erstellt AD-Benutzer basierend auf CSV-Daten" />
                            <Button
                                x:Name="ButtonFillAttributes"
                                Grid.Column="2"
                                Margin="0,0,4,0"
                                Content="📝 Attribute befüllen"
                                Style="{StaticResource ModernButton}"
                                ToolTip="Überschreibt die ausgewählten Attribute der Benutzer, die beim LETZTEN Lauf von 'Benutzer aus CSV erstellen' angelegt wurden, mit den Werten der aktuell geladenen CSV (gleiche Zeile). Ein neuer CSV-Import ersetzt diese Liste; zufällig oder per Vorlage erstellte Benutzer werden nicht berücksichtigt." />
                            <Button
                                x:Name="ButtonExportCreatedUsers"
                                Grid.Column="3"
                                Margin="3,0,3,0"
                                Content="📤 Export"
                                Style="{StaticResource SecondaryButton}"
                                ToolTip="Exportiert erstellte Benutzer" />
                        </Grid>
                    </Expander>
                </StackPanel>
            </ScrollViewer>

            <!--  Right Panel: Random Creation & Advanced Features  -->
            <ScrollViewer
                Grid.Column="2"
                Padding="0,0,8,0"
                VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="0,0,0,16" Orientation="Vertical">

                    <!--  Schnellzugriff Panel  -->
                    <GroupBox Margin="0,0,0,12" Header="⚡ Schnellzugriff &amp; Verwaltung">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto" />
                                <RowDefinition Height="Auto" />
                            </Grid.RowDefinitions>

                            <!--  Schnell-Erstellung  -->
                            <GroupBox
                                Grid.Row="0"
                                Margin="0,0,0,8"
                                Header="🚀 Schnell-Erstellung">
                                <UniformGrid Columns="2" Rows="2">
                                    <Button
                                        x:Name="ButtonQuickRandomUsers"
                                        Margin="3"
                                        Content="👥 Zufallsbenutzer"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt zufällige Test-Benutzer (Einstellungen unter 'Zufallsbenutzer erstellen')" />
                                    <Button
                                        x:Name="ButtonQuickCreateGroups"
                                        Margin="3"
                                        Content="🏢 Auto-Gruppen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erstellt Gruppen basierend auf Benutzern" />
                                    <Button
                                        x:Name="ButtonQuickTestData"
                                        Margin="3"
                                        Content="🧪 Komplettes Set"
                                        Style="{StaticResource WarningButton}"
                                        ToolTip="Erstellt komplettes Testdaten-Set" />
                                    <Button
                                        x:Name="ButtonQuickCleanup"
                                        Margin="3"
                                        Content="🧹 Alles löschen"
                                        Style="{StaticResource DangerButton}"
                                        ToolTip="Löscht alle in dieser Sitzung erstellten Gruppen, Computer, Dienstkonten, Drucker und Test-OUs (USERS, GROUPS, COMPUTERS, SERVICES, RESOURCES). Benutzer werden nur mit entfernt, wenn sie in einer gelöschten Test-OU liegen; OUs aus der OU-Struktur bleiben erhalten (→ 🗑️ OUs)." />
                                </UniformGrid>
                            </GroupBox>

                            <!--  Objekt-Verwaltung  -->
                            <GroupBox
                                Grid.Row="1"
                                Margin="0,0,0,8"
                                Header="📊 Objekt-Verwaltung">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto" />
                                        <RowDefinition Height="Auto" />
                                    </Grid.RowDefinitions>

                                    <!--  Lösch-Buttons  -->
                                    <UniformGrid
                                        Grid.Row="0"
                                        Margin="0,0,0,4"
                                        Columns="3"
                                        Rows="2">
                                        <Button
                                            x:Name="ButtonDeleteGroups"
                                            Margin="2"
                                            Content="🗑️ Gruppen"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Löscht alle erstellten Gruppen" />
                                        <Button
                                            x:Name="ButtonDeleteComputers"
                                            Margin="2"
                                            Content="🗑️ Computer"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Löscht alle erstellten Computer" />
                                        <Button
                                            x:Name="ButtonDeleteOUs"
                                            Margin="2"
                                            Content="🗑️ OUs"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Löscht alle erstellten OUs" />
                                        <Button
                                            x:Name="ButtonDeleteServiceAccounts"
                                            Margin="2"
                                            Content="🗑️ Dienstkonten"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Löscht alle erstellten Dienstkonten" />
                                        <Button
                                            x:Name="ButtonDeletePrinters"
                                            Margin="2"
                                            Content="🗑️ Drucker"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Löscht alle erstellten Drucker-Objekte (printQueue)" />
                                    </UniformGrid>

                                    <!--  Export Button  -->
                                    <Button
                                        x:Name="ButtonExportAll"
                                        Grid.Row="1"
                                        Content="📤 Alle Objekte exportieren"
                                        Style="{StaticResource SecondaryButton}"
                                        ToolTip="Exportiert alle erstellten Objekte" />
                                </Grid>
                            </GroupBox>

                        </Grid>
                    </GroupBox>

                    <!--  Statistik Panel  -->
                    <GroupBox Margin="0,0,0,12" Header="📊 Erstellte Objekte">
                        <StackPanel>
                            <Grid>
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="*" />
                                </Grid.ColumnDefinitions>

                                <Border
                                    Grid.Column="0"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="👥 Benutzer" />
                                        <TextBlock
                                            x:Name="TextBlockUserCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>

                                <Border
                                    Grid.Column="1"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="🏢 Gruppen" />
                                        <TextBlock
                                            x:Name="TextBlockGroupCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>

                                <Border
                                    Grid.Column="2"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="💻 Computer" />
                                        <TextBlock
                                            x:Name="TextBlockComputerCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>
                            </Grid>

                            <Grid Margin="0,4,0,0">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="*" />
                                    <ColumnDefinition Width="*" />
                                </Grid.ColumnDefinitions>

                                <Border
                                    Grid.Column="0"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="🏗️ OUs" />
                                        <TextBlock
                                            x:Name="TextBlockOUCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>

                                <Border
                                    Grid.Column="1"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="⚙️ Dienstkonten" />
                                        <TextBlock
                                            x:Name="TextBlockServiceCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>

                                <Border
                                    Grid.Column="2"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="🖨️ Drucker" />
                                        <TextBlock
                                            x:Name="TextBlockPrinterCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>

                                <Border
                                    Grid.Column="3"
                                    Margin="2"
                                    Padding="4"
                                    Background="{StaticResource SurfaceBrush}"
                                    CornerRadius="4">
                                    <StackPanel HorizontalAlignment="Center">
                                        <TextBlock FontSize="12" Text="🎯 Gesamt" />
                                        <TextBlock
                                            x:Name="TextBlockTotalCount"
                                            HorizontalAlignment="Center"
                                            FontSize="16"
                                            FontWeight="Bold"
                                            Text="0" />
                                    </StackPanel>
                                </Border>
                            </Grid>
                        </StackPanel>
                    </GroupBox>

                    <!--  1. Random Benutzer-Erstellung (Hauptbereich)  -->
                    <Expander Header="🎲 Zufallsbenutzer erstellen" IsExpanded="False">
                        <StackPanel>
                            <!--  Zufallsbenutzer: Einstellungen  -->
                            <GroupBox Margin="0,0,0,8" Header="⚙️ Einstellungen für Zufallsbenutzer">
                                <Grid>
                                    <Grid.RowDefinitions>
                                        <RowDefinition Height="Auto" />
                                        <RowDefinition Height="Auto" />
                                        <RowDefinition Height="Auto" />
                                        <RowDefinition Height="Auto" />
                                        <RowDefinition Height="Auto" />
                                    </Grid.RowDefinitions>

                                    <Grid Grid.Row="0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Anzahl Benutzer:" />
                                        <TextBox
                                            x:Name="TextBoxRandomUserCount"
                                            Grid.Column="1"
                                            Text="50"
                                            ToolTip="Anzahl der zu erstellenden Zufallsbenutzer" />
                                    </Grid>

                                    <Label
                                        Grid.Row="1"
                                        Margin="0,4,0,0"
                                        Content="Zufällige Attribute:" />
                                    <Grid Grid.Row="2">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <StackPanel Grid.Column="0">
                                            <CheckBox
                                                x:Name="CheckBoxRandomNames"
                                                Content="Namen"
                                                IsChecked="True" />
                                            <CheckBox
                                                x:Name="CheckBoxRandomAddresses"
                                                Content="Adressen"
                                                IsChecked="True" />
                                            <CheckBox
                                                x:Name="CheckBoxRandomPhone"
                                                Content="Telefon"
                                                IsChecked="True" />
                                        </StackPanel>
                                        <StackPanel Grid.Column="1">
                                            <CheckBox
                                                x:Name="CheckBoxRandomDepartments"
                                                Content="Abteilungen"
                                                IsChecked="True" />
                                            <CheckBox
                                                x:Name="CheckBoxRandomTitles"
                                                Content="Titel"
                                                IsChecked="True" />
                                            <CheckBox
                                                x:Name="CheckBoxRandomCompany"
                                                Content="Firma"
                                                IsChecked="True" />
                                        </StackPanel>
                                    </Grid>

                                    <Label
                                        Grid.Row="3"
                                        Margin="0,4,0,0"
                                        Content="Passwort-Komplexität:" />
                                    <ComboBox
                                        x:Name="ComboBoxPasswordComplexity"
                                        Grid.Row="4"
                                        ToolTip="Länge/Komplexität der zufälligen Initialpasswörter. Wird ignoriert, wenn im CSV-Bereich ein Initial-Passwort eingegeben ist. Passwörter werden weder gespeichert noch protokolliert.">
                                        <ComboBoxItem Content="Einfach (8 Zeichen)" />
                                        <ComboBoxItem Content="Mittel (12 Zeichen + Symbole)" IsSelected="True" />
                                        <ComboBoxItem Content="Komplex (16 Zeichen + Spezial)" />
                                        <ComboBoxItem Content="Hochsicher (20+ Zeichen)" />
                                    </ComboBox>
                                </Grid>
                            </GroupBox>

                            <!--  Zufallsbenutzer: Aktionen  -->
                            <GroupBox Margin="0,0,0,8" Header="🚀 Zufallsbenutzer anlegen">
                                <StackPanel>
                                    <Button
                                        x:Name="ButtonCreateRandomUsers"
                                        Content="👥 Zufallsbenutzer erstellen"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt zufällige Benutzer in der Test-OU (USERS) unterhalb der Ziel-OU. Passwort: das Initial-Passwort aus dem CSV-Bereich oder ein zufälliges Passwort je Benutzer (nicht gespeichert)." />
                                    <Grid Margin="0,4,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <CheckBox
                                            x:Name="CheckBoxIncludeNumbers"
                                            Grid.Column="0"
                                            Content="Zahlen in Passwörtern"
                                            IsChecked="True" />
                                        <CheckBox
                                            x:Name="CheckBoxIncludeSymbols"
                                            Grid.Column="1"
                                            Content="Symbole in Passwörtern"
                                            IsChecked="True" />
                                    </Grid>
                                    <CheckBox
                                        x:Name="CheckBoxExcludeAmbiguous"
                                        Margin="0,2,0,0"
                                        Content="Mehrdeutige Zeichen vermeiden (0/O, 1/l)"
                                        IsChecked="True" />
                                    <CheckBox
                                        x:Name="CheckBoxSetExpiryDate"
                                        Margin="0,2,0,0"
                                        Content="Zufälliges Kontoablaufdatum (30–365 Tage)"
                                        ToolTip="Setzt für jeden neuen Benutzer ein zufälliges Kontoablaufdatum zwischen 30 und 365 Tagen in der Zukunft" />
                                    <CheckBox
                                        x:Name="CheckBoxTemporaryAccount"
                                        Margin="0,2,0,0"
                                        Content="Als temporäre Konten anlegen (Ablauf in 30 Tagen)"
                                        ToolTip="Kontoablaufdatum = heute + 30 Tage (hat Vorrang vor dem zufälligen Ablaufdatum)" />
                                </StackPanel>
                            </GroupBox>

                            <!--  Erstellte Benutzer anpassen  -->
                            <GroupBox Margin="0,0,0,8" Header="🎯 Erstellte Benutzer anpassen">
                                <StackPanel>
                                    <Button
                                        x:Name="ButtonGenerateRandomData"
                                        Content="📊 Zufallsattribute zuweisen"
                                        Style="{StaticResource SecondaryButton}"
                                        ToolTip="Überschreibt bei allen vom Tool erstellten Benutzern die oben ausgewählten Attribute (Namen, Adressen, Telefon, Abteilung, Titel, Firma) mit neuen Zufallswerten" />
                                    <CheckBox
                                        x:Name="CheckBoxGenerateAvatars"
                                        Margin="0,6,0,0"
                                        Content="Avatare automatisch generieren (Initialen)"
                                        IsChecked="True"
                                        ToolTip="Aktiviert: Es werden Initialen-Avatare erzeugt. Deaktiviert: Es werden JPG-Bilder aus dem gewählten Ordner verwendet." />
                                    <Grid Margin="0,4,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="Auto" />
                                        </Grid.ColumnDefinitions>
                                        <TextBox
                                            x:Name="TextBoxAvatarPath"
                                            Grid.Column="0"
                                            ToolTip="Ordner mit JPG-Bildern (max. 100 KB je Bild) für das Attribut thumbnailPhoto" />
                                        <Button
                                            x:Name="ButtonBrowseAvatars"
                                            Grid.Column="1"
                                            Margin="4,0,0,0"
                                            Content="📁"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Ordner mit Avatar-Bildern auswählen" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonAssignAvatars"
                                        Margin="0,4,0,0"
                                        Content="🖼️ Avatare zuweisen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Setzt thumbnailPhoto bei allen vom Tool erstellten Benutzern (generierte Initialen-Avatare oder Bilder aus dem Ordner)" />
                                </StackPanel>
                            </GroupBox>

                            <!--  Benutzer aus Vorlage  -->
                            <GroupBox Margin="0,0,0,8" Header="📋 Benutzer aus Vorlage">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Vorlage (sAMAccountName):" />
                                        <TextBox
                                            x:Name="TextBoxTemplateUser"
                                            Grid.Column="1"
                                            ToolTip="Anmeldename eines bestehenden Benutzers, dessen Abteilung, Firma, Titel, Adresse und Gruppenmitgliedschaften übernommen werden (keine privilegierten Gruppen)" />
                                    </Grid>
                                    <Grid Margin="0,4,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Anzahl:" />
                                        <TextBox
                                            x:Name="TextBoxTemplateCount"
                                            Grid.Column="1"
                                            Text="5"
                                            ToolTip="Anzahl der zu erstellenden Benutzer (1–500)" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonCreateFromTemplate"
                                        Margin="0,4,0,0"
                                        Content="📋 Benutzer aus Vorlage erstellen"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt Benutzer mit zufälligen Namen und den Attributen der Vorlage in der Test-OU (USERS). Passwort: Feld 'Initial-Passwort' oder zufälliges Passwort je Benutzer (nicht gespeichert)." />
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Expander>

                    <!--  2. Gruppen & Organisationsstruktur  -->
                    <Expander Header="🏢 Gruppen &amp; Organisationsstruktur" IsExpanded="False">
                        <StackPanel>
                            <GroupBox Margin="0,0,0,8" Header="📊 Automatische Gruppenerstellung">
                                <StackPanel>
                                    <CheckBox
                                        x:Name="CheckBoxCreateDepartmentGroups"
                                        Content="Abteilungsgruppen erstellen"
                                        IsChecked="True" />
                                    <CheckBox x:Name="CheckBoxCreateLocationGroups" Content="Standortgruppen erstellen" />
                                    <CheckBox x:Name="CheckBoxCreateJobTitleGroups" Content="Jobbezeichnungsgruppen erstellen" />
                                    <Button
                                        x:Name="ButtonCreateAutoGroups"
                                        Margin="0,4,0,0"
                                        Content="🏗️ Gruppen aus Benutzern erstellen"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt Gruppen basierend auf Benutzerattributen" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="🔗 Erweiterte Gruppenstrukturen">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxGroupHierarchy">
                                        <ComboBoxItem Content="Flache Struktur" IsSelected="True" />
                                        <ComboBoxItem Content="2-stufige Hierarchie" />
                                        <ComboBoxItem Content="3-stufige Hierarchie" />
                                        <ComboBoxItem Content="Vollständige Hierarchie" />
                                    </ComboBox>
                                    <CheckBox
                                        x:Name="CheckBoxNestedSecurity"
                                        Margin="0,4,0,0"
                                        Content="Als Sicherheitsgruppen anlegen (sonst Verteilergruppen)"
                                        IsChecked="True" />
                                    <Button
                                        x:Name="ButtonCreateNestedGroups"
                                        Margin="0,4,0,0"
                                        Content="🔗 Hierarchie erstellen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erstellt verschachtelte Test-Gruppen in der Test-OU (GROUPS). 'Vollständige Hierarchie' = 5 Ebenen (Region → Land → Stadt → Abteilung → Team)." />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="🏗️ OU-Struktur">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxOUStructure" ToolTip="Vorlage für die OU-Struktur">
                                        <ComboBoxItem Content="Kleine Firma (unter 50 MA)" IsSelected="True" />
                                        <ComboBoxItem Content="Mittlere Firma (50-500 MA)" />
                                        <ComboBoxItem Content="Große Firma (500+ MA)" />
                                        <ComboBoxItem Content="Konzern (Multi-Standort)" />
                                    </ComboBox>
                                    <Button
                                        x:Name="ButtonCreateOUStructure"
                                        Margin="0,4,0,0"
                                        Content="🏗️ OU-Struktur erstellen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erstellt eine verschachtelte OU-Struktur unterhalb der Ziel-OU (ohne Löschschutz, damit 'OUs löschen' sie wieder entfernen kann)" />
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Expander>

                    <!--  3. Computer & Geräte  -->
                    <Expander Header="💻 Computer &amp; Geräte" IsExpanded="False">
                        <StackPanel>
                            <GroupBox Margin="0,0,0,8" Header="🖥️ Computer erstellen">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Anzahl:" />
                                        <TextBox
                                            x:Name="TextBoxComputerCount"
                                            Grid.Column="1"
                                            Text="20" />
                                    </Grid>
                                    <ComboBox x:Name="ComboBoxComputerType" Margin="0,4,0,0">
                                        <ComboBoxItem Content="Arbeitsplatzrechner" IsSelected="True" />
                                        <ComboBoxItem Content="Notebooks" />
                                        <ComboBoxItem Content="Server" />
                                        <ComboBoxItem Content="Virtuelle Maschinen" />
                                    </ComboBox>
                                    <CheckBox
                                        x:Name="CheckBoxRandomComputerNames"
                                        Margin="0,4,0,0"
                                        Content="Zufällige Namen generieren"
                                        IsChecked="True" />
                                    <Button
                                        x:Name="ButtonCreateComputers"
                                        Margin="0,4,0,0"
                                        Content="💻 Computer erstellen"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt Computerkonten des gewählten Typs in der Test-OU (COMPUTERS)" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="⚙️ Dienstkonten">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxServiceType">
                                        <ComboBoxItem Content="SQL-Server-Dienst" IsSelected="True" />
                                        <ComboBoxItem Content="IIS-Anwendungspool" />
                                        <ComboBoxItem Content="Windows-Dienst" />
                                        <ComboBoxItem Content="Geplante Aufgabe" />
                                        <ComboBoxItem Content="Eigene Anwendung" />
                                    </ComboBox>
                                    <Grid Margin="0,4,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Anzahl:" />
                                        <TextBox
                                            x:Name="TextBoxServiceAccountCount"
                                            Grid.Column="1"
                                            Text="5" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonCreateServiceAccounts"
                                        Margin="0,4,0,0"
                                        Content="⚙️ Dienstkonten erstellen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erstellt Dienstkonten des gewählten Typs in der Test-OU (SERVICES)" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="🖨️ Drucker (printQueue)">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxPrinterType">
                                        <ComboBoxItem Content="Netzwerkdrucker" IsSelected="True" />
                                        <ComboBoxItem Content="Lokale Drucker" />
                                        <ComboBoxItem Content="Multifunktionsgeräte" />
                                    </ComboBox>
                                    <Grid Margin="0,4,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Anzahl:" />
                                        <TextBox
                                            x:Name="TextBoxPrinterCount"
                                            Grid.Column="1"
                                            Text="5"
                                            ToolTip="Anzahl der zu erstellenden Drucker-Objekte (1–200)" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonCreatePrinters"
                                        Margin="0,4,0,0"
                                        Content="🖨️ Drucker erstellen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erstellt veröffentlichte Drucker (printQueue-Objekte) in der Test-OU (RESOURCES). Es werden keine echten Druckwarteschlangen angelegt." />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="🔐 Computer-Sicherheitsdaten">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="BitLocker-Schlüssel für:" />
                                        <TextBox
                                            x:Name="TextBoxBitLockerComputerCount"
                                            Grid.Column="1"
                                            Text="10"
                                            ToolTip="Anzahl Computer" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonCreateBitLockerData"
                                        Margin="0,4,0,0"
                                        Content="🔐 BitLocker-Schlüssel generieren"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erzeugt simulierte BitLocker-Wiederherstellungsdaten für erstellte Computer und exportiert sie als CSV" />
                                    <CheckBox
                                        x:Name="CheckBoxBitLockerRandomSelection"
                                        Margin="0,2,0,0"
                                        Content="Computer zufällig auswählen (sonst die ersten X)" />

                                    <Grid Margin="0,8,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="LAPS für:" />
                                        <TextBox
                                            x:Name="TextBoxLAPSSystemCount"
                                            Grid.Column="1"
                                            Text="10"
                                            ToolTip="Anzahl Systeme" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonCreateLAPSData"
                                        Margin="0,4,0,0"
                                        Content="🔑 LAPS-Passwörter generieren"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Setzt LAPS-Testpasswörter für erstellte Computer und exportiert sie als CSV (Klartext – nach dem Test löschen!)" />
                                    <Grid Margin="0,2,0,0">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <CheckBox
                                            x:Name="CheckBoxLAPSIncludeServers"
                                            Grid.Column="0"
                                            Content="Server einbeziehen"
                                            IsChecked="True" />
                                        <CheckBox
                                            x:Name="CheckBoxLAPSIncludeWorkstations"
                                            Grid.Column="1"
                                            Content="Clients einbeziehen"
                                            IsChecked="True" />
                                    </Grid>
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Expander>

                    <!--  4. Test-Szenarien  -->
                    <Expander Header="🧪 Test-Szenarien" IsExpanded="False">
                        <StackPanel>
                            <GroupBox Margin="0,0,0,8" Header="📊 Komplette Test-Umgebung">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxTestDataSize">
                                        <ComboBoxItem Content="Klein (10-50 Objekte)" IsSelected="True" />
                                        <ComboBoxItem Content="Mittel (50-500 Objekte)" />
                                        <ComboBoxItem Content="Groß (500-5000 Objekte)" />
                                        <ComboBoxItem Content="Enterprise (5000+ Objekte)" />
                                    </ComboBox>
                                    <CheckBox
                                        x:Name="CheckBoxRealisticData"
                                        Margin="0,4,0,0"
                                        Content="Realistische Verteilung"
                                        IsChecked="True" />
                                    <CheckBox
                                        x:Name="CheckBoxHistoricalData"
                                        Margin="0,2,0,0"
                                        Content="Historische Erstellungsdaten simulieren (in Beschreibung)" />
                                    <Button
                                        x:Name="ButtonCreateTestDataSet"
                                        Margin="0,4,0,0"
                                        Content="🧪 Test-Umgebung erstellen"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt komplette Test-Umgebung mit Benutzern, Gruppen und Computern" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="🎭 Chaos-Test Daten">
                                <StackPanel>
                                    <CheckBox x:Name="CheckBoxInvalidData" Content="Ungültige E-Mail-Adressen" />
                                    <CheckBox x:Name="CheckBoxMissingAttributes" Content="Fehlende Attribute" />
                                    <CheckBox x:Name="CheckBoxDuplicateEntries" Content="Doppelte Einträge" />
                                    <CheckBox x:Name="CheckBoxSpecialCharacters" Content="Sonderzeichen und Unicode in Namen" />
                                    <Button
                                        x:Name="ButtonActivateChaosMode"
                                        Margin="0,4,0,0"
                                        Content="🎭 Chaos-Daten erstellen"
                                        Style="{StaticResource DangerButton}"
                                        ToolTip="Erstellt absichtlich fehlerhafte Test-Benutzer in der Test-OU (USERS) für Fehlerbehandlungs-Tests" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="⏱️ Performance-Test">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="Benutzer:" />
                                        <TextBox
                                            x:Name="TextBoxPerformanceCount"
                                            Grid.Column="1"
                                            Text="100"
                                            ToolTip="Anzahl der Test-Benutzer (1–5000)" />
                                        <Label Grid.Column="2" Content="Batchgröße:" />
                                        <TextBox
                                            x:Name="TextBoxBatchSize"
                                            Grid.Column="3"
                                            Text="10"
                                            ToolTip="Anzahl Benutzer pro Messintervall" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonStartPerformanceTest"
                                        Margin="0,4,0,0"
                                        Content="⏱️ Performance-Test starten"
                                        Style="{StaticResource WarningButton}"
                                        ToolTip="Misst die Erstellungsgeschwindigkeit von Test-Benutzern (Test-OU USERS). Die Benutzer werden nachverfolgt und können über '🗑️ Löschen' (Erstellte Benutzer verwalten) entfernt werden; Messwerte werden als CSV exportiert." />
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Expander>

                    <!--  5. Sicherheit & Compliance  -->
                    <Expander Header="🔐 Sicherheit &amp; Compliance" IsExpanded="False">
                        <StackPanel>
                            <GroupBox Margin="0,0,0,8" Header="🔒 Passwort-Richtlinien">
                                <StackPanel>
                                    <CheckBox x:Name="CheckBoxSimulatePasswordHistory" Content="Passwort-Historie simulieren" />
                                    <CheckBox x:Name="CheckBoxCreateLockedAccounts" Content="Gesperrte Konten erstellen (10 %)" />
                                    <CheckBox x:Name="CheckBoxExpiredPasswords" Content="Abgelaufene Passwörter" />
                                    <Button
                                        x:Name="ButtonApplyPasswordPolicies"
                                        Margin="0,4,0,0"
                                        Content="🔒 Passwort-Richtlinien anwenden"
                                        Style="{StaticResource WarningButton}"
                                        ToolTip="Wendet die gewählten Passwort-Szenarien auf alle vom Tool erstellten Benutzer an" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="⏰ Anmeldezeiten">
                                <StackPanel>
                                    <TextBlock
                                        FontSize="11"
                                        Foreground="{StaticResource TextSecondaryBrush}"
                                        Text="Erlaubt die Anmeldung nur Mo–Fr 08:00–17:00 Uhr (lokale Zeit)."
                                        TextWrapping="Wrap" />
                                    <Button
                                        x:Name="ButtonSetTimeRestrictions"
                                        Margin="0,4,0,0"
                                        Content="⏰ Anmeldezeiten setzen"
                                        Style="{StaticResource WarningButton}"
                                        ToolTip="Setzt logonHours (Mo–Fr 08:00–17:00 Uhr) bei allen vom Tool erstellten Benutzern" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="👑 RBAC-Rollen">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxRBACRoles">
                                        <ComboBoxItem Content="Helpdesk Operator" IsSelected="True" />
                                        <ComboBoxItem Content="Server Operator" />
                                        <ComboBoxItem Content="Backup Operator" />
                                        <ComboBoxItem Content="Account Operator" />
                                        <ComboBoxItem Content="Print Operator" />
                                    </ComboBox>
                                    <Button
                                        x:Name="ButtonCreateRBACRoles"
                                        Margin="0,4,0,0"
                                        Content="👑 RBAC-Struktur erstellen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Erstellt 5 Rollengruppen mit Berechtigungs-Untergruppen in der Test-OU (GROUPS)" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="⚠️ Kritische Einstellungen">
                                <StackPanel>
                                    <CheckBox x:Name="CheckBoxPwdNotExpires" Content="Passwort läuft nicht ab" />
                                    <CheckBox x:Name="CheckBoxRevPwd" Content="Umkehrbare Verschlüsselung" />
                                    <Button
                                        x:Name="ButtonApplySecuritySettings"
                                        Margin="0,4,0,0"
                                        Content="⚠️ Anwenden"
                                        Style="{StaticResource DangerButton}"
                                        ToolTip="WARNUNG: Kritische Einstellungen!" />
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Expander>

                    <!--  6. Erweiterte Features  -->
                    <Expander Header="🚀 Erweiterte Features" IsExpanded="False">
                        <StackPanel>
                            <GroupBox Margin="0,0,0,8" Header="🔧 Zusätzliche Test-Features">
                                <StackPanel>
                                    <CheckBox x:Name="CheckBoxCreateDNSEntries" Content="DNS-Einträge simulieren (CSV)" />
                                    <CheckBox x:Name="CheckBoxCreateSPNs" Content="Service Principal Names (SPNs)" />
                                    <CheckBox x:Name="CheckBoxDocumentFSMO" Content="FSMO-Rollen dokumentieren" />
                                    <Button
                                        x:Name="ButtonCreateAdvancedFeatures"
                                        Margin="0,4,0,0"
                                        Content="🚀 Erweiterte Features ausführen"
                                        Style="{StaticResource ModernButton}"
                                        ToolTip="Simulierte DNS-Liste (CSV), SPNs für erstellte Dienstkonten und FSMO-Dokumentation (TXT)" />
                                </StackPanel>
                            </GroupBox>
                        </StackPanel>
                    </Expander>


                </StackPanel>
            </ScrollViewer>
        </Grid>

        <!--  Footer / Status  -->
        <Border
            Grid.Row="2"
            Padding="16,8"
            Background="White"
            BorderBrush="{StaticResource BorderBrush}"
            BorderThickness="0,1,0,0">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="*" />
                    <ColumnDefinition Width="Auto" />
                    <ColumnDefinition Width="Auto" />
                </Grid.ColumnDefinitions>

                <StackPanel Grid.Column="0" Orientation="Horizontal">
                    <Border
                        Width="12"
                        Height="12"
                        Margin="0,0,6,0"
                        Background="{StaticResource SuccessBrush}"
                        CornerRadius="6">
                        <Ellipse
                            Width="4"
                            Height="4"
                            HorizontalAlignment="Center"
                            VerticalAlignment="Center"
                            Fill="White" />
                    </Border>
                    <TextBlock
                        x:Name="TextBlockStatus"
                        VerticalAlignment="Center"
                        FontSize="12"
                        FontWeight="Medium"
                        Foreground="{StaticResource TextPrimaryBrush}"
                        Text="Bereit." />
                </StackPanel>

                <TextBlock
                    Grid.Column="3"
                    VerticalAlignment="Center"
                    FontSize="11"
                    Foreground="{StaticResource TextSecondaryBrush}"
                    Text="$($script:AppConfig.Author)" />
            </Grid>
        </Border>
    </Grid>
</Window>
"@
#endregion

#region Logging und Hilfsfunktionen
function Write-AppLog {
    param(
        [string]$Message,
        [string]$Level = "INFO" # INFO, WARN, ERROR, DEBUG, SUCCESS
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Write-Verbose -Message $logEntry # Konsolenausgabe bei Start mit -Verbose bzw. $VerbosePreference = 'Continue'

    if ($script:Window -and $script:GuiControls.TextBlockStatus) {
        $script:GuiControls.TextBlockStatus.Text = $Message
    }

    # In Datei loggen (Logs-Unterordner im Skriptverzeichnis)
    try {
        if (-not $script:LogDirectoryReady) {
            if (-not (Test-Path -LiteralPath $script:AppConfig.LogDirectory -PathType Container)) {
                New-Item -Path $script:AppConfig.LogDirectory -ItemType Directory -Force | Out-Null
            }
            $script:LogDirectoryReady = $true
        }
        [System.IO.File]::AppendAllText($script:AppConfig.LogFilePath, $logEntry + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($true))
    } catch {
        # Fehler beim Logging nicht weiterwerfen, um Hauptfunktionalität nicht zu beeinträchtigen
        Write-Warning -Message "Fehler beim Schreiben in Logdatei: $($_.Exception.Message)"
    }
}

function Get-ExportFilePath {
    <#
    .SYNOPSIS
    Liefert einen Pfad im Export-Ordner des Skripts (wird bei Bedarf angelegt)
    #>
    param([Parameter(Mandatory = $true)][string]$FileName)

    $exportDir = $script:AppConfig.ExportDirectory
    if (-not (Test-Path -LiteralPath $exportDir -PathType Container)) {
        New-Item -Path $exportDir -ItemType Directory -Force | Out-Null
    }
    return (Join-Path $exportDir $FileName)
}

function ConvertTo-ADFilterValue {
    <#
    .SYNOPSIS
    Maskiert einen Wert für die Verwendung in einem -Filter-String (einfache Anführungszeichen verdoppeln)
    #>
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Get-CachedADDomain {
    <#
    .SYNOPSIS
    Liefert das AD-Domänenobjekt (einmalig abgefragt und zwischengespeichert)
    #>
    if (-not $script:DomainInfoCache) {
        $script:DomainInfoCache = Get-ADDomain -ErrorAction Stop
    }
    return $script:DomainInfoCache
}

function ConvertTo-IntOrZero {
    <#
    .SYNOPSIS
    Wandelt eine GUI-Eingabe sicher in eine Ganzzahl um (ungültige Eingaben ergeben 0 statt einer Ausnahme)
    #>
    param($Value)
    $parsed = 0
    if ([int]::TryParse(([string]$Value).Trim(), [ref]$parsed)) { return $parsed }
    return 0
}

function Get-CryptoRandomInt {
    <#
    .SYNOPSIS
    Liefert eine kryptografisch sichere Zufallszahl im Bereich [0, MaxExclusive)
    #>
    param([Parameter(Mandatory = $true)][int]$MaxExclusive)

    if ($MaxExclusive -le 0) { throw "MaxExclusive muss größer als 0 sein." }
    $bytes = New-Object byte[] 4
    # Rejection Sampling verhindert Modulo-Bias
    $limit = [uint32]::MaxValue - ([uint32]::MaxValue % [uint32]$MaxExclusive)
    do {
        $script:CryptoRng.GetBytes($bytes)
        $value = [System.BitConverter]::ToUInt32($bytes, 0)
    } while ($value -ge $limit)
    return [int]($value % [uint32]$MaxExclusive)
}

function ConvertTo-SecurePasswordString {
    <#
    .SYNOPSIS
    Zentrale Umwandlung eines Klartext-Passworts in einen SecureString (ohne ConvertTo-SecureString -AsPlainText).
    Das Passwort wird weder geloggt noch exportiert.
    #>
    param([Parameter(Mandatory = $true)][string]$PlainText)

    $secure = New-Object System.Security.SecureString
    foreach ($ch in $PlainText.ToCharArray()) { $secure.AppendChar($ch) }
    $secure.MakeReadOnly()
    return $secure
}

function Get-RandomSecurePassword {
    <#
    .SYNOPSIS
    Erzeugt ein kryptografisch zufälliges Passwort direkt als SecureString
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [string]$Complexity = "Mittel (12 Zeichen + Symbole)",
        [int]$Length = 0,
        [bool]$IncludeNumbers = $true,
        [bool]$IncludeSymbols = $true,
        [bool]$ExcludeAmbiguous = $true
    )
    $plainText = Get-RandomPasswordText -Complexity $Complexity -Length $Length -IncludeNumbers $IncludeNumbers -IncludeSymbols $IncludeSymbols -ExcludeAmbiguous $ExcludeAmbiguous
    return (ConvertTo-SecurePasswordString -PlainText $plainText)
}

function Get-InitialUserPassword {
    <#
    .SYNOPSIS
    Liefert das im GUI eingegebene Initial-Passwort (SecureString) oder ein zufälliges Passwort pro Benutzer
    #>
    [CmdletBinding()]
    [OutputType([System.Security.SecureString])]
    param(
        [string]$Complexity = "Komplex (16 Zeichen + Spezial)",
        [bool]$IncludeNumbers = $true,
        [bool]$IncludeSymbols = $true,
        [bool]$ExcludeAmbiguous = $true
    )
    $passwordBox = $script:GuiControls.PasswordBoxInitialPassword
    if ($passwordBox -and $passwordBox.SecurePassword.Length -gt 0) {
        return $passwordBox.SecurePassword
    }
    return (Get-RandomSecurePassword -Complexity $Complexity -IncludeNumbers $IncludeNumbers -IncludeSymbols $IncludeSymbols -ExcludeAmbiguous $ExcludeAmbiguous)
}

function ConvertTo-CountryCode {
    <#
    .SYNOPSIS
    Wandelt gängige Ländernamen in ISO-3166 2-Buchstaben-Codes um (AD-Attribut 'c')
    #>
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    switch ($Value.Trim()) {
        { $_ -in @('Germany', 'Deutschland', 'DEU') } { return 'DE' }
        { $_ -in @('United States', 'USA', 'United States of America') } { return 'US' }
        { $_ -in @('United Kingdom', 'UK', 'GBR', 'Great Britain') } { return 'GB' }
        { $_ -in @('Austria', 'Österreich', 'AUT') } { return 'AT' }
        { $_ -in @('Switzerland', 'Schweiz', 'CHE') } { return 'CH' }
        { $_ -in @('France', 'Frankreich', 'FRA') } { return 'FR' }
    }
    return $Value
}

function Resolve-ADUserReference {
    <#
    .SYNOPSIS
    Löst einen Benutzer-Verweis (DN, SamAccountName, UPN oder Mail) zum DistinguishedName auf (mit Cache)
    #>
    param(
        [string]$Reference,
        [hashtable]$Cache
    )
    if ([string]::IsNullOrWhiteSpace($Reference)) { return $null }
    if ($Cache -and $Cache.ContainsKey($Reference)) { return $Cache[$Reference] }

    $escaped = ConvertTo-ADFilterValue -Value $Reference
    $dn = $null
    try {
        $found = Get-ADUser -Filter "DistinguishedName -eq '$escaped' -or SamAccountName -eq '$escaped' -or UserPrincipalName -eq '$escaped' -or mail -eq '$escaped'" -ErrorAction Stop |
            Select-Object -First 1
        if ($found) { $dn = $found.DistinguishedName }
    } catch {
        Write-AppLog "Benutzer-Verweis '$Reference' konnte nicht aufgelöst werden: $($_.Exception.Message)" -Level "DEBUG"
    }
    if ($Cache) { $Cache[$Reference] = $dn }
    return $dn
}

function Invoke-UiRefresh {
    <#
    .SYNOPSIS
    Verarbeitet ausstehende WPF-Dispatcher-Nachrichten, damit die GUI während langer Vorgänge aktualisiert wird
    #>
    try {
        if (-not $script:Window) { return }
        $frame = New-Object System.Windows.Threading.DispatcherFrame
        $callback = [System.Windows.Threading.DispatcherOperationCallback] {
            param($f)
            $f.Continue = $false
            return $null
        }
        [void]$script:Window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, $callback, $frame)
        [System.Windows.Threading.Dispatcher]::PushFrame($frame)
    } catch {
        Write-AppLog "UI-Aktualisierung fehlgeschlagen: $($_.Exception.Message)" -Level "DEBUG"
    }
}

function Set-UiBusyState {
    <#
    .SYNOPSIS
    Sperrt bzw. entsperrt die Bedienoberfläche während eines laufenden Vorgangs (verhindert Doppelklicks/Reentrancy)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([bool]$Busy)
    if (-not $PSCmdlet.ShouldProcess("Bedienoberfläche", $(if ($Busy) { "Sperren" } else { "Entsperren" }))) { return }
    try {
        if ($script:Window -and $script:Window.Content) {
            $script:Window.Content.IsHitTestVisible = -not $Busy
        }
        [System.Windows.Input.Mouse]::OverrideCursor = if ($Busy) { [System.Windows.Input.Cursors]::Wait } else { $null }
    } catch {
        Write-AppLog "UI-Status konnte nicht gesetzt werden: $($_.Exception.Message)" -Level "DEBUG"
    }
}

function Invoke-GuiAction {
    <#
    .SYNOPSIS
    Führt eine GUI-Aktion mit zentraler Fehlerbehandlung und Reentrancy-Schutz aus
    #>
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    if ($script:IsBusy) {
        Write-AppLog "Es läuft bereits ein Vorgang - bitte warten." -Level "WARN"
        return
    }
    $script:IsBusy = $true
    try {
        & $Action
    } catch {
        Write-AppLog "Unbehandelter Fehler: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Es ist ein Fehler aufgetreten:`n$($_.Exception.Message)", "Fehler", "OK", "Error") | Out-Null
    } finally {
        Hide-Progress
        $script:IsBusy = $false
    }
}

function ConvertTo-NormalizedSamAccountName {
    <#
    .SYNOPSIS
    Normalisiert einen SamAccountName für Active Directory-Kompatibilität.

    .DESCRIPTION
    Diese Funktion bereinigt und normalisiert einen SamAccountName, um sicherzustellen,
    dass er den AD-Anforderungen entspricht:
    - Keine Umlaute/Akzente (ä→a, ö→o, ü→u, ß→ss, é→e, etc.)
    - Keine Leerzeichen (ersetzt durch Unterstriche)
    - Keine Sonderzeichen (entfernt oder ersetzt)
    - Nur ASCII-Zeichen (a-z, A-Z, 0-9, -, _)
    - Maximale Länge von 20 Zeichen
    - Eindeutigkeit durch Counter bei Duplikaten

    .PARAMETER SamAccountName
    Der ursprüngliche SamAccountName aus der CSV-Datei

    .PARAMETER ExistingNames
    HashSet bestehender Namen zur Duplikatsvermeidung

    .EXAMPLE
    ConvertTo-NormalizedSamAccountName -SamAccountName "müller.johann" -ExistingNames $existingNames
    # Gibt zurück: "mueller.johann"

    .EXAMPLE
    ConvertTo-NormalizedSamAccountName -SamAccountName "mauch schlauchin" -ExistingNames $existingNames
    # Gibt zurück: "mauch_schlauchin"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SamAccountName,

        [Parameter(Mandatory=$false)]
        [System.Collections.Generic.HashSet[string]]$ExistingNames
    )

    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        Write-AppLog "ConvertTo-NormalizedSamAccountName: Leerer SamAccountName übergeben" -Level "ERROR"
        return "user" + (Get-Random -Minimum 1000 -Maximum 9999)
    }

    # 1. Zu Lowercase konvertieren
    $normalized = $SamAccountName.ToLower()

    # 2. Umlaute und Akzente ersetzen
    $replacements = @{
        'ä' = 'ae'; 'ö' = 'oe'; 'ü' = 'ue'; 'ß' = 'ss'
        'à' = 'a'; 'á' = 'a'; 'â' = 'a'; 'ã' = 'a'; 'å' = 'a'; 'æ' = 'ae'
        'è' = 'e'; 'é' = 'e'; 'ê' = 'e'; 'ë' = 'e'
        'ì' = 'i'; 'í' = 'i'; 'î' = 'i'; 'ï' = 'i'
        'ò' = 'o'; 'ó' = 'o'; 'ô' = 'o'; 'õ' = 'o'; 'ø' = 'o'
        'ù' = 'u'; 'ú' = 'u'; 'û' = 'u'
        'ý' = 'y'; 'ÿ' = 'y'
        'ñ' = 'n'; 'ç' = 'c'
        'ą' = 'a'; 'ć' = 'c'; 'ę' = 'e'; 'ł' = 'l'; 'ń' = 'n'; 'ś' = 's'; 'ź' = 'z'; 'ż' = 'z'
    }

    foreach ($char in $replacements.Keys) {
        $normalized = $normalized -replace [regex]::Escape($char), $replacements[$char]
    }

    # 3. Leerzeichen durch Unterstriche ersetzen
    $normalized = $normalized -replace '\s+', '_'

    # 4. Sonderzeichen entfernen oder ersetzen
    $normalized = $normalized -replace "'", ''  # Apostrophe entfernen
    $normalized = $normalized -replace '[^\w.-]', ''  # Nur Buchstaben, Zahlen, Punkte, Bindestriche, Unterstriche

    # 5. Mehrfache Punkte/Unterstriche/Bindestriche zusammenfassen
    $normalized = $normalized -replace '\.{2,}', '.'
    $normalized = $normalized -replace '_{2,}', '_'
    $normalized = $normalized -replace '-{2,}', '-'

    # 6. Führende/nachfolgende Sonderzeichen entfernen
    $normalized = $normalized.Trim('.', '_', '-')

    # 7. Nicht-ASCII-Zeichen durch Platzhalter ersetzen (für chinesische, japanische, koreanische, thai Zeichen)
    $normalized = $normalized -replace '[^\x00-\x7F]', 'x'

    # 8. Falls leer, Fallback verwenden
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        $normalized = "user" + (Get-Random -Minimum 1000 -Maximum 9999)
        Write-AppLog "SamAccountName war nach Normalisierung leer, verwende Fallback: $normalized" -Level "WARN"
    }

    # 9. Auf 20 Zeichen kürzen (AD-Limit)
    if ($normalized.Length -gt 20) {
        $normalized = $normalized.Substring(0, 17) + (Get-Random -Minimum 100 -Maximum 999)
        Write-AppLog "SamAccountName zu lang, gekürzt auf: $normalized" -Level "DEBUG"
    }

    # 10. Eindeutigkeit sicherstellen
    if ($ExistingNames) {
        $originalNormalized = $normalized
        $counter = 1

        while ($ExistingNames.Contains($normalized)) {
            $suffix = $counter.ToString()
            if (($originalNormalized.Length + $suffix.Length) -le 20) {
                $normalized = $originalNormalized + $suffix
            } else {
                $baseLength = 20 - $suffix.Length
                $normalized = $originalNormalized.Substring(0, $baseLength) + $suffix
            }
            $counter++

            # Sicherheitsbremse gegen Endlosschleife
            if ($counter -gt 999) {
                $normalized = "user" + (Get-Random -Minimum 1000 -Maximum 9999)
                break
            }
        }

        # Zur Liste hinzufügen
        $ExistingNames.Add($normalized) | Out-Null

        if ($normalized -ne $originalNormalized) {
            Write-AppLog "SamAccountName Duplikat vermieden: '$originalNormalized' → '$normalized'" -Level "DEBUG"
        }
    }

    Write-AppLog "SamAccountName normalisiert: '$SamAccountName' → '$normalized'" -Level "DEBUG"
    return $normalized
}

function Initialize-GuiControl {
    <#
    .SYNOPSIS
    Sammelt alle benannten GUI-Controls aus dem XAML-Window

    .DESCRIPTION
    Die Namen werden direkt aus der XAML-Definition gelesen (alle x:Name außerhalb von ControlTemplates),
    damit Code und Oberfläche nicht auseinanderlaufen. Die Controls werden in $script:GuiControls abgelegt.
    #>
    Write-AppLog "Sammle GUI-Controls..." -Level "INFO"

    $xamlDocument = [xml]$XAML
    $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xamlDocument.NameTable)
    $namespaceManager.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $namedNodes = $xamlDocument.SelectNodes('//*[@x:Name][not(ancestor::*[local-name()="ControlTemplate"])]', $namespaceManager)

    foreach ($node in $namedNodes) {
        $controlName = $node.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        $control = $script:Window.FindName($controlName)
        if ($null -ne $control) {
            $script:GuiControls[$controlName] = $control
        } else {
            Write-AppLog "Control nicht gefunden: $controlName" -Level "WARN"
        }
    }

    Write-AppLog "$($script:GuiControls.Count) Controls erfolgreich gesammelt" -Level "SUCCESS"
}

#region Benutzer-Erstellung & Verwaltung - Erweiterte Funktionen

# Vordefinierte Listen für Zufallsdaten
$script:RandomDataLists = @{
    FirstNames = @(
        "Max", "Anna", "Felix", "Sophie", "Leon", "Marie", "Paul", "Emma", "Ben", "Mia",
        "Jonas", "Hannah", "Elias", "Emilia", "Noah", "Lena", "Luis", "Lea", "Finn", "Clara",
        "Luca", "Johanna", "David", "Laura", "Tim", "Sarah", "Julian", "Lisa", "Tom", "Julia"
    )
    LastNames = @(
        "Mueller", "Schmidt", "Schneider", "Fischer", "Weber", "Meyer", "Wagner", "Becker",
        "Schulz", "Hoffmann", "Schaefer", "Koch", "Bauer", "Richter", "Klein", "Wolf",
        "Schroeder", "Neumann", "Schwarz", "Zimmermann", "Braun", "Krueger", "Hofmann",
        "Hartmann", "Lange", "Schmitt", "Werner", "Schmitz", "Krause", "Meier"
    )
    Departments = @(
        "IT", "Human Resources", "Finance", "Marketing", "Sales", "Operations",
        "Engineering", "Support", "Legal", "Administration", "Research", "Development",
        "Customer Service", "Quality Assurance", "Product Management", "Logistics"
    )
    Cities = @(
        "Berlin", "Hamburg", "Munich", "Cologne", "Frankfurt", "Stuttgart", "Düsseldorf",
        "Dortmund", "Essen", "Leipzig", "Bremen", "Dresden", "Hanover", "Nuremberg"
    )
    Streets = @(
        "Hauptstrasse", "Bahnhofstrasse", "Gartenstrasse", "Schulstrasse", "Kirchgasse",
        "Ringstrasse", "Lindenallee", "Bergstrasse", "Waldweg", "Marktplatz"
    )
    JobTitles = @(
        "Manager", "Developer", "Administrator", "Analyst", "Consultant", "Engineer",
        "Specialist", "Coordinator", "Assistant", "Director", "Supervisor", "Technician"
    )
}

function Get-RandomPasswordText {
    <#
    .SYNOPSIS
    Generiert sichere Passwörter mit verschiedenen Komplexitätsstufen

    .DESCRIPTION
    Erstellt Passwörter basierend auf ausgewählter Komplexität und Optionen.
    Verwendet einen kryptografisch sicheren Zufallszahlengenerator (RandomNumberGenerator).
    Das erzeugte Passwort wird niemals geloggt.
    #>
    param(
        [string]$Complexity = "Mittel",
        [bool]$IncludeNumbers = $true,
        [bool]$IncludeSymbols = $true,
        [bool]$ExcludeAmbiguous = $true,
        [int]$Length = 0 # 0 = Länge aus Komplexität ableiten
    )

    # Zeichensätze definieren
    $lowercase = 'abcdefghijklmnopqrstuvwxyz'
    $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    $numbers = '0123456789'
    $symbols = '!@#$%^&*()_+-=[]{}|;:,.<>?'

    # Mehrdeutige Zeichen
    $ambiguous = 'il1Lo0O'

    # Länge basierend auf Komplexität
    $targetLength = switch ($Complexity) {
        "Einfach (8 Zeichen)" { 8 }
        "Mittel (12 Zeichen + Symbole)" { 12 }
        "Komplex (16 Zeichen + Spezial)" { 16 }
        "Hochsicher (20+ Zeichen)" { 24 }
        default { 12 }
    }
    if ($Length -gt 0) { $targetLength = $Length }

    $useSymbols = $IncludeSymbols -and $Complexity -ne "Einfach (8 Zeichen)"

    # Mehrdeutige Zeichen entfernen
    if ($ExcludeAmbiguous) {
        foreach ($char in $ambiguous.ToCharArray()) {
            $lowercase = $lowercase.Replace($char.ToString(), '')
            $uppercase = $uppercase.Replace($char.ToString(), '')
            $numbers = $numbers.Replace($char.ToString(), '')
        }
    }

    # Basis-Zeichensatz erweitern
    $charSet = $lowercase + $uppercase
    if ($IncludeNumbers) { $charSet += $numbers }
    if ($useSymbols) { $charSet += $symbols }

    # Mindestens ein Zeichen aus jeder gewählten Kategorie sicherstellen
    $passwordChars = New-Object System.Collections.Generic.List[char]
    $passwordChars.Add($lowercase[(Get-CryptoRandomInt -MaxExclusive $lowercase.Length)])
    $passwordChars.Add($uppercase[(Get-CryptoRandomInt -MaxExclusive $uppercase.Length)])
    if ($IncludeNumbers) { $passwordChars.Add($numbers[(Get-CryptoRandomInt -MaxExclusive $numbers.Length)]) }
    if ($useSymbols) { $passwordChars.Add($symbols[(Get-CryptoRandomInt -MaxExclusive $symbols.Length)]) }

    # Rest auffüllen
    while ($passwordChars.Count -lt $targetLength) {
        $passwordChars.Add($charSet[(Get-CryptoRandomInt -MaxExclusive $charSet.Length)])
    }

    # Passwort mischen (Fisher-Yates mit kryptografischem Zufall)
    $passwordArray = $passwordChars.ToArray()
    for ($i = $passwordArray.Length - 1; $i -gt 0; $i--) {
        $j = Get-CryptoRandomInt -MaxExclusive ($i + 1)
        $tmp = $passwordArray[$i]
        $passwordArray[$i] = $passwordArray[$j]
        $passwordArray[$j] = $tmp
    }

    Write-AppLog "Passwort generiert (Komplexität: $Complexity, Länge: $($passwordArray.Length))" -Level "DEBUG"
    return (-join $passwordArray)
}

#endregion
#endregion

#region Event Handler und GUI Logik

function Import-CsvData {
    $csvPath = $script:GuiControls.TextBoxCsvPath.Text
    if ([string]::IsNullOrWhiteSpace($csvPath) -or -not (Test-Path -LiteralPath $csvPath -PathType Leaf)) {
        Write-AppLog "CSV-Datei nicht gefunden: $csvPath" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Die angegebene CSV-Datei wurde nicht gefunden: `n$csvPath", "Fehler", "OK", "Error")
        return
    }
    try {
        $script:CsvData = @(Import-Csv -LiteralPath $csvPath -Encoding UTF8)
        $script:GuiControls.DataGridCsvContent.ItemsSource = $script:CsvData
        Write-AppLog "CSV-Datei erfolgreich geladen: $csvPath ($($script:CsvData.Count) Einträge)" -Level "SUCCESS"

        # Attribute für Auswahl-Checkboxes populieren
        $script:GuiControls.StackPanelAttributeSelection.Children.Clear()
        $csvHeaders = $script:CsvData | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

        foreach ($attrInfo in $script:SelectableADAttributes) {
            if ($csvHeaders -contains $attrInfo.CsvHeader) {
                $checkBox = New-Object System.Windows.Controls.CheckBox
                $checkBox.Content = "$($attrInfo.Name) (aus $($attrInfo.CsvHeader))"
                $checkBox.Tag = $attrInfo # Store the attribute info object
                if ($attrInfo.Required -or @("GivenName", "Surname", "DisplayName", "UserPrincipalName") -contains $attrInfo.Name) {
                    $checkBox.IsChecked = $true # Pre-select required and common attributes
                }
                $script:GuiControls.StackPanelAttributeSelection.Children.Add($checkBox) | Out-Null
            }
        }
    } catch {
        Write-AppLog "Fehler beim Laden der CSV-Datei: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Laden der CSV-Datei:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-ADUserFromCsv {
    <#
    .SYNOPSIS
    Erstellt Benutzer aus der geladenen CSV-Datei
    .DESCRIPTION
    Die in diesem Lauf erstellten Benutzer werden zusätzlich (mit CSV-Zeilennummer) in $script:LastCsvImportUsers
    gespeichert. 'Attribute befüllen' arbeitet ausschließlich mit dieser Liste; jeder neue CSV-Import ersetzt sie.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if (-not $script:CsvData) {
        Write-AppLog "Bitte zuerst eine CSV-Datei laden." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte laden Sie zuerst eine CSV-Datei.", "Hinweis", "OK", "Warning")
        return
    }

    # AD-Verbindung prüfen
    if (-not (Test-ADConnection)) {
        return
    }

    $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
    if (-not $targetOU) {
        Write-AppLog "Bitte geben Sie eine Ziel-OU an." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Ziel-OU (Distinguished Name) an.", "Hinweis", "OK", "Warning")
        return
    }

    # OU validieren
    if (-not (Test-TargetOU -TargetOU $targetOU)) {
        return
    }

    $numUsersToCreateText = $script:GuiControls.TextBoxNumUsersToCreate.Text
    $numUsersToCreate = 0
    if ([string]::IsNullOrWhiteSpace($numUsersToCreateText)) {
        $numUsersToCreate = @($script:CsvData).Count
    } elseif (-not [int]::TryParse($numUsersToCreateText.Trim(), [ref]$numUsersToCreate)) {
        Write-AppLog "Ungültige Anzahl: '$numUsersToCreateText'" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Zahl für die Anzahl der Benutzer ein.", "Hinweis", "OK", "Warning")
        return
    }

    if ($numUsersToCreate -le 0) {
        Write-AppLog "Anzahl der zu erstellenden Benutzer muss größer als 0 sein." -Level "WARN"
        return
    }

    $selectedAttributesCheckboxes = $script:GuiControls.StackPanelAttributeSelection.Children | Where-Object {$_.IsChecked -eq $true}
    if ($selectedAttributesCheckboxes.Count -eq 0) {
        Write-AppLog "Bitte wählen Sie mindestens ein Attribut für die Benutzererstellung aus." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein Attribut für die Benutzererstellung aus.", "Hinweis", "OK", "Warning")
        return
    }

    # Sicherstellen, dass SamAccountName ausgewählt ist, wenn es in der CSV existiert
    $samAttrInfo = $script:SelectableADAttributes | Where-Object {$_.Name -eq "SamAccountName"}
    $samSelected = $selectedAttributesCheckboxes | ForEach-Object { $_.Tag } | Where-Object {$_.Name -eq "SamAccountName"}
    if (($script:CsvData[0].PSObject.Properties.Name -contains $samAttrInfo.CsvHeader) -and (-not $samSelected)) {
         Write-AppLog "Das Attribut 'SamAccountName' muss ausgewählt sein, wenn es in der CSV existiert und für die Erstellung verwendet werden soll." -Level "WARN"
        [System.Windows.MessageBox]::Show("Das Attribut 'SamAccountName' (aus CSV-Spalte '$($samAttrInfo.CsvHeader)') ist für die Benutzererstellung erforderlich und muss ausgewählt werden.", "Hinweis", "OK", "Warning")
        return
    }

    if (-not $PSCmdlet.ShouldProcess($targetOU, "Bis zu $numUsersToCreate Benutzer aus CSV erstellen")) { return }

    # Fortschrittsanzeige aktivieren
    Show-Progress -Text "Starte Benutzererstellung..." -Value 0

    Write-AppLog "Starte Erstellung von bis zu $numUsersToCreate AD-Benutzern..." -Level "INFO"
    # Nur die Zuordnung für 'Attribute befüllen' wird ersetzt; die Bereinigungsliste $script:CreatedUsers bleibt erhalten
    $script:LastCsvImportUsers.Clear()
    $createdCount = 0
    $errorCount = 0

    # HashSet für SamAccountName-Duplikate zur Laufzeit
    $usedSamAccountNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $usedUpns = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $managerCache = @{}
    $usesRandomPasswords = -not ($script:GuiControls.PasswordBoxInitialPassword -and $script:GuiControls.PasswordBoxInitialPassword.SecurePassword.Length -gt 0)
    $csvRows = @($script:CsvData)

    for ($i = 0; $i -lt $csvRows.Count; $i++) {
        if ($createdCount -ge $numUsersToCreate) { break }

        $csvRow = $csvRows[$i]
        $userParams = @{
            Path    = $targetOU
            Enabled = $true
            ChangePasswordAtLogon = $script:AppConfig.EnablePasswordChange # Wert aus globaler Konfiguration verwenden
            AccountPassword = (Get-InitialUserPassword) # GUI-Eingabe oder zufälliges Passwort pro Benutzer (kein Standardpasswort)
        }
        $otherAttributes = @{}

        # Standard Name, falls nicht anders spezifiziert
        $userParams.Name = if ($csvRow.PSObject.Properties["DisplayName"]) { $csvRow.DisplayName } elseif ($csvRow.PSObject.Properties["FirstName"] -and $csvRow.PSObject.Properties["LastName"]) { "$($csvRow.FirstName) $($csvRow.LastName)" } else { $csvRow.SamAccountName }

        foreach ($checkBox in $selectedAttributesCheckboxes) {
            $attrInfo = $checkBox.Tag
            if ($csvRow.PSObject.Properties[$attrInfo.CsvHeader]) {
                $value = $csvRow.($attrInfo.CsvHeader)
                if (-not [string]::IsNullOrWhiteSpace($value)) {
                    # Spezielle Behandlung für bestimmte Attribute
                    if ($attrInfo.Name -eq "Country") {
                        # AD erwartet einen ISO-3166 2-Buchstaben-Code
                        $value = ConvertTo-CountryCode -Value $value
                    }
                    if ($attrInfo.Name -eq "proxyAddresses") {
                        $value = [string[]]@($value -split ";" | ForEach-Object { $_.Trim() } | Where-Object { $_ }) # Semikolon-getrennte Liste
                    }
                    if ($attrInfo.Name -eq "Manager") {
                        # Manager muss als DN/SamAccountName aufgelöst werden (CSV enthält ggf. Mailadressen)
                        $value = Resolve-ADUserReference -Reference $value -Cache $managerCache
                        if (-not $value) {
                            Write-AppLog "Manager '$($csvRow.($attrInfo.CsvHeader))' für Zeile $($i+1) nicht gefunden - Attribut wird ausgelassen." -Level "WARN"
                            continue
                        }
                    }
                    if ($script:ADUserOtherAttributeNames -contains $attrInfo.Name) {
                        # Kein eigener New-ADUser-Parameter -> über -OtherAttributes setzen
                        $otherAttributes[$script:ADAttributeLdapNames[$attrInfo.Name]] = $value
                    } else {
                        $userParams[$attrInfo.Name] = $value
                    }
                }
            }
        }

        # SamAccountName ist zwingend erforderlich
        if (-not $userParams.ContainsKey("SamAccountName") -or [string]::IsNullOrWhiteSpace($userParams.SamAccountName)) {
            Write-AppLog "Fehler: SamAccountName fehlt oder ist leer für Zeile $($i+1). Benutzer wird übersprungen." -Level "ERROR"
            $errorCount++
            continue
        }

        # SamAccountName für AD-Kompatibilität normalisieren
        $originalSamAccountName = $userParams.SamAccountName
        $userParams.SamAccountName = ConvertTo-NormalizedSamAccountName -SamAccountName $originalSamAccountName -ExistingNames $usedSamAccountNames

        if ($originalSamAccountName -ne $userParams.SamAccountName) {
            Write-AppLog "SamAccountName normalisiert für Zeile $($i+1): '$originalSamAccountName' → '$($userParams.SamAccountName)'" -Level "INFO"
        }

        # Fortschritt aktualisieren
        $progressText = if ($originalSamAccountName -ne $userParams.SamAccountName) {
            "Erstelle Benutzer ($($originalSamAccountName) → $($userParams.SamAccountName))"
        } else {
            "Erstelle Benutzer ($($userParams.SamAccountName))"
        }
        Write-GuiProgress -Current ($i + 1) -Total $numUsersToCreate -Text $progressText

        # Automatische UPN-Generierung, falls nicht bereits in CSV vorhanden
        if (-not $userParams.ContainsKey("UserPrincipalName") -or [string]::IsNullOrWhiteSpace($userParams.UserPrincipalName)) {
            $userParams.UserPrincipalName = Get-UserPrincipalName -SamAccountName $userParams.SamAccountName
            Write-AppLog "UPN automatisch generiert: $($userParams.UserPrincipalName)" -Level "DEBUG"
        }

        # UPN auf Eindeutigkeit prüfen (innerhalb des Laufs und im AD)
        if (-not $usedUpns.Add([string]$userParams.UserPrincipalName)) {
            Write-AppLog "UPN '$($userParams.UserPrincipalName)' kommt in der CSV mehrfach vor. Benutzer wird übersprungen." -Level "WARN"
            $errorCount++
            continue
        }
        try {
            $upnFilterValue = ConvertTo-ADFilterValue -Value $userParams.UserPrincipalName
            $existingUser = Get-ADUser -Filter "UserPrincipalName -eq '$upnFilterValue'" -ErrorAction Stop
            if ($existingUser) {
                Write-AppLog "UPN '$($userParams.UserPrincipalName)' existiert bereits für Benutzer '$($existingUser.SamAccountName)'. Benutzer wird übersprungen." -Level "WARN"
                $errorCount++
                continue
            }
        } catch {
            # Prüfung ist optional - New-ADUser meldet echte Konflikte selbst
            Write-AppLog "UPN-Prüfung für '$($userParams.UserPrincipalName)' fehlgeschlagen: $($_.Exception.Message)" -Level "DEBUG"
        }

        if ($otherAttributes.Count -gt 0) {
            $userParams.OtherAttributes = $otherAttributes
        }

        try {
            Write-AppLog "Erstelle Benutzer: $($userParams.SamAccountName)" -Level "DEBUG"
            $newUser = New-ADUser @userParams -PassThru -ErrorAction Stop
            Write-AppLog "Benutzer '$($newUser.SamAccountName)' erfolgreich erstellt." -Level "SUCCESS"
            $script:CreatedUsers.Add($newUser.SamAccountName) # Speichere nur SamAccountName für spätere Aktionen
            $script:LastCsvImportUsers.Add([PSCustomObject]@{ SamAccountName = $newUser.SamAccountName; RowIndex = $i })
            $createdCount++
        } catch {
            Write-AppLog "Fehler beim Erstellen des Benutzers '$($userParams.SamAccountName)': $($_.Exception.Message)" -Level "ERROR"
            $errorCount++
        }
    }

    # Fortschrittsanzeige ausblenden
    Hide-Progress

    Write-AppLog "Benutzererstellung abgeschlossen. $createdCount erfolgreich erstellt, $errorCount Fehler." -Level "INFO"
    Show-CreatedObjectCount
    $passwordHint = if ($usesRandomPasswords) { "`n`nHinweis: Es wurde kein Initial-Passwort angegeben. Jeder Benutzer hat ein eigenes, zufälliges Passwort erhalten (nicht gespeichert). Setzen Sie bei Bedarf ein Passwort per 'Set-ADAccountPassword' zurück." } else { "" }
    [System.Windows.MessageBox]::Show("Benutzererstellung abgeschlossen.`nErfolgreich: $createdCount`nFehler: $errorCount$passwordHint", "Ergebnis", "OK", "Information")
}


function Set-ADUserAttributeFromCsv {
    <#
    .SYNOPSIS
    Überschreibt Attribute der Benutzer aus dem letzten CSV-Import mit den Werten der aktuell geladenen CSV
    .DESCRIPTION
    Verwendet ausschließlich die Benutzer des letzten Laufs von 'Benutzer aus CSV erstellen' ($script:LastCsvImportUsers).
    Jeder Benutzer erhält die Werte der CSV-Zeile, aus der er erstellt wurde (gleiche Zeilennummer in der aktuell geladenen CSV).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Aktion 'Attribute befüllen' gestartet..."
    if ($script:LastCsvImportUsers.Count -eq 0) {
        Write-AppLog "Keine Benutzer aus einem CSV-Import vorhanden. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("'Attribute befüllen' bezieht sich nur auf die Benutzer, die beim letzten Lauf von 'Benutzer aus CSV erstellen' angelegt wurden.`n`nIn dieser Sitzung wurden noch keine Benutzer aus einer CSV erstellt (oder sie wurden inzwischen gelöscht). Zufällig oder per Vorlage erstellte Benutzer werden hier nicht berücksichtigt.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    if (-not $script:CsvData) {
        Write-AppLog "Keine CSV-Daten geladen. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte laden Sie zuerst eine CSV-Datei, die die neuen Attributwerte enthält.", "Hinweis", "OK", "Warning")
        return
    }

    $numUsersToUpdate = Get-ActionUserCount -Available $script:LastCsvImportUsers.Count
    if ($numUsersToUpdate -lt 0) { return }
    $csvRows = @($script:CsvData)

    $selectedAttributesToSetInfo = @{}
    $anyAttributeSelected = $false
    foreach ($checkBox in $script:GuiControls.StackPanelAttributeSelection.Children) {
        if ($checkBox.IsChecked -eq $true) {
            $attrInfo = $checkBox.Tag
            if ($attrInfo) {
                # SamAccountName ist der Identifikator, nicht zum Setzen via -Replace hier
                if ($attrInfo.Name -ne "SamAccountName") {
                     $selectedAttributesToSetInfo[$attrInfo.Name] = $attrInfo.CsvHeader
                     $anyAttributeSelected = $true
                }
            }
        }
    }

    if (-not $anyAttributeSelected) {
        Write-AppLog "Keine Attribute zum Befüllen ausgewählt." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein Attribut aus, das befüllt werden soll.", "Hinweis", "OK", "Warning")
        return
    }
    Write-AppLog "Folgende Attribute wurden zum Befüllen ausgewählt: $($selectedAttributesToSetInfo.Keys -join ', ')"

    $result = [System.Windows.MessageBox]::Show(
        "Sollen bei $numUsersToUpdate Benutzer(n) aus dem letzten CSV-Import die ausgewählten Attribute mit den Werten der aktuell geladenen CSV überschrieben werden?`n`n" +
        "Zuordnung: Jeder Benutzer erhält die Werte der CSV-Zeile, aus der er erstellt wurde.`n" +
        "Attribute: $($selectedAttributesToSetInfo.Keys -join ', ')",
        "Attribute befüllen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess("$numUsersToUpdate Benutzer aus dem letzten CSV-Import", "Attribute aus CSV setzen")) { return }

    # Fortschrittsanzeige aktivieren
    Show-Progress -Text "Starte Attribut-Update..." -Value 0

    $usersProcessed = 0
    $usersFailed = 0
    $managerCache = @{}

    for ($i = 0; $i -lt $numUsersToUpdate; $i++) {
        $importEntry = $script:LastCsvImportUsers[$i]
        $samAccountName = $importEntry.SamAccountName

        # Fortschritt aktualisieren
        Write-GuiProgress -Current ($i + 1) -Total $numUsersToUpdate -Text "Aktualisiere Benutzerattribute"

        if ($importEntry.RowIndex -ge $csvRows.Count) {
            Write-AppLog "Für '$samAccountName' gibt es in der aktuell geladenen CSV keine Zeile $($importEntry.RowIndex + 1). Übersprungen." -Level "WARN"
            $usersFailed++
            continue
        }
        $csvRow = $csvRows[$importEntry.RowIndex]

        Write-AppLog "Verarbeite Benutzer '$samAccountName' (Datensatz $($importEntry.RowIndex + 1) aus CSV)..."
        $attributesForReplaceCmd = @{}

        foreach ($attrNameKey in $selectedAttributesToSetInfo.Keys) {
            $csvHeaderName = $selectedAttributesToSetInfo[$attrNameKey]
            if ($csvRow.PSObject.Properties[$csvHeaderName]) {
                $valueFromCsv = $csvRow.$($csvHeaderName)
                # Nur nicht-leere Werte aus der CSV verwenden, um Attribute zu setzen/überschreiben
                # Leere Werte in der CSV führen nicht zum Löschen des Attributs mit dieser Logik
                if (-not [string]::IsNullOrEmpty($valueFromCsv)) {
                    # Spezielle Attribut-Behandlung
                    switch ($attrNameKey) {
                        "proxyAddresses" {
                            $proxyAddressesArray = $valueFromCsv -split ';' | ForEach-Object {$_.Trim()} | Where-Object {$_}
                            $attributesForReplaceCmd[$attrNameKey] = $proxyAddressesArray
                        }
                        "Manager" {
                            # Prüfe ob Manager gültig ist (DN, SamAccountName, UPN oder Mail; mit Cache)
                            $managerDn = Resolve-ADUserReference -Reference $valueFromCsv -Cache $managerCache
                            if ($managerDn) {
                                $attributesForReplaceCmd[$attrNameKey] = $managerDn
                            } else {
                                Write-AppLog "  Manager '$valueFromCsv' nicht gefunden für Benutzer '$samAccountName'" -Level "WARN"
                            }
                        }
                        "Country" {
                            # Konvertiere zu 2-Buchstaben-Code wenn nötig
                            $attributesForReplaceCmd[$attrNameKey] = ConvertTo-CountryCode -Value $valueFromCsv
                        }
                        "PostalCode" {
                            # Führende Nullen bleiben erhalten (z.B. deutsche PLZ 01067)
                            $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv
                        }
                        "ExtensionAttribute1" { $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv }
                        "ExtensionAttribute2" { $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv }
                        "ExtensionAttribute3" { $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv }
                        "ExtensionAttribute4" { $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv }
                        "ExtensionAttribute5" { $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv }
                        default {
                            $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv
                        }
                    }
                    Write-AppLog "  Setze '$attrNameKey' auf '$($attributesForReplaceCmd[$attrNameKey])' (aus CSV-Spalte '$csvHeaderName')"
                } else {
                    Write-AppLog "  Wert für '$attrNameKey' (aus CSV '$csvHeaderName') ist leer. Attribut wird für '$samAccountName' nicht geändert." -Level "INFO"
                }
            } else {
                Write-AppLog "  CSV-Spalte '$csvHeaderName' für Attribut '$attrNameKey' nicht im aktuellen CSV-Datensatz gefunden." -Level "WARN"
            }
        }

        if ($attributesForReplaceCmd.Count -gt 0) {
            # Parameternamen (z.B. Surname, City) in LDAP-Attributnamen (sn, l) für -Replace übersetzen
            $ldapReplace = @{}
            foreach ($key in $attributesForReplaceCmd.Keys) {
                $ldapName = if ($script:ADAttributeLdapNames.ContainsKey($key)) { $script:ADAttributeLdapNames[$key] } else { $key }
                $ldapReplace[$ldapName] = $attributesForReplaceCmd[$key]
            }
            try {
                Set-ADUser -Identity $samAccountName -Replace $ldapReplace -ErrorAction Stop
                Write-AppLog "Benutzer '$samAccountName' erfolgreich aktualisiert." -Level "SUCCESS"
                $usersProcessed++
            } catch {
                Write-AppLog "Fehler beim Aktualisieren von Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
                $usersFailed++
            }
        } else {
            Write-AppLog "Keine gültigen Attributwerte zum Aktualisieren für Benutzer '$samAccountName' gefunden. Übersprungen." -Level "INFO"
        }
    }

    # Fortschrittsanzeige ausblenden
    Hide-Progress

    $summaryMessage = "Aktion 'Attribute befüllen' abgeschlossen. $usersProcessed Benutzer erfolgreich aktualisiert, $usersFailed Fehler."
    Write-AppLog $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Get-ActionUserCount {
    <#
    .SYNOPSIS
    Liest das Feld 'Anzahl Benutzer für Aktion' aus (leer = alle) und begrenzt den Wert auf die verfügbare Anzahl
    .OUTPUTS
    Anzahl der zu bearbeitenden Benutzer oder -1 bei ungültiger Eingabe
    #>
    param([Parameter(Mandatory = $true)][int]$Available)

    $text = ([string]$script:GuiControls.TextBoxNumUsersForAction.Text).Trim()
    if (-not $text) { return $Available }
    $count = ConvertTo-IntOrZero -Value $text
    if ($count -le 0) {
        Write-AppLog "Ungültige Eingabe für 'Anzahl Benutzer für Aktion': '$text'" -Level "WARN"
        [System.Windows.MessageBox]::Show("Die Eingabe für 'Anzahl Benutzer für Aktion' ist ungültig. Bitte geben Sie eine positive Zahl ein oder lassen Sie das Feld leer (= alle).", "Hinweis", "OK", "Warning") | Out-Null
        return -1
    }
    return [math]::Min($count, $Available)
}

function Disable-CreatedADUser {
    Write-AppLog "Aktion 'Benutzer deaktivieren' gestartet..."
    if (-not $script:CreatedUsers -or $script:CreatedUsers.Count -eq 0) {
        Write-AppLog "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $result = [System.Windows.MessageBox]::Show("Sind Sie sicher, dass Sie die erstellten Benutzer deaktivieren möchten?", "Bestätigung", "YesNo", "Question")
    if ($result -ne "Yes") {
        Write-AppLog "Benutzer-Deaktivierung abgebrochen." -Level "INFO"
        return
    }

    $numUsersToDisable = Get-ActionUserCount -Available $script:CreatedUsers.Count
    if ($numUsersToDisable -lt 0) { return }

    $usersProcessed = 0
    $usersFailed = 0
    $usersToDisable = @($script:CreatedUsers | Select-Object -First $numUsersToDisable)

    Show-Progress -Text "Deaktiviere Benutzer..."
    for ($i = 0; $i -lt $usersToDisable.Count; $i++) {
        $samAccountName = $usersToDisable[$i]
        Write-GuiProgress -Current ($i + 1) -Total $usersToDisable.Count -Text "Deaktiviere $samAccountName"
        try {
            Disable-ADAccount -Identity $samAccountName -ErrorAction Stop
            Write-AppLog "Benutzer '$samAccountName' erfolgreich deaktiviert." -Level "SUCCESS"
            $usersProcessed++
        } catch {
            Write-AppLog "Fehler beim Deaktivieren von Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }

    Hide-Progress

    $summaryMessage = "Aktion 'Benutzer deaktivieren' abgeschlossen. $usersProcessed Benutzer deaktiviert, $usersFailed Fehler."
    Write-AppLog $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Remove-CreatedADUser {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Aktion 'Benutzer löschen' gestartet..."
    if (-not $script:CreatedUsers -or $script:CreatedUsers.Count -eq 0) {
        Write-AppLog "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $result = [System.Windows.MessageBox]::Show("WARNUNG: Diese Aktion löscht die erstellten Benutzer UNWIDERRUFLICH!`n`nSind Sie sicher?", "VORSICHT - Benutzer löschen", "YesNo", "Warning")
    if ($result -ne "Yes") {
        Write-AppLog "Benutzer-Löschung abgebrochen." -Level "INFO"
        return
    }

    $numUsersToDelete = Get-ActionUserCount -Available $script:CreatedUsers.Count
    if ($numUsersToDelete -lt 0) { return }
    if (-not $PSCmdlet.ShouldProcess("$numUsersToDelete vom Tool erstellte Benutzer", "Löschen")) { return }

    $usersProcessed = 0
    $usersFailed = 0
    $deletedUsers = New-Object System.Collections.Generic.List[string]

    # Nur Benutzer löschen, die von diesem Tool erstellt wurden (Liste $script:CreatedUsers)
    $usersToDelete = @($script:CreatedUsers | Select-Object -First $numUsersToDelete)
    for ($i = 0; $i -lt $usersToDelete.Count; $i++) {
        $samAccountName = $usersToDelete[$i]
        Write-GuiProgress -Current ($i + 1) -Total $usersToDelete.Count -Text "Lösche Benutzer: $samAccountName"
        try {
            Remove-ADUser -Identity $samAccountName -Confirm:$false -ErrorAction Stop
            Write-AppLog "Benutzer '$samAccountName' erfolgreich gelöscht." -Level "SUCCESS"
            $deletedUsers.Add($samAccountName)
            $usersProcessed++
        } catch {
            Write-AppLog "Fehler beim Löschen von Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }
    Hide-Progress

    # Nur tatsächlich gelöschte Benutzer aus der Liste entfernen (fehlgeschlagene bleiben nachverfolgbar)
    foreach ($deletedUser in $deletedUsers) {
        [void]$script:CreatedUsers.Remove($deletedUser)
        [void]$script:LastCsvImportUsers.RemoveAll([Predicate[object]] { param($entry) $entry.SamAccountName -eq $deletedUser })
    }
    Show-CreatedObjectCount

    $summaryMessage = "Aktion 'Benutzer löschen' abgeschlossen. $usersProcessed Benutzer gelöscht, $usersFailed Fehler."
    Write-AppLog $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Export-CreatedUser {
    Write-AppLog "Export der erstellten Benutzer gestartet..."
    if (-not $script:CreatedUsers -or $script:CreatedUsers.Count -eq 0) {
        Write-AppLog "Keine Benutzer zum Exportieren vorhanden." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt oder alle wurden bereits gelöscht.", "Hinweis", "OK", "Warning")
        return
    }

    try {
        $exportPath = Get-ExportFilePath -FileName "Created_Users_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $exportData = New-Object System.Collections.Generic.List[object]

        foreach ($samAccountName in $script:CreatedUsers) {
            try {
                $user = Get-ADUser -Identity $samAccountName -Properties DisplayName, EmailAddress, Created -ErrorAction Stop
                $exportData.Add([PSCustomObject]@{
                    SamAccountName = $user.SamAccountName
                    DisplayName = $user.DisplayName
                    GivenName = $user.GivenName
                    Surname = $user.Surname
                    UserPrincipalName = $user.UserPrincipalName
                    EmailAddress = $user.EmailAddress
                    Enabled = $user.Enabled
                    Created = $user.Created
                    DistinguishedName = $user.DistinguishedName
                })
            } catch {
                Write-AppLog "Fehler beim Abrufen der Details für Benutzer '$samAccountName': $($_.Exception.Message)" -Level "WARN"
                $exportData.Add([PSCustomObject]@{
                    SamAccountName = $samAccountName
                    DisplayName = "Fehler beim Abrufen"
                    GivenName = ""
                    Surname = ""
                    UserPrincipalName = ""
                    EmailAddress = ""
                    Enabled = "Unbekannt"
                    Created = ""
                    DistinguishedName = ""
                })
            }
        }

        $exportData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Write-AppLog "Export erfolgreich: $exportPath" -Level "SUCCESS"
        [System.Windows.MessageBox]::Show("Benutzerliste erfolgreich exportiert nach:`n$exportPath", "Export abgeschlossen", "OK", "Information")
    } catch {
        Write-AppLog "Fehler beim Export: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Exportieren der Benutzerliste:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Show-CsvBrowser {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $openFileDialog.Title = "CSV-Datei auswählen"
        $initialDir = $script:AppConfig.ScriptRoot
        if (-not [string]::IsNullOrWhiteSpace($script:GuiControls.TextBoxCsvPath.Text)) {
            $csvDir = Split-Path -Path $script:GuiControls.TextBoxCsvPath.Text -Parent
            if ($csvDir -and (Test-Path -LiteralPath $csvDir -PathType Container)) { $initialDir = (Resolve-Path -LiteralPath $csvDir).ProviderPath }
        }
        $openFileDialog.InitialDirectory = $initialDir

        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:GuiControls.TextBoxCsvPath.Text = $openFileDialog.FileName
            Write-AppLog "CSV-Pfad ausgewählt: $($openFileDialog.FileName)" -Level "INFO"
        }
    } catch {
        Write-AppLog "Fehler beim Öffnen des Datei-Browsers: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Öffnen des Datei-Browsers. Bitte geben Sie den Pfad manuell ein.", "Fehler", "OK", "Error")
    }
}

function Set-CriticalSecuritySetting {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Anwenden kritischer Sicherheitseinstellungen gestartet..."
    if (-not $script:CreatedUsers -or $script:CreatedUsers.Count -eq 0) {
        Write-AppLog "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $result = [System.Windows.MessageBox]::Show("WARNUNG: Sie sind dabei, kritische Sicherheitseinstellungen zu ändern!`n`nDies kann Ihre Domäne gefährden. Sind Sie sicher?", "KRITISCHE SICHERHEITSWARNUNG", "YesNo", "Warning")
    if ($result -ne "Yes") {
        Write-AppLog "Anwendung kritischer Sicherheitseinstellungen abgebrochen." -Level "INFO"
        return
    }

    $pwdNotExpires = [bool]$script:GuiControls.CheckBoxPwdNotExpires.IsChecked
    $revPwd = [bool]$script:GuiControls.CheckBoxRevPwd.IsChecked
    if (-not ($pwdNotExpires -or $revPwd)) {
        Write-AppLog "Keine kritische Einstellung ausgewählt." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Einstellung aus.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $numUsersToModify = Get-ActionUserCount -Available $script:CreatedUsers.Count
    if ($numUsersToModify -lt 0) { return }
    if (-not $PSCmdlet.ShouldProcess("$numUsersToModify vom Tool erstellte Benutzer", "Kritische Sicherheitseinstellungen setzen")) { return }

    $usersProcessed = 0
    $usersFailed = 0
    $usersToModify = @($script:CreatedUsers | Select-Object -First $numUsersToModify)

    for ($i = 0; $i -lt $usersToModify.Count; $i++) {
        $samAccountName = $usersToModify[$i]
        try {
            $params = @{}

            if ($pwdNotExpires) {
                $params.PasswordNeverExpires = $true
                Write-AppLog "Setze für '$samAccountName': Passwort läuft nie ab" -Level "WARN"
            }

            if ($revPwd) {
                $params.AllowReversiblePasswordEncryption = $true
                Write-AppLog "Setze für '$samAccountName': Umkehrbare Verschlüsselung aktiviert" -Level "WARN"
            }

            if ($params.Count -gt 0) {
                Set-ADUser -Identity $samAccountName @params -ErrorAction Stop
                Write-AppLog "Sicherheitseinstellungen für Benutzer '$samAccountName' erfolgreich angewendet." -Level "SUCCESS"
                $usersProcessed++
            }
        } catch {
            Write-AppLog "Fehler beim Anwenden der Sicherheitseinstellungen für Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }

    $summaryMessage = "Anwendung kritischer Sicherheitseinstellungen abgeschlossen. $usersProcessed Benutzer bearbeitet, $usersFailed Fehler."
    Write-AppLog $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Test-ADConnection {
    try {
        Write-AppLog "Prüfe Active Directory Verbindung..."
        $domain = Get-ADDomain -ErrorAction Stop
        Write-AppLog "AD-Verbindung erfolgreich. Domäne: $($domain.Name)" -Level "SUCCESS"
        return $true
    } catch {
        Write-AppLog "Fehler bei AD-Verbindung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Active Directory Verbindung fehlgeschlagen:`n$($_.Exception.Message)`n`nBitte stellen Sie sicher, dass:`n- Das ActiveDirectory-Modul installiert ist`n- Sie mit einer Domäne verbunden sind`n- Sie über ausreichende Berechtigungen verfügen", "AD-Verbindungsfehler", "OK", "Error")
        return $false
    }
}

function Test-TargetOU {
    param([string]$TargetOU)

    if (-not $TargetOU) {
        return $false
    }

    try {
        $ou = Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop
        Write-AppLog "Ziel-OU validiert: $($ou.DistinguishedName)" -Level "SUCCESS"
        return $true
    } catch {
        Write-AppLog "Ziel-OU nicht gefunden oder ungültig: $TargetOU - $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Die angegebene Ziel-OU ist ungültig oder nicht gefunden:`n$TargetOU`n`nFehler: $($_.Exception.Message)", "OU-Validierungsfehler", "OK", "Error")
        return $false
    }
}

function Register-EventHandler {
    # CSV-basierte Funktionen
    if ($script:GuiControls.ButtonBrowseCsv) { $script:GuiControls.ButtonBrowseCsv.Add_Click({ Invoke-GuiAction { Show-CsvBrowser } }) }
    if ($script:GuiControls.ButtonLoadCsv) { $script:GuiControls.ButtonLoadCsv.Add_Click({ Invoke-GuiAction { Import-CsvData } }) }
    if ($script:GuiControls.ButtonCreateADUsers) { $script:GuiControls.ButtonCreateADUsers.Add_Click({ Invoke-GuiAction { New-ADUserFromCsv } }) }
    if ($script:GuiControls.ButtonFillAttributes) { $script:GuiControls.ButtonFillAttributes.Add_Click({ Invoke-GuiAction { Set-ADUserAttributeFromCsv } }) }
    if ($script:GuiControls.ButtonDisableUsers) { $script:GuiControls.ButtonDisableUsers.Add_Click({ Invoke-GuiAction { Disable-CreatedADUser } }) }
    if ($script:GuiControls.ButtonDeleteUsers) { $script:GuiControls.ButtonDeleteUsers.Add_Click({ Invoke-GuiAction { Remove-CreatedADUser } }) }
    if ($script:GuiControls.ButtonExportCreatedUsers) { $script:GuiControls.ButtonExportCreatedUsers.Add_Click({ Invoke-GuiAction { Export-CreatedUser } }) }
    if ($script:GuiControls.ButtonApplySecuritySettings) { $script:GuiControls.ButtonApplySecuritySettings.Add_Click({ Invoke-GuiAction { Set-CriticalSecuritySetting } }) }

    # Neue Event Handler für Benutzer-Erstellung & Verwaltung
    if ($script:GuiControls.ButtonGenerateRandomData) { $script:GuiControls.ButtonGenerateRandomData.Add_Click({ Invoke-GuiAction { Set-RandomUserAttribute } }) }
    if ($script:GuiControls.ButtonCreateFromTemplate) { $script:GuiControls.ButtonCreateFromTemplate.Add_Click({ Invoke-GuiAction { New-UserFromTemplate } }) }
    if ($script:GuiControls.ButtonSetTimeRestrictions) { $script:GuiControls.ButtonSetTimeRestrictions.Add_Click({ Invoke-GuiAction { Set-UserLogonHour } }) }
    if ($script:GuiControls.ButtonBrowseAvatars) { $script:GuiControls.ButtonBrowseAvatars.Add_Click({ Invoke-GuiAction { Select-AvatarPath } }) }
    if ($script:GuiControls.ButtonAssignAvatars) { $script:GuiControls.ButtonAssignAvatars.Add_Click({ Invoke-GuiAction { Set-UserAvatar } }) }

    # Schnellzugriff Event Handler
    if ($script:GuiControls.ButtonQuickRandomUsers) { $script:GuiControls.ButtonQuickRandomUsers.Add_Click({ Invoke-GuiAction { New-RandomUser } }) }
    if ($script:GuiControls.ButtonQuickCreateGroups) { $script:GuiControls.ButtonQuickCreateGroups.Add_Click({ Invoke-GuiAction { New-StandardTestGroup } }) }
    if ($script:GuiControls.ButtonQuickTestData) { $script:GuiControls.ButtonQuickTestData.Add_Click({ Invoke-GuiAction { New-QuickTestDataSet } }) }
    if ($script:GuiControls.ButtonQuickCleanup) { $script:GuiControls.ButtonQuickCleanup.Add_Click({ Invoke-GuiAction { Clear-CreatedTestData } }) }

    # Löschfunktionen Event Handler
    if ($script:GuiControls.ButtonDeleteGroups) { $script:GuiControls.ButtonDeleteGroups.Add_Click({ Invoke-GuiAction { Remove-CreatedGroup } }) }
    if ($script:GuiControls.ButtonDeleteComputers) { $script:GuiControls.ButtonDeleteComputers.Add_Click({ Invoke-GuiAction { Remove-CreatedComputer } }) }
    if ($script:GuiControls.ButtonDeleteOUs) { $script:GuiControls.ButtonDeleteOUs.Add_Click({ Invoke-GuiAction { Remove-CreatedOU } }) }
    if ($script:GuiControls.ButtonDeleteServiceAccounts) { $script:GuiControls.ButtonDeleteServiceAccounts.Add_Click({ Invoke-GuiAction { Remove-CreatedServiceAccount } }) }
    if ($script:GuiControls.ButtonDeletePrinters) { $script:GuiControls.ButtonDeletePrinters.Add_Click({ Invoke-GuiAction { Remove-CreatedPrinter } }) }
    if ($script:GuiControls.ButtonExportAll) { $script:GuiControls.ButtonExportAll.Add_Click({ Invoke-GuiAction { Export-CreatedObject } }) }

    # Test-Umgebung Event Handler
    if ($script:GuiControls.ButtonCreateTestEnvironment) { $script:GuiControls.ButtonCreateTestEnvironment.Add_Click({ Invoke-GuiAction { New-TestEnvironment } }) }
    if ($script:GuiControls.ButtonCreateRandomUsers) { $script:GuiControls.ButtonCreateRandomUsers.Add_Click({ Invoke-GuiAction { New-RandomUser } }) }

    # Event Handler für Gruppen & Organisationsstruktur
    if ($script:GuiControls.ButtonCreateAutoGroups) { $script:GuiControls.ButtonCreateAutoGroups.Add_Click({ Invoke-GuiAction { New-AutomaticGroup } }) }
    if ($script:GuiControls.ButtonCreateNestedGroups) { $script:GuiControls.ButtonCreateNestedGroups.Add_Click({ Invoke-GuiAction { New-NestedGroupStructure } }) }
    if ($script:GuiControls.ButtonCreateOUStructure) { $script:GuiControls.ButtonCreateOUStructure.Add_Click({ Invoke-GuiAction { New-OUStructure } }) }

    # Event Handler für Computer & Geräte
    if ($script:GuiControls.ButtonCreateComputers) { $script:GuiControls.ButtonCreateComputers.Add_Click({ Invoke-GuiAction { New-TestComputer } }) }
    if ($script:GuiControls.ButtonCreateServiceAccounts) { $script:GuiControls.ButtonCreateServiceAccounts.Add_Click({ Invoke-GuiAction { New-TestServiceAccount } }) }
    if ($script:GuiControls.ButtonCreatePrinters) { $script:GuiControls.ButtonCreatePrinters.Add_Click({ Invoke-GuiAction { New-TestPrinter } }) }
    if ($script:GuiControls.ButtonCreateBitLockerData) { $script:GuiControls.ButtonCreateBitLockerData.Add_Click({ Invoke-GuiAction { New-ComputerBitLockerData } }) }
    if ($script:GuiControls.ButtonCreateLAPSData) { $script:GuiControls.ButtonCreateLAPSData.Add_Click({ Invoke-GuiAction { New-LAPSData } }) }

    # Event Handler für Test-Szenarien
    if ($script:GuiControls.ButtonCreateTestDataSet) { $script:GuiControls.ButtonCreateTestDataSet.Add_Click({ Invoke-GuiAction { New-TestDataSet } }) }
    if ($script:GuiControls.ButtonActivateChaosMode) { $script:GuiControls.ButtonActivateChaosMode.Add_Click({ Invoke-GuiAction { New-ChaosTestData } }) }
    if ($script:GuiControls.ButtonStartPerformanceTest) { $script:GuiControls.ButtonStartPerformanceTest.Add_Click({ Invoke-GuiAction { Start-PerformanceTest } }) }

    # Event Handler für Sicherheit & Compliance
    if ($script:GuiControls.ButtonApplyPasswordPolicies) { $script:GuiControls.ButtonApplyPasswordPolicies.Add_Click({ Invoke-GuiAction { Set-PasswordPolicyTestData } }) }
    if ($script:GuiControls.ButtonCreateRBACRoles) { $script:GuiControls.ButtonCreateRBACRoles.Add_Click({ Invoke-GuiAction { New-RBACRole } }) }

    # Event Handler für Erweiterte Features
    if ($script:GuiControls.ButtonCreateAdvancedFeatures) { $script:GuiControls.ButtonCreateAdvancedFeatures.Add_Click({ Invoke-GuiAction { Invoke-AdvancedFeature } }) }

    Write-AppLog "Event Handler registriert."
}

#endregion

#region Initialisierung und Start

function Initialize-Application {
    Write-AppLog "Initialisiere Anwendung..."
    try {
        # XAML korrekt laden
        $stringReader = New-Object System.IO.StringReader -ArgumentList $XAML
        $xmlTextReader = [System.Xml.XmlTextReader]::new($stringReader)
        $script:Window = [Windows.Markup.XamlReader]::Load($xmlTextReader)

        if (-not $script:Window) {
            Throw "Kritischer Fehler: Das XAML-Fenster konnte nicht geladen werden."
        }
        Write-AppLog "XAML-Fenster erfolgreich geladen."

        Initialize-GuiControl
        Register-EventHandler

        # Standard CSV laden, falls vorhanden, ansonsten Beispiel erstellen
        $script:GuiControls.TextBoxCsvPath.Text = $script:AppConfig.DefaultCsvPath
        if (Test-Path $script:AppConfig.DefaultCsvPath -PathType Leaf) {
            Import-CsvData
        } else {
            Write-AppLog "Standard CSV-Datei nicht gefunden: $($script:AppConfig.DefaultCsvPath)" -Level "WARN"
            New-SampleCsv
        }

        # AD-Verbindung testen (nicht blockierend)
        if (-not (Test-ADConnection)) {
            Write-AppLog "AD-Verbindung fehlgeschlagen - Funktion eingeschränkt verfügbar." -Level "WARN"
        } else {
            # OU-Dropdown initialisieren wenn AD-Verbindung besteht
            Initialize-OUDropdown
        }

        Write-AppLog "Anwendung erfolgreich initialisiert." -Level "SUCCESS"
    } catch {
        Write-AppLog "Fehler während der Anwendungsinitialisierung: $($_.Exception.ToString())" -Level "ERROR"
        # Den Fehler weiterwerfen, damit er vom äußeren try-catch in Show-MainWindow behandelt wird
        throw $_
    }
}

function New-SampleCsv {
    <#
    .SYNOPSIS
    Legt eine Beispiel-CSV am Standardpfad an, falls dort noch keine Datei existiert
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess($script:AppConfig.DefaultCsvPath, "Beispiel-CSV erstellen")) { return }
    try {
        $sampleData = @(
            [PSCustomObject]@{
                SamAccountName = "test.user1"
                FirstName = "Test"
                LastName = "User1"
                DisplayName = "Test User 1"
                Email = "test.user1@example.com"
                Department = "IT"
                Title = "Test Engineer"
                Company = "Example Corp"
                UserPrincipalName = "test.user1@example.com"
            },
            [PSCustomObject]@{
                SamAccountName = "test.user2"
                FirstName = "Test"
                LastName = "User2"
                DisplayName = "Test User 2"
                Email = "test.user2@example.com"
                Department = "HR"
                Title = "Test Manager"
                Company = "Example Corp"
                UserPrincipalName = "test.user2@example.com"
            }
        )

        $sampleData | Export-Csv -Path $script:AppConfig.DefaultCsvPath -NoTypeInformation -Encoding UTF8
        Write-AppLog "Beispiel-CSV erstellt: $($script:AppConfig.DefaultCsvPath)" -Level "INFO"
        Import-CsvData
    } catch {
        Write-AppLog "Fehler beim Erstellen der Beispiel-CSV: $($_.Exception.Message)" -Level "ERROR"
    }
}

#region GUI Verbesserungen - OU Dropdown, Progress, UPN Generation

function Get-ADOrganizationalUnitList {
    <#
    .SYNOPSIS
    Ruft alle verfügbaren Organizational Units aus Active Directory ab
    #>
    try {
        Write-AppLog "Lade OUs aus Active Directory..."
        $ous = Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName
        Write-AppLog "$(($ous | Measure-Object).Count) OUs gefunden" -Level "SUCCESS"
        return $ous
    } catch {
        Write-AppLog "Fehler beim Laden der OUs: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Initialize-OUDropdown {
    <#
    .SYNOPSIS
    Befüllt die OU-ComboBox mit verfügbaren OUs
    #>
    try {
        $comboBox = $script:GuiControls.ComboBoxTargetOU
        $comboBox.Items.Clear()

        # Standard-OU hinzufügen
        $comboBox.Items.Add("OU=DummyUsers,DC=example,DC=com")

        # AD OUs laden
        $ous = Get-ADOrganizationalUnitList
        foreach ($ou in $ous) {
            if ($ou.DistinguishedName -notlike "*CN=*") {  # Nur echte OUs, keine Container
                $comboBox.Items.Add($ou.DistinguishedName)
            }
        }

        # Ersten Eintrag auswählen
        if ($comboBox.Items.Count -gt 0) {
            $comboBox.SelectedIndex = 0
        }

        Write-AppLog "OU-Dropdown initialisiert mit $(($comboBox.Items | Measure-Object).Count) Einträgen" -Level "SUCCESS"
    } catch {
        Write-AppLog "Fehler beim Initialisieren des OU-Dropdowns: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Get-UserPrincipalName {
    <#
    .SYNOPSIS
    Generiert automatisch User Principal Names basierend auf SamAccountName
    #>
    param(
        [string]$SamAccountName,
        [string]$DefaultDomain = $null
    )

    try {
        if (-not $DefaultDomain) {
            # Versuche die Standard-Domain aus AD zu ermitteln (zwischengespeichert)
            $domain = $null
            try { $domain = Get-CachedADDomain } catch { Write-AppLog "Domäne konnte nicht ermittelt werden: $($_.Exception.Message)" -Level "DEBUG" }
            if ($domain) {
                $DefaultDomain = $domain.DNSRoot
            } else {
                $DefaultDomain = "example.com"
            }
        }

        $upn = "$SamAccountName@$DefaultDomain"
        Write-AppLog "UPN generiert: $upn" -Level "DEBUG"
        return $upn
    } catch {
        Write-AppLog "Fehler bei UPN-Generierung für '$SamAccountName': $($_.Exception.Message)" -Level "ERROR"
        return "$SamAccountName@example.com"
    }
}

# Hilfsfunktionen für Zufallsdaten
function Get-RandomFirstName {
    $names = $script:RandomDataLists.FirstNames
    if ($names -and $names.Count -gt 0) {
        return $names | Get-Random
    }
    return "Max"  # Fallback
}

function Get-RandomLastName {
    $names = $script:RandomDataLists.LastNames
    if ($names -and $names.Count -gt 0) {
        return $names | Get-Random
    }
    return "Mustermann"  # Fallback
}

function Get-RandomStreetAddress {
    $streets = $script:RandomDataLists.Streets
    if ($streets -and $streets.Count -gt 0) {
        $street = $streets | Get-Random
        $number = Get-Random -Minimum 1 -Maximum 200
        return "$street $number"
    }
    return "Hauptstrasse 1"  # Fallback
}

function Get-RandomCity {
    $cities = $script:RandomDataLists.Cities
    if ($cities -and $cities.Count -gt 0) {
        return $cities | Get-Random
    }
    return "Berlin"  # Fallback
}

function Get-RandomPostalCode {
    return (Get-Random -Minimum 10000 -Maximum 99999).ToString()
}

function Get-RandomPhoneNumber {
    $areaCode = Get-Random -Minimum 100 -Maximum 999
    $number = Get-Random -Minimum 1000000 -Maximum 9999999
    return "+49 $areaCode $number"
}

function Get-RandomDepartment {
    $departments = $script:RandomDataLists.Departments
    if ($departments -and $departments.Count -gt 0) {
        return $departments | Get-Random
    }
    return "IT"  # Fallback
}

function Get-RandomJobTitle {
    $titles = $script:RandomDataLists.JobTitles
    if ($titles -and $titles.Count -gt 0) {
        return $titles | Get-Random
    }
    return "Specialist"  # Fallback
}

function Show-CreatedObjectCount {
    <#
    .SYNOPSIS
    Aktualisiert die Statistik-Kacheln mit der Anzahl der in dieser Sitzung erstellten Objekte
    #>
    try {
        $counts = [ordered]@{
            TextBlockUserCount     = $script:CreatedUsers.Count
            TextBlockGroupCount    = $script:CreatedGroups.Count
            TextBlockComputerCount = $script:CreatedComputers.Count
            TextBlockOUCount       = $script:CreatedOUs.Count
            TextBlockServiceCount  = $script:CreatedServiceAccounts.Count
            TextBlockPrinterCount  = $script:CreatedPrinters.Count
        }
        $totalCount = 0
        foreach ($entry in $counts.GetEnumerator()) {
            $totalCount += $entry.Value
            if ($script:GuiControls[$entry.Key]) { $script:GuiControls[$entry.Key].Text = $entry.Value.ToString() }
        }
        if ($script:GuiControls.TextBlockTotalCount) { $script:GuiControls.TextBlockTotalCount.Text = $totalCount.ToString() }

        Write-AppLog "Statistiken aktualisiert" -Level "DEBUG"
    } catch {
        Write-AppLog "Fehler beim Aktualisieren der Statistiken: $($_.Exception.Message)" -Level "WARN"
    }
}

function ConvertTo-AvatarImage {
    <#
    .SYNOPSIS
    Erzeugt ein JPEG-Avatarbild (96x96 Pixel) mit Initialen und liefert es als Byte-Array
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Initials,
        [int]$ColorIndex = 0
    )

    $palette = @(
        @(52, 152, 219),   # Blau
        @(46, 204, 113),   # Grün
        @(231, 76, 60),    # Rot
        @(155, 89, 182),   # Lila
        @(241, 196, 15),   # Gelb
        @(230, 126, 34),   # Orange
        @(149, 165, 166),  # Grau
        @(52, 73, 94)      # Dunkelblau
    )
    $rgb = $palette[[math]::Abs($ColorIndex) % $palette.Count]

    $bitmap = $null; $graphics = $null; $font = $null; $brush = $null; $format = $null; $stream = $null
    try {
        $bitmap = New-Object System.Drawing.Bitmap 96, 96
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $graphics.Clear([System.Drawing.Color]::FromArgb($rgb[0], $rgb[1], $rgb[2]))

        $font = New-Object System.Drawing.Font('Segoe UI', 36, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        $graphics.DrawString($Initials, $font, $brush, (New-Object System.Drawing.RectangleF(0, 0, 96, 96)), $format)

        $stream = New-Object System.IO.MemoryStream
        $bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        # Komma verhindert, dass PowerShell das Byte-Array in Einzelwerte auflöst
        return , $stream.ToArray()
    } finally {
        foreach ($disposable in @($stream, $format, $brush, $font, $graphics, $bitmap)) {
            if ($disposable) { $disposable.Dispose() }
        }
    }
}

function Set-RandomUserAttribute {
    <#
    .SYNOPSIS
    Überschreibt die ausgewählten Attribute aller vom Tool erstellten Benutzer mit neuen Zufallswerten
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Zuweisung von Zufallsattributen..." -Level "INFO"

    $randomNames = [bool]$script:GuiControls.CheckBoxRandomNames.IsChecked
    $randomAddresses = [bool]$script:GuiControls.CheckBoxRandomAddresses.IsChecked
    $randomPhone = [bool]$script:GuiControls.CheckBoxRandomPhone.IsChecked
    $randomDepartments = [bool]$script:GuiControls.CheckBoxRandomDepartments.IsChecked
    $randomTitles = [bool]$script:GuiControls.CheckBoxRandomTitles.IsChecked
    $randomCompany = [bool]$script:GuiControls.CheckBoxRandomCompany.IsChecked

    if (-not ($randomNames -or $randomAddresses -or $randomPhone -or $randomDepartments -or $randomTitles -or $randomCompany)) {
        Write-AppLog "Keine Attribute für Zufallsdaten ausgewählt" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie unter 'Zufällige Attribute' mindestens ein Attribut aus.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $users = @($script:CreatedUsers)
    if ($users.Count -eq 0) {
        Write-AppLog "Keine Benutzer für Zufallsdaten vorhanden" -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden in dieser Sitzung noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $result = [System.Windows.MessageBox]::Show(
        "Sollen die ausgewählten Attribute von $($users.Count) vom Tool erstellten Benutzern mit Zufallswerten überschrieben werden?",
        "Zufallsattribute zuweisen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess("$($users.Count) Benutzer", "Zufallsattribute setzen")) { return }

    $companyName = ([string]$script:GuiControls.TextBoxCompanyName.Text).Trim()
    if (-not $companyName) { $companyName = "Testfirma" }

    Show-Progress -Text "Weise Zufallsattribute zu..."
    $processed = 0
    $failed = 0

    for ($i = 0; $i -lt $users.Count; $i++) {
        $user = $users[$i]
        Write-GuiProgress -Current ($i + 1) -Total $users.Count -Text "Aktualisiere $user"
        try {
            $params = @{}
            if ($randomNames) {
                $params.GivenName = Get-RandomFirstName
                $params.Surname = Get-RandomLastName
                $params.DisplayName = "$($params.GivenName) $($params.Surname)"
            }
            if ($randomAddresses) {
                $params.StreetAddress = Get-RandomStreetAddress
                $params.City = Get-RandomCity
                $params.PostalCode = Get-RandomPostalCode
                $params.Country = "DE"
            }
            if ($randomPhone) {
                $params.OfficePhone = Get-RandomPhoneNumber
                $params.MobilePhone = Get-RandomPhoneNumber
            }
            if ($randomDepartments) { $params.Department = Get-RandomDepartment }
            if ($randomTitles) { $params.Title = Get-RandomJobTitle }
            if ($randomCompany) { $params.Company = $companyName }

            Set-ADUser -Identity $user @params -ErrorAction Stop
            Write-AppLog "Zufallsattribute für '$user' gesetzt" -Level "DEBUG"
            $processed++
        } catch {
            Write-AppLog "Fehler beim Setzen von Zufallsattributen für '$user': $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Hide-Progress
    Write-AppLog "Zufallsattribute zugewiesen: $processed erfolgreich, $failed Fehler" -Level "INFO"
    [System.Windows.MessageBox]::Show("Zufallsattribute zugewiesen.`n`nAktualisiert: $processed`nFehler: $failed", "Vorgang abgeschlossen", "OK", "Information") | Out-Null
}

function Get-UniqueSamAccountName {
    <#
    .SYNOPSIS
    Erzeugt einen im AD und im aktuellen Lauf eindeutigen sAMAccountName (max. 20 Zeichen) aus Vor- und Nachname
    #>
    param(
        [Parameter(Mandatory = $true)][string]$GivenName,
        [Parameter(Mandatory = $true)][string]$Surname,
        [System.Collections.Generic.HashSet[string]]$UsedNames
    )

    $base = ConvertTo-NormalizedSamAccountName -SamAccountName "$GivenName.$Surname"
    # 16 Zeichen Basis + 4 Ziffern = maximal 20 Zeichen (AD-Limit)
    if ($base.Length -gt 16) { $base = $base.Substring(0, 16).TrimEnd('.', '_', '-') }

    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        $candidate = "$base$(Get-Random -Minimum 1000 -Maximum 10000)"
        if ($UsedNames -and $UsedNames.Contains($candidate)) { continue }
        $existing = Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-ADFilterValue -Value $candidate)'" -ErrorAction SilentlyContinue
        if (-not $existing) {
            if ($UsedNames) { [void]$UsedNames.Add($candidate) }
            return $candidate
        }
    }
    throw "Für '$GivenName $Surname' konnte kein eindeutiger sAMAccountName ermittelt werden."
}

function Get-AvailableObjectName {
    <#
    .SYNOPSIS
    Liefert einen im Container eindeutigen Objektnamen (CN); bei Konflikten wird der Suffix angehängt
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Suffix,
        [System.Collections.Generic.HashSet[string]]$UsedNames
    )

    $inUse = $UsedNames -and $UsedNames.Contains($Name)
    if (-not $inUse) {
        $inUse = [bool](Get-ADObject -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $Name)'" -SearchBase $Path -SearchScope OneLevel -ErrorAction SilentlyContinue)
    }
    $result = if ($inUse) { "$Name ($Suffix)" } else { $Name }
    if ($UsedNames) { [void]$UsedNames.Add($result) }
    return $result
}

function New-UserFromTemplate {
    <#
    .SYNOPSIS
    Erstellt Test-Benutzer mit zufälligen Namen auf Basis eines bestehenden Vorlagen-Benutzers

    .DESCRIPTION
    Übernimmt Abteilung, Firma, Titel, Büro, Adresse sowie die Gruppenmitgliedschaften der Vorlage.
    Geschützte/privilegierte Gruppen (adminCount = 1, z. B. Domänen-Admins) werden nie übernommen.
    Die Benutzer werden in der Test-OU (USERS) angelegt und für die Bereinigung nachverfolgt.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Benutzer-Erstellung aus Vorlage..." -Level "INFO"

    $templateName = ([string]$script:GuiControls.TextBoxTemplateUser.Text).Trim()
    if (-not $templateName) {
        Write-AppLog "Kein Vorlagen-Benutzer angegeben" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie den Anmeldenamen (sAMAccountName) eines Vorlagen-Benutzers an.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $numUsers = ConvertTo-IntOrZero -Value $script:GuiControls.TextBoxTemplateCount.Text
    if ($numUsers -lt 1 -or $numUsers -gt 500) {
        Write-AppLog "Ungültige Anzahl für Vorlagen-Benutzer: '$($script:GuiControls.TextBoxTemplateCount.Text)'" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie eine Anzahl zwischen 1 und 500 an.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    if (-not (Test-ADConnection)) { return }
    $targetOU = ([string]$script:GuiControls.ComboBoxTargetOU.Text).Trim()
    if (-not (Test-TargetOU -TargetOU $targetOU)) { return }

    $copyAttributes = @('Department', 'Company', 'Title', 'Office', 'StreetAddress', 'City', 'PostalCode', 'State', 'Country')
    $template = Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-ADFilterValue -Value $templateName)'" -Properties ($copyAttributes + 'MemberOf') -ErrorAction Stop |
        Select-Object -First 1
    if (-not $template) {
        Write-AppLog "Vorlagen-Benutzer nicht gefunden: $templateName" -Level "WARN"
        [System.Windows.MessageBox]::Show("Der Vorlagen-Benutzer '$templateName' wurde nicht gefunden.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    # Nur unkritische Gruppen übernehmen (adminCount = 1 kennzeichnet AdminSDHolder-geschützte Gruppen)
    $templateGroups = New-Object System.Collections.Generic.List[string]
    $skippedGroups = 0
    foreach ($groupDn in @($template.MemberOf)) {
        try {
            $group = Get-ADGroup -Identity $groupDn -Properties adminCount -ErrorAction Stop
            if ($group.adminCount -eq 1) { $skippedGroups++; continue }
            $templateGroups.Add($group.DistinguishedName)
        } catch {
            Write-AppLog "Gruppe '$groupDn' der Vorlage konnte nicht gelesen werden: $($_.Exception.Message)" -Level "DEBUG"
        }
    }

    $result = [System.Windows.MessageBox]::Show(
        "Sollen $numUsers Benutzer auf Basis von '$($template.SamAccountName)' erstellt werden?`n`n" +
        "Übernommen werden: Abteilung, Firma, Titel, Büro, Adresse`n" +
        "Gruppen: $($templateGroups.Count)$(if ($skippedGroups -gt 0) { " ($skippedGroups privilegierte Gruppe(n) werden ausgelassen)" })`n" +
        "Ziel: Test-OU 'USERS' unterhalb von $targetOU",
        "Benutzer aus Vorlage erstellen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess($targetOU, "$numUsers Benutzer aus Vorlage '$($template.SamAccountName)' erstellen")) { return }

    Show-Progress -Text "Erstelle Benutzer aus Vorlage..."
    $testOUs = Initialize-TestOU -BaseOU $targetOU
    $usersPath = if ($testOUs["USERS"]) { $testOUs["USERS"] } else { $targetOU }

    $usedSamNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $usedObjectNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $processed = 0
    $failed = 0

    for ($i = 1; $i -le $numUsers; $i++) {
        Write-GuiProgress -Current $i -Total $numUsers -Text "Erstelle Benutzer $i"
        try {
            $firstName = Get-RandomFirstName
            $lastName = Get-RandomLastName
            $samAccountName = Get-UniqueSamAccountName -GivenName $firstName -Surname $lastName -UsedNames $usedSamNames

            $userParams = @{
                Name = Get-AvailableObjectName -Name "$firstName $lastName" -Path $usersPath -Suffix $samAccountName -UsedNames $usedObjectNames
                SamAccountName = $samAccountName
                UserPrincipalName = Get-UserPrincipalName -SamAccountName $samAccountName
                GivenName = $firstName
                Surname = $lastName
                DisplayName = "$firstName $lastName"
                Description = "Erstellt aus Vorlage $($template.SamAccountName)"
                Path = $usersPath
                Enabled = $true
                AccountPassword = (Get-InitialUserPassword)
                ChangePasswordAtLogon = [bool]$script:AppConfig.EnablePasswordChange
            }
            foreach ($attribute in $copyAttributes) {
                if (-not [string]::IsNullOrWhiteSpace([string]$template.$attribute)) {
                    $userParams[$attribute] = $template.$attribute
                }
            }

            New-ADUser @userParams -ErrorAction Stop
            $script:CreatedUsers.Add($samAccountName)

            foreach ($groupDn in $templateGroups) {
                try {
                    Add-ADGroupMember -Identity $groupDn -Members $samAccountName -ErrorAction Stop
                } catch {
                    Write-AppLog "'$samAccountName' konnte nicht zu '$groupDn' hinzugefügt werden: $($_.Exception.Message)" -Level "WARN"
                }
            }

            Write-AppLog "Benutzer '$samAccountName' aus Vorlage erstellt" -Level "SUCCESS"
            $processed++
        } catch {
            Write-AppLog "Fehler beim Erstellen eines Benutzers aus Vorlage: $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Hide-Progress
    Show-CreatedObjectCount
    Write-AppLog "Benutzer aus Vorlage: $processed erstellt, $failed Fehler" -Level "INFO"
    [System.Windows.MessageBox]::Show("Benutzer-Erstellung aus Vorlage abgeschlossen.`n`nErstellt: $processed`nFehler: $failed`nZiel-OU: $usersPath", "Vorgang abgeschlossen", "OK", "Information") | Out-Null
}

function ConvertTo-LogonHoursBitmask {
    <#
    .SYNOPSIS
    Erzeugt die 21-Byte-Bitmaske für das AD-Attribut logonHours

    .DESCRIPTION
    logonHours enthält 168 Bits (7 Tage x 24 Stunden). Bit 0 von Byte 0 entspricht Sonntag 00:00-01:00 UTC;
    innerhalb eines Bytes ist das niederwertigste Bit die früheste Stunde. Die erlaubten Zeiten werden in
    lokaler Zeit angegeben und anhand des UTC-Offsets der Zeitzone umgerechnet.
    #>
    param(
        [int[]]$Days = @(1, 2, 3, 4, 5),
        [ValidateRange(0, 23)][int]$StartHour = 8,
        [ValidateRange(1, 24)][int]$EndHour = 17,
        [int]$UtcOffsetHours = [int][math]::Round([System.TimeZoneInfo]::Local.BaseUtcOffset.TotalHours)
    )

    $bytes = New-Object byte[] 21
    foreach ($day in $Days) {
        for ($hour = $StartHour; $hour -lt $EndHour; $hour++) {
            # Lokale Wochenstunde (0 = Sonntag 00:00) in UTC umrechnen
            $bit = ((($day * 24) + $hour - $UtcOffsetHours) % 168 + 168) % 168
            $bytes[[math]::Floor($bit / 8)] = $bytes[[math]::Floor($bit / 8)] -bor [byte](1 -shl ($bit % 8))
        }
    }
    return , $bytes
}

function Set-UserLogonHour {
    <#
    .SYNOPSIS
    Beschränkt die Anmeldezeiten aller vom Tool erstellten Benutzer auf Mo-Fr 08:00-17:00 Uhr (lokale Zeit)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Setzen von Anmeldezeiten..." -Level "INFO"

    $users = @($script:CreatedUsers)
    if ($users.Count -eq 0) {
        Write-AppLog "Keine Benutzer für Anmeldezeiten vorhanden" -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden in dieser Sitzung noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $result = [System.Windows.MessageBox]::Show(
        "Sollen die Anmeldezeiten von $($users.Count) Benutzern auf Mo-Fr 08:00-17:00 Uhr (lokale Zeit) beschränkt werden?",
        "Anmeldezeiten setzen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess("$($users.Count) Benutzer", "logonHours setzen")) { return }

    [byte[]]$logonHours = ConvertTo-LogonHoursBitmask -Days @(1, 2, 3, 4, 5) -StartHour 8 -EndHour 17

    Show-Progress -Text "Setze Anmeldezeiten..."
    $processed = 0
    $failed = 0

    for ($i = 0; $i -lt $users.Count; $i++) {
        $user = $users[$i]
        Write-GuiProgress -Current ($i + 1) -Total $users.Count -Text "Anmeldezeiten für $user"
        try {
            Set-ADUser -Identity $user -Replace @{ logonHours = $logonHours } -ErrorAction Stop
            Write-AppLog "Anmeldezeiten für '$user' gesetzt" -Level "DEBUG"
            $processed++
        } catch {
            Write-AppLog "Fehler beim Setzen der Anmeldezeiten für '$user': $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Hide-Progress
    Write-AppLog "Anmeldezeiten gesetzt: $processed erfolgreich, $failed Fehler" -Level "INFO"
    [System.Windows.MessageBox]::Show("Anmeldezeiten gesetzt (Mo-Fr 08:00-17:00 Uhr).`n`nAktualisiert: $processed`nFehler: $failed", "Vorgang abgeschlossen", "OK", "Information") | Out-Null
}

function Select-AvatarPath {
    <#
    .SYNOPSIS
    Öffnet einen Ordnerauswahl-Dialog für Avatar-Bilder
    #>
    Add-Type -AssemblyName System.Windows.Forms
    $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
    try {
        $folderBrowser.Description = "Ordner mit Avatar-Bildern (JPG, max. 100 KB) auswählen"
        $currentPath = [string]$script:GuiControls.TextBoxAvatarPath.Text
        if ($currentPath -and (Test-Path -LiteralPath $currentPath -PathType Container)) {
            $folderBrowser.SelectedPath = $currentPath
        }
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $script:GuiControls.TextBoxAvatarPath.Text = $folderBrowser.SelectedPath
            $script:GuiControls.CheckBoxGenerateAvatars.IsChecked = $false
            Write-AppLog "Avatar-Ordner ausgewählt: $($folderBrowser.SelectedPath)" -Level "INFO"
        }
    } finally {
        $folderBrowser.Dispose()
    }
}

function Set-UserAvatar {
    <#
    .SYNOPSIS
    Setzt das Profilbild (thumbnailPhoto) aller vom Tool erstellten Benutzer

    .DESCRIPTION
    Entweder werden Initialen-Avatare generiert oder zufällig JPG-Bilder aus dem gewählten Ordner verwendet.
    Bilder über 100 KB werden übersprungen (AD-Grenze für thumbnailPhoto).
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Avatar-Zuweisung..." -Level "INFO"

    $users = @($script:CreatedUsers)
    if ($users.Count -eq 0) {
        Write-AppLog "Keine Benutzer für Avatar-Zuweisung vorhanden" -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden in dieser Sitzung noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $generateAvatars = [bool]$script:GuiControls.CheckBoxGenerateAvatars.IsChecked
    $images = @()
    if (-not $generateAvatars) {
        $avatarPath = ([string]$script:GuiControls.TextBoxAvatarPath.Text).Trim()
        if (-not $avatarPath) {
            Write-AppLog "Kein Avatar-Ordner angegeben" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Ordner mit Bildern aus oder aktivieren Sie 'Avatare automatisch generieren'.", "Hinweis", "OK", "Warning") | Out-Null
            return
        }
        if (-not (Test-Path -LiteralPath $avatarPath -PathType Container)) {
            Write-AppLog "Avatar-Ordner nicht gefunden: $avatarPath" -Level "WARN"
            [System.Windows.MessageBox]::Show("Der Avatar-Ordner wurde nicht gefunden:`n$avatarPath", "Hinweis", "OK", "Warning") | Out-Null
            return
        }
        $images = @(Get-ChildItem -LiteralPath $avatarPath -File |
            Where-Object { $_.Extension -in @('.jpg', '.jpeg') -and $_.Length -le 100KB })
        if ($images.Count -eq 0) {
            Write-AppLog "Keine geeigneten Avatar-Bilder in '$avatarPath' gefunden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Im Ordner wurden keine JPG-Bilder mit höchstens 100 KB gefunden.", "Hinweis", "OK", "Warning") | Out-Null
            return
        }
    }

    $source = if ($generateAvatars) { "generierte Initialen-Avatare" } else { "$($images.Count) Bild(er) aus dem Ordner" }
    $result = [System.Windows.MessageBox]::Show(
        "Soll für $($users.Count) Benutzer das Profilbild (thumbnailPhoto) gesetzt werden?`n`nQuelle: $source",
        "Avatare zuweisen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess("$($users.Count) Benutzer", "thumbnailPhoto setzen")) { return }

    if ($generateAvatars) { Add-Type -AssemblyName System.Drawing }

    Show-Progress -Text "Weise Avatare zu..."
    $processed = 0
    $failed = 0

    for ($i = 0; $i -lt $users.Count; $i++) {
        $user = $users[$i]
        Write-GuiProgress -Current ($i + 1) -Total $users.Count -Text "Avatar für $user"
        try {
            if ($generateAvatars) {
                $userObj = Get-ADUser -Identity $user -Properties GivenName, Surname -ErrorAction Stop
                $initials = -join @(@($userObj.GivenName, $userObj.Surname) |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    ForEach-Object { $_.Trim().Substring(0, 1) })
                if (-not $initials) { $initials = $user.Substring(0, [math]::Min(2, $user.Length)) }
                [byte[]]$photo = ConvertTo-AvatarImage -Initials $initials.ToUpper() -ColorIndex $i
            } else {
                [byte[]]$photo = [System.IO.File]::ReadAllBytes(($images | Get-Random).FullName)
            }

            Set-ADUser -Identity $user -Replace @{ thumbnailPhoto = $photo } -ErrorAction Stop
            Write-AppLog "Avatar für '$user' zugewiesen" -Level "DEBUG"
            $processed++
        } catch {
            Write-AppLog "Fehler bei Avatar-Zuweisung für '$user': $($_.Exception.Message)" -Level "ERROR"
            $failed++
        }
    }

    Hide-Progress
    Write-AppLog "Avatare zugewiesen: $processed erfolgreich, $failed Fehler" -Level "INFO"
    [System.Windows.MessageBox]::Show("Avatar-Zuweisung abgeschlossen.`n`nAktualisiert: $processed`nFehler: $failed", "Vorgang abgeschlossen", "OK", "Information") | Out-Null
}

function New-TestEnvironment {
    <#
    .SYNOPSIS
    Erstellt die komplette Test-Umgebung mit allen benötigten OUs
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Test-Umgebung Erstellung..." -Level "INFO"

        $companyName = $script:GuiControls.TextBoxCompanyName.Text
        if ([string]::IsNullOrWhiteSpace($companyName)) {
            $companyName = "TestCompany"
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie die Test-Umgebung '$companyName' erstellen?`n`n" +
            "Folgende OUs werden erstellt:`n" +
            "- OU=$companyName`n" +
            "  - OU=USERS`n" +
            "  - OU=GROUPS`n" +
            "  - OU=COMPUTERS`n" +
            "  - OU=SERVICES`n" +
            "  - OU=RESOURCES",
            "Test-Umgebung erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess("OU=$companyName (Domänenstamm)", "Test-Umgebung erstellen")) { return }

        Show-Progress -Text "Erstelle Test-Umgebung..."

        # Basis-OU ermitteln
        $domain = Get-ADDomain
        $baseOU = $domain.DistinguishedName

        # Haupt-OU erstellen
        $companyOU = "OU=$companyName,$baseOU"

        try {
            # Prüfe ob Haupt-OU bereits existiert
            $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$(ConvertTo-ADFilterValue -Value $companyOU)'" -ErrorAction SilentlyContinue

            if (-not $existingOU) {
                New-ADOrganizationalUnit -Name $companyName `
                    -Path $baseOU `
                    -Description "Wurzel-OU der Test-Umgebung" `
                    -ProtectedFromAccidentalDeletion $false `
                    -ErrorAction Stop

                $script:CreatedOUs.Add($companyOU)
                Write-AppLog "Haupt-OU '$companyName' erstellt" -Level "SUCCESS"
            } else {
                Write-AppLog "Haupt-OU '$companyName' existiert bereits" -Level "INFO"
            }

            # Erstelle Unter-OUs
            $subOUs = @{
                "USERS" = "Test-Benutzerkonten"
                "GROUPS" = "Test-Sicherheitsgruppen"
                "COMPUTERS" = "Test-Computerkonten"
                "SERVICES" = "Test-Dienstkonten"
                "RESOURCES" = "Test-Ressourcen"
            }

            foreach ($ouName in $subOUs.Keys) {
                $ouPath = "OU=$ouName,$companyOU"

                try {
                    $existingSubOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$(ConvertTo-ADFilterValue -Value $ouPath)'" -ErrorAction SilentlyContinue

                    if (-not $existingSubOU) {
                        New-ADOrganizationalUnit -Name $ouName `
                            -Path $companyOU `
                            -Description $subOUs[$ouName] `
                            -ProtectedFromAccidentalDeletion $false `
                            -ErrorAction Stop

                        $script:CreatedOUs.Add($ouPath)
                        Write-AppLog "Unter-OU '$ouName' erstellt" -Level "SUCCESS"
                    }
                } catch {
                    Write-AppLog "Fehler beim Erstellen der OU '$ouName': $($_.Exception.Message)" -Level "ERROR"
                }
            }

            # Aktualisiere OU-Dropdown
            Initialize-OUDropdown

            # Setze die neue OU als Standard
            $script:GuiControls.ComboBoxTargetOU.Text = $companyOU

            Hide-Progress
            Show-CreatedObjectCount

            [System.Windows.MessageBox]::Show(
                "Test-Umgebung erfolgreich erstellt!`n`n" +
                "Basis-OU: $companyOU`n" +
                "Die OU wurde als Ziel-OU ausgewählt.",
                "Erfolg",
                "OK",
                "Information"
            )

        } catch {
            Write-AppLog "Fehler beim Erstellen der Test-Umgebung: $($_.Exception.Message)" -Level "ERROR"
            throw
        }

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Test-Umgebung Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-RandomUser {
    <#
    .SYNOPSIS
    Erstellt zufällige Benutzer basierend auf den GUI-Einstellungen
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Erstellung von Zufallsbenutzern..." -Level "INFO"

    $userCountText = [string]$script:GuiControls.TextBoxRandomUserCount.Text
    $userCount = if ([string]::IsNullOrWhiteSpace($userCountText)) { 50 } else { ConvertTo-IntOrZero -Value $userCountText }
    if ($userCount -le 0) {
        Write-AppLog "Ungültige Anzahl Benutzer: '$userCountText'" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Benutzern an.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $targetOU = ([string]$script:GuiControls.ComboBoxTargetOU.Text).Trim()
    if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
        Write-AppLog "Keine gültige Ziel-OU ausgewählt" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte erstellen Sie zuerst eine Test-Umgebung oder wählen Sie eine gültige Ziel-OU.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }
    if (-not (Test-TargetOU -TargetOU $targetOU)) { return }

    # USERS-Unter-OU verwenden, falls vorhanden
    $userOU = $targetOU
    $testUserOU = "OU=USERS,$targetOU"
    $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$(ConvertTo-ADFilterValue -Value $testUserOU)'" -ErrorAction SilentlyContinue
    if ($existingOU) {
        $userOU = $testUserOU
        Write-AppLog "Verwende USERS-OU: $userOU" -Level "DEBUG"
    }

    $randomAddresses = [bool]$script:GuiControls.CheckBoxRandomAddresses.IsChecked
    $randomPhone = [bool]$script:GuiControls.CheckBoxRandomPhone.IsChecked
    $randomDepartments = [bool]$script:GuiControls.CheckBoxRandomDepartments.IsChecked
    $randomTitles = [bool]$script:GuiControls.CheckBoxRandomTitles.IsChecked
    $randomCompany = [bool]$script:GuiControls.CheckBoxRandomCompany.IsChecked
    $setExpiryDate = [bool]$script:GuiControls.CheckBoxSetExpiryDate.IsChecked
    $temporaryAccount = [bool]$script:GuiControls.CheckBoxTemporaryAccount.IsChecked

    # Passwort-Optionen (gelten nur, wenn kein Initialpasswort eingegeben wurde)
    $passwordOptions = @{
        Complexity = if ($script:GuiControls.ComboBoxPasswordComplexity.SelectedItem) { [string]$script:GuiControls.ComboBoxPasswordComplexity.SelectedItem.Content } else { "Mittel (12 Zeichen + Symbole)" }
        IncludeNumbers = [bool]$script:GuiControls.CheckBoxIncludeNumbers.IsChecked
        IncludeSymbols = [bool]$script:GuiControls.CheckBoxIncludeSymbols.IsChecked
        ExcludeAmbiguous = [bool]$script:GuiControls.CheckBoxExcludeAmbiguous.IsChecked
    }
    $usesGuiPassword = $script:GuiControls.PasswordBoxInitialPassword -and $script:GuiControls.PasswordBoxInitialPassword.SecurePassword.Length -gt 0
    $passwordInfo = if ($usesGuiPassword) { "Initialpasswort aus dem Eingabefeld" } else { "zufällig ($($passwordOptions.Complexity), nicht gespeichert)" }
    $expiryInfo = if ($temporaryAccount) { "in 30 Tagen (temporär)" } elseif ($setExpiryDate) { "zufällig in 30-365 Tagen" } else { "keins" }

    $companyName = ([string]$script:GuiControls.TextBoxCompanyName.Text).Trim()
    if (-not $companyName) { $companyName = "Testfirma" }

    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie $userCount zufällige Benutzer erstellen?`n`n" +
        "Ziel-OU: $userOU`n" +
        "Zufällige Adressen: $(if ($randomAddresses) { 'Ja' } else { 'Nein' })`n" +
        "Zufällige Telefonnummern: $(if ($randomPhone) { 'Ja' } else { 'Nein' })`n" +
        "Passwort: $passwordInfo`n" +
        "Kontoablauf: $expiryInfo",
        "Zufallsbenutzer erstellen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess($userOU, "$userCount Zufallsbenutzer erstellen")) { return }

    Show-Progress -Text "Erstelle zufällige Benutzer..."
    $successCount = 0
    $errorCount = 0
    $usedSamNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $usedObjectNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    for ($i = 1; $i -le $userCount; $i++) {
        Write-GuiProgress -Current $i -Total $userCount -Text "Erstelle Benutzer"

        try {
            $firstName = Get-RandomFirstName
            $lastName = Get-RandomLastName
            $samAccountName = Get-UniqueSamAccountName -GivenName $firstName -Surname $lastName -UsedNames $usedSamNames

            $userParams = @{
                Name = Get-AvailableObjectName -Name "$firstName $lastName" -Path $userOU -Suffix $samAccountName -UsedNames $usedObjectNames
                SamAccountName = $samAccountName
                UserPrincipalName = Get-UserPrincipalName -SamAccountName $samAccountName
                GivenName = $firstName
                Surname = $lastName
                DisplayName = "$firstName $lastName"
                Path = $userOU
                Enabled = $true
                AccountPassword = (Get-InitialUserPassword @passwordOptions)
                ChangePasswordAtLogon = $false
            }

            if ($randomAddresses) {
                $userParams.StreetAddress = Get-RandomStreetAddress
                $userParams.City = Get-RandomCity
                $userParams.PostalCode = Get-RandomPostalCode
                $userParams.Country = "DE"
            }
            if ($randomPhone) {
                $userParams.OfficePhone = Get-RandomPhoneNumber
                $userParams.MobilePhone = Get-RandomPhoneNumber
            }
            if ($randomDepartments) { $userParams.Department = Get-RandomDepartment }
            if ($randomTitles) { $userParams.Title = Get-RandomJobTitle }
            if ($randomCompany) { $userParams.Company = $companyName }

            if ($temporaryAccount) {
                $userParams.AccountExpirationDate = (Get-Date).Date.AddDays(30)
                $userParams.Description = "Temporäres Testkonto (läuft nach 30 Tagen ab)"
            } elseif ($setExpiryDate) {
                $userParams.AccountExpirationDate = (Get-Date).Date.AddDays((Get-Random -Minimum 30 -Maximum 366))
            }

            New-ADUser @userParams -ErrorAction Stop
            $script:CreatedUsers.Add($samAccountName)
            $successCount++
        } catch {
            Write-AppLog "Fehler beim Erstellen eines Zufallsbenutzers: $($_.Exception.Message)" -Level "ERROR"
            $errorCount++
        }
    }

    Hide-Progress
    Show-CreatedObjectCount
    Write-AppLog "Zufallsbenutzer erstellt: $successCount erfolgreich, $errorCount Fehler" -Level "INFO"

    $passwordHint = if ($usesGuiPassword) { "" } else { "`n`nHinweis: Jeder Benutzer hat ein eigenes, zufälliges Passwort erhalten (nicht gespeichert)." }
    [System.Windows.MessageBox]::Show("Zufallsbenutzer erstellt.`n`nErstellt: $successCount`nFehler: $errorCount`nZiel-OU: $userOU$passwordHint", "Zufallsbenutzer erstellt", "OK", "Information") | Out-Null
}

function Export-CreatedObject {
    <#
    .SYNOPSIS
    Exportiert alle erstellten Objekte in eine CSV-Datei
    #>
    try {
        Write-AppLog "Starte Export aller Objekte..." -Level "INFO"

        $totalObjects = $script:CreatedUsers.Count + $script:CreatedGroups.Count +
                       $script:CreatedComputers.Count + $script:CreatedOUs.Count +
                       $script:CreatedServiceAccounts.Count + $script:CreatedPrinters.Count

        if ($totalObjects -eq 0) {
            Write-AppLog "Keine Objekte zum Exportieren vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Objekte erstellt.", "Hinweis", "OK", "Information")
            return
        }

        Show-Progress -Text "Exportiere Objekte..."

        $exportData = New-Object System.Collections.Generic.List[object]

        # Benutzer exportieren
        foreach ($user in $script:CreatedUsers) {
            try {
                $adUser = Get-ADUser -Identity $user -Properties whenCreated -ErrorAction Stop
                $exportData.Add([PSCustomObject]@{
                    ObjectType = "User"
                    Name = $adUser.Name
                    SamAccountName = $adUser.SamAccountName
                    DistinguishedName = $adUser.DistinguishedName
                    Created = $adUser.whenCreated
                    Enabled = $adUser.Enabled
                })
            } catch {
                Write-AppLog "Fehler beim Export von Benutzer '$user': $($_.Exception.Message)" -Level "WARN"
            }
        }

        # Gruppen exportieren
        foreach ($group in $script:CreatedGroups) {
            try {
                $adGroup = Get-ADGroup -Identity $group -Properties whenCreated -ErrorAction Stop
                $exportData.Add([PSCustomObject]@{
                    ObjectType = "Group"
                    Name = $adGroup.Name
                    SamAccountName = $adGroup.SamAccountName
                    DistinguishedName = $adGroup.DistinguishedName
                    Created = $adGroup.whenCreated
                    Enabled = "N/A"
                })
            } catch {
                Write-AppLog "Fehler beim Export von Gruppe '$group': $($_.Exception.Message)" -Level "WARN"
            }
        }

        # Computer exportieren
        foreach ($computer in $script:CreatedComputers) {
            try {
                $adComputer = Get-ADComputer -Identity $computer -Properties whenCreated -ErrorAction Stop
                $exportData.Add([PSCustomObject]@{
                    ObjectType = "Computer"
                    Name = $adComputer.Name
                    SamAccountName = $adComputer.SamAccountName
                    DistinguishedName = $adComputer.DistinguishedName
                    Created = $adComputer.whenCreated
                    Enabled = $adComputer.Enabled
                })
            } catch {
                Write-AppLog "Fehler beim Export von Computer '$computer': $($_.Exception.Message)" -Level "WARN"
            }
        }

        # OUs dokumentieren
        foreach ($ou in $script:CreatedOUs) {
            $exportData.Add([PSCustomObject]@{
                ObjectType = "OU"
                Name = (($ou -split ',')[0] -replace 'OU=', '')
                SamAccountName = "N/A"
                DistinguishedName = $ou
                Created = "N/A"
                Enabled = "N/A"
            })
        }

        # Dienstkonten exportieren
        foreach ($service in $script:CreatedServiceAccounts) {
            try {
                $adService = Get-ADUser -Identity $service -Properties whenCreated -ErrorAction Stop
                $exportData.Add([PSCustomObject]@{
                    ObjectType = "ServiceAccount"
                    Name = $adService.Name
                    SamAccountName = $adService.SamAccountName
                    DistinguishedName = $adService.DistinguishedName
                    Created = $adService.whenCreated
                    Enabled = $adService.Enabled
                })
            } catch {
                Write-AppLog "Fehler beim Export von Dienstkonto '$service': $($_.Exception.Message)" -Level "WARN"
            }
        }

        # Drucker exportieren
        foreach ($printerDn in $script:CreatedPrinters) {
            try {
                $adPrinter = Get-ADObject -Identity $printerDn -Properties whenCreated -ErrorAction Stop
                $exportData.Add([PSCustomObject]@{
                    ObjectType = "Printer"
                    Name = $adPrinter.Name
                    SamAccountName = "N/A"
                    DistinguishedName = $adPrinter.DistinguishedName
                    Created = $adPrinter.whenCreated
                    Enabled = "N/A"
                })
            } catch {
                Write-AppLog "Fehler beim Export von Drucker '$printerDn': $($_.Exception.Message)" -Level "WARN"
            }
        }

        # Export
        $exportPath = (Get-ExportFilePath -FileName "AllCreatedObjects_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
        $exportData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

        Hide-Progress

        $message = "Export erfolgreich abgeschlossen:`n`nExportierte Objekte: $($exportData.Count)`n- Benutzer: $($script:CreatedUsers.Count)`n- Gruppen: $($script:CreatedGroups.Count)`n- Computer: $($script:CreatedComputers.Count)`n- OUs: $($script:CreatedOUs.Count)`n- Dienstkonten: $($script:CreatedServiceAccounts.Count)`n- Drucker: $($script:CreatedPrinters.Count)`n`nDatei: $exportPath"

        [System.Windows.MessageBox]::Show($message, "Export abgeschlossen", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler beim Export: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Export:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-StandardTestGroup {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Schnell-Erstellung von Gruppen..." -Level "INFO"

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie Standard-Gruppen erstellen?`n`n- Benutzer`n- Administratoren`n- Gäste",
            "Gruppen erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess("Test-OU GROUPS", "Standard-Testgruppen erstellen")) { return }

        Show-Progress -Text "Erstelle Gruppen..."
        $processed = 0
        $failed = 0

        $groups = @(
            @{Name="Benutzer"; Description="Standardbenutzer"},
            @{Name="Administratoren"; Description="Administratoren mit erweiterten Rechten"},
            @{Name="Gäste"; Description="Eingeschränkte Gastbenutzer"}
        )

        $current = 0
        foreach ($group in $groups) {
            $current++
            try {
                # Vorhandene (z.B. integrierte) Gruppen gleichen Namens nicht anfassen
                $existing = Get-ADGroup -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $group.Name)' -or SamAccountName -eq '$(ConvertTo-ADFilterValue -Value $group.Name)'" -ErrorAction SilentlyContinue
                if ($existing) {
                    Write-AppLog "Gruppe $($group.Name) existiert bereits, übersprungen" -Level "WARN"
                    $failed++
                } else {
                    New-ADGroup -Name $group.Name `
                        -GroupScope Global `
                        -GroupCategory Security `
                        -Description $group.Description `
                        -ErrorAction Stop

                    $script:CreatedGroups.Add($group.Name)
                    Write-AppLog "Gruppe $($group.Name) erfolgreich erstellt" -Level "SUCCESS"
                    $processed++
                }
            }
            catch {
                Write-AppLog "Fehler beim Erstellen der Gruppe $($group.Name): $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }

            Write-GuiProgress -Current $current -Total $groups.Count
        }

        Hide-Progress
        Show-CreatedObjectCount
        [System.Windows.MessageBox]::Show("Gruppen-Erstellung abgeschlossen.`n$processed Gruppen erstellt, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-AppLog "Fehler bei Gruppen-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Initialize-TestOU {
    <#
    .SYNOPSIS
    Erstellt dedizierte Test-OUs für verschiedene Objekttypen
    #>
    param(
        [string]$BaseOU
    )

    try {
        Write-AppLog "Erstelle dedizierte Test-OUs..." -Level "INFO"

        $testOUs = @{
            "USERS" = "Test-Benutzerkonten"
            "GROUPS" = "Test-Sicherheitsgruppen"
            "COMPUTERS" = "Test-Computerkonten"
            "SERVICES" = "Test-Dienstkonten"
            "RESOURCES" = "Test-Ressourcen"
        }

        $createdOUs = @{}

        foreach ($ouName in $testOUs.Keys) {
            $ouPath = "OU=$ouName,$BaseOU"

            try {
                # Prüfe ob OU bereits existiert
                $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$(ConvertTo-ADFilterValue -Value $ouPath)'" -ErrorAction SilentlyContinue

                if (-not $existingOU) {
                    New-ADOrganizationalUnit -Name $ouName `
                        -Path $BaseOU `
                        -Description $testOUs[$ouName] `
                        -ProtectedFromAccidentalDeletion $false `
                        -ErrorAction Stop

                    $script:CreatedOUs.Add($ouPath)
                    Write-AppLog "Test-OU '$ouName' erstellt: $ouPath" -Level "SUCCESS"
                } else {
                    Write-AppLog "Test-OU '$ouName' existiert bereits: $ouPath" -Level "INFO"
                }

                # Immer zum Dictionary hinzufügen, auch wenn sie bereits existiert
                $createdOUs[$ouName] = $ouPath

            } catch {
                Write-AppLog "Fehler beim Erstellen der Test-OU '$ouName': $($_.Exception.Message)" -Level "ERROR"
                # Fallback zur Basis-OU
                $createdOUs[$ouName] = $BaseOU
            }
        }

        return $createdOUs

    } catch {
        Write-AppLog "Fehler beim Erstellen der Test-OUs: $($_.Exception.Message)" -Level "ERROR"
        return @{}
    }
}

function New-QuickTestDataSet {
    <#
    .SYNOPSIS
    Erstellt einen kleinen Testdatensatz (Benutzer mit Zufallsattributen und Abteilungsgruppen) in den Test-OUs
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Erstellung von Testdaten..." -Level "INFO"

        # Ermittle Ziel-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        # Anzahl der zu erstellenden Benutzer aus TextBox oder Standard
        $numUsers = 10
        $parsedNum = 0
        if ([int]::TryParse(([string]$script:GuiControls.TextBoxNumUsersToCreate.Text).Trim(), [ref]$parsedNum) -and $parsedNum -gt 0) {
            $numUsers = $parsedNum
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie einen Testdatensatz erstellen?`n`n- $numUsers Testbenutzer (in OU=USERS)`n- 5 Testgruppen (in OU=GROUPS)`n- Zufällige Attribute`n`nBasis-OU: $targetOU",
            "Testdaten erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "Komplettes Testdaten-Set erstellen")) { return }

        Show-Progress -Text "Erstelle Testdaten..."

        # Erstelle dedizierte Test-OUs
        $testOUs = Initialize-TestOU -BaseOU $targetOU

        # Verwende die USERS OU für Benutzer
        $userOU = if ($testOUs["USERS"]) { $testOUs["USERS"] } else { $targetOU }
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }

        # Testbenutzer erstellen
        $userSuccess = 0
        $userError = 0
        $departments = @("IT", "HR", "Finance", "Sales", "Marketing")
        $usersByDepartment = @{}
        foreach ($dept in $departments) { $usersByDepartment[$dept] = New-Object System.Collections.Generic.List[string] }
        $usedSamNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $usedCNs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        for ($i = 1; $i -le $numUsers; $i++) {
            try {
                # Zufällige Daten generieren
                $firstName = Get-RandomFirstName
                $lastName = Get-RandomLastName
                $department = $departments | Get-Random
                $title = Get-RandomJobTitle
                $city = Get-RandomCity
                # Eindeutiger sAMAccountName (max. 20 Zeichen) und eindeutiger CN in der Ziel-OU
                $samAccountName = Get-UniqueSamAccountName -GivenName $firstName -Surname $lastName -UsedNames $usedSamNames
                $commonName = Get-AvailableObjectName -Name "$firstName $lastName" -Path $userOU -Suffix $samAccountName -UsedNames $usedCNs

                $user = @{
                    Name = $commonName
                    SamAccountName = $samAccountName
                    UserPrincipalName = (Get-UserPrincipalName -SamAccountName $samAccountName)
                    GivenName = $firstName
                    Surname = $lastName
                    DisplayName = "$firstName $lastName"
                    Department = $department
                    Title = $title
                    City = $city
                    Company = "Testfirma"
                    StreetAddress = Get-RandomStreetAddress
                    PostalCode = Get-RandomPostalCode
                    OfficePhone = Get-RandomPhoneNumber
                    Path = $userOU
                    Enabled = $true
                    AccountPassword = (Get-InitialUserPassword)
                    ChangePasswordAtLogon = $true
                }

                New-ADUser @user -ErrorAction Stop
                $script:CreatedUsers.Add($user.SamAccountName)
                $usersByDepartment[$department].Add($user.SamAccountName)
                Write-AppLog "Testbenutzer '$($user.DisplayName)' in OU '$userOU' erstellt" -Level "SUCCESS"
                $userSuccess++
            }
            catch {
                Write-AppLog "Fehler beim Erstellen von Testbenutzer $($i): $($_.Exception.Message)" -Level "ERROR"
                $userError++
            }

            Write-GuiProgress -Current $i -Total $numUsers -Text "Erstelle Testbenutzer"
        }

        # Testgruppen erstellen
        Write-GuiProgress -Current 0 -Total 5 -Text "Erstelle Testgruppen..."
        $groupSuccess = 0
        $groupError = 0

        # Erstelle Gruppen basierend auf den verwendeten Departments

        foreach ($dept in $departments) {
            try {
                $groupName = "TEST_${dept}_Users"
                New-ADGroup -Name $groupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description "Testgruppe für $dept" `
                    -Path $groupOU `
                    -ErrorAction Stop

                $script:CreatedGroups.Add($groupName)
                Write-AppLog "Testgruppe '$groupName' erstellt" -Level "SUCCESS"
                $groupSuccess++

                # Füge die in diesem Lauf erstellten Benutzer der Abteilung hinzu (ein AD-Aufruf pro Gruppe)
                $deptUsers = $usersByDepartment[$dept]
                if ($deptUsers.Count -gt 0) {
                    try {
                        Add-ADGroupMember -Identity $groupName -Members $deptUsers.ToArray() -ErrorAction Stop
                        Write-AppLog "$($deptUsers.Count) Benutzer zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                    } catch {
                        Write-AppLog "Fehler beim Hinzufügen von Benutzern zu Gruppe '$groupName': $($_.Exception.Message)" -Level "WARN"
                    }
                }
            }
            catch {
                Write-AppLog "Fehler beim Erstellen von Testgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                $groupError++
            }
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = @"
Testdaten erfolgreich erstellt:

Benutzer:
- Erstellt: $userSuccess
- Fehler: $userError
- Ziel-OU: $userOU

Gruppen:
- Erstellt: $groupSuccess
- Fehler: $groupError

Die Benutzer wurden mit zufälligen Attributen und
zufälligen Initial-Passwörtern erstellt.
"@

        [System.Windows.MessageBox]::Show($message, "Testdaten erstellt", "OK", "Information")

    }
    catch {
        Write-AppLog "Fehler bei Testdaten-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Test-ADIdentityNotFound {
    <#
    .SYNOPSIS
    Prüft, ob ein Fehler "Objekt nicht gefunden" bedeutet (Objekt existiert bereits nicht mehr)
    #>
    param($ErrorRecord)
    return ($ErrorRecord -and $ErrorRecord.Exception -and $ErrorRecord.Exception.GetType().Name -eq 'ADIdentityNotFoundException')
}

function Get-OUContentOwnership {
    <#
    .SYNOPSIS
    Ermittelt, welche Objekte unterhalb einer OU von diesem Tool erstellt wurden und welche nicht (Fremdobjekte)
    #>
    param([Parameter(Mandatory = $true)][string]$OUDistinguishedName)

    $comparer = [System.StringComparer]::OrdinalIgnoreCase
    $ownedSam = New-Object 'System.Collections.Generic.HashSet[string]' ($comparer)
    foreach ($name in @($script:CreatedUsers) + @($script:CreatedServiceAccounts) + @($script:CreatedGroups)) {
        if ($name) { [void]$ownedSam.Add([string]$name) }
    }
    foreach ($name in $script:CreatedComputers) {
        if ($name) { [void]$ownedSam.Add(([string]$name).TrimEnd('$') + '$') }
    }
    $ownedOUs = New-Object 'System.Collections.Generic.HashSet[string]' ($comparer)
    foreach ($ou in $script:CreatedOUs) { if ($ou) { [void]$ownedOUs.Add([string]$ou) } }

    $ownedLeafDNs = New-Object 'System.Collections.Generic.HashSet[string]' ($comparer)
    foreach ($printerDn in $script:CreatedPrinters) { if ($printerDn) { [void]$ownedLeafDNs.Add([string]$printerDn) } }
    $foreign = New-Object System.Collections.Generic.List[object]
    $ownedNames = New-Object System.Collections.Generic.List[string]

    # Nur lesend und auf die betroffene OU beschränkt
    $objects = @(Get-ADObject -SearchBase $OUDistinguishedName -SearchScope Subtree -Filter * -Properties sAMAccountName -ErrorAction Stop |
        Sort-Object { $_.DistinguishedName.Length })

    foreach ($obj in $objects) {
        $dn = [string]$obj.DistinguishedName
        if ($comparer.Equals($dn, $OUDistinguishedName)) { continue }

        $parentDn = ([regex]'(?<!\\),').Split($dn, 2)[1]
        $sam = [string]$obj.sAMAccountName

        if ($obj.ObjectClass -eq 'organizationalUnit' -and $ownedOUs.Contains($dn)) {
            continue
        } elseif ($ownedLeafDNs.Contains($dn)) {
            # Vom Tool erstellter Drucker (printQueue, ohne sAMAccountName)
            continue
        } elseif ($sam -and $ownedSam.Contains($sam)) {
            [void]$ownedLeafDNs.Add($dn)
            $ownedNames.Add($sam.TrimEnd('$'))
            if ($sam.EndsWith('$')) { $ownedNames.Add($sam) }
        } elseif ($parentDn -and $ownedLeafDNs.Contains($parentDn)) {
            # Unterobjekt eines Tool-Objekts (z.B. BitLocker-Recovery-Information eines Computers)
            [void]$ownedLeafDNs.Add($dn)
        } else {
            $foreign.Add($obj)
        }
    }

    return [PSCustomObject]@{
        Foreign    = $foreign
        OwnedNames = $ownedNames
    }
}

function Remove-ToolCreatedOU {
    <#
    .SYNOPSIS
    Löscht eine vom Tool erstellte OU. Enthält sie Objekte, die NICHT vom Tool erstellt wurden,
    wird vor dem rekursiven Löschen explizit nachgefragt.
    .OUTPUTS
    'Deleted', 'NotFound' oder 'Skipped'
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)][string]$DistinguishedName)

    $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$(ConvertTo-ADFilterValue -Value $DistinguishedName)'" -ErrorAction SilentlyContinue
    if (-not $existingOU) {
        Write-AppLog "OU '$DistinguishedName' nicht gefunden, übersprungen" -Level "WARN"
        return 'NotFound'
    }

    $ownership = Get-OUContentOwnership -OUDistinguishedName $DistinguishedName
    if ($ownership.Foreign.Count -gt 0) {
        $sample = ($ownership.Foreign | Select-Object -First 5 | ForEach-Object { "- $($_.DistinguishedName)" }) -join "`n"
        Write-AppLog "OU '$DistinguishedName' enthält $($ownership.Foreign.Count) Fremdobjekt(e)" -Level "WARN"
        Set-UiBusyState -Busy $false
        $answer = [System.Windows.MessageBox]::Show(
            "Die OU`n$DistinguishedName`nenthält $($ownership.Foreign.Count) Objekt(e), die NICHT von diesem Tool erstellt wurden, z.B.:`n$sample`n`n" +
            "Soll die OU trotzdem INKLUSIVE dieser Objekte gelöscht werden?`n(Nein = OU wird übersprungen)",
            "Fremdobjekte in OU gefunden", "YesNo", "Warning", "No")
        Set-UiBusyState -Busy $true
        if ($answer -ne "Yes") {
            Write-AppLog "OU '$DistinguishedName' wegen Fremdobjekten übersprungen" -Level "WARN"
            return 'Skipped'
        }
        Write-AppLog "Löschen der OU '$DistinguishedName' inkl. Fremdobjekten vom Benutzer bestätigt" -Level "WARN"
    }

    if (-not $PSCmdlet.ShouldProcess($DistinguishedName, "OU rekursiv löschen")) { return 'Skipped' }

    # Schutz vor versehentlichem Löschen entfernen und OU rekursiv löschen
    Set-ADOrganizationalUnit -Identity $DistinguishedName -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
    Remove-ADOrganizationalUnit -Identity $DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop

    # Mitgelöschte Tool-Objekte aus den Nachverfolgungslisten entfernen
    foreach ($name in $ownership.OwnedNames) {
        foreach ($list in @($script:CreatedUsers, $script:CreatedServiceAccounts, $script:CreatedGroups, $script:CreatedComputers)) {
            while ($list.Remove($name)) { }
        }
    }
    foreach ($ou in @($script:CreatedOUs)) {
        if ($ou -like "*,$DistinguishedName") { [void]$script:CreatedOUs.Remove($ou) }
    }
    foreach ($printerDn in @($script:CreatedPrinters)) {
        if ($printerDn -like "*,$DistinguishedName") { [void]$script:CreatedPrinters.Remove($printerDn) }
    }
    return 'Deleted'
}

function Remove-CreatedGroup {
    <#
    .SYNOPSIS
    Löscht alle erstellten Gruppen
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Löschung aller erstellten Gruppen..." -Level "INFO"

        if (-not $script:CreatedGroups -or $script:CreatedGroups.Count -eq 0) {
            Write-AppLog "Keine Gruppen zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Gruppen erstellt.", "Hinweis", "OK", "Information")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($script:CreatedGroups.Count) erstellten Gruppen löschen?`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "Gruppen löschen", "YesNo", "Warning")

        if ($result -ne "Yes") {
            Write-AppLog "Gruppenlöschung abgebrochen" -Level "INFO"
            return
        }
        if (-not $PSCmdlet.ShouldProcess("$($script:CreatedGroups.Count) erstellte Gruppen", "Löschen")) { return }

        Show-Progress -Text "Lösche Gruppen..."

        $deletedCount = 0
        $errorCount = 0
        $total = $script:CreatedGroups.Count

        # In umgekehrter Reihenfolge löschen (zuletzt erstellte zuerst)
        $groupsToDelete = @(@($script:CreatedGroups) | Sort-Object -Descending)

        for ($i = 0; $i -lt $groupsToDelete.Count; $i++) {
            $groupName = $groupsToDelete[$i]
            Write-GuiProgress -Current ($i + 1) -Total $total -Text "Lösche Gruppe: $groupName"

            try {
                Remove-ADGroup -Identity $groupName -Confirm:$false -ErrorAction Stop
                Write-AppLog "Gruppe '$groupName' gelöscht" -Level "SUCCESS"
                $deletedCount++
                [void]$script:CreatedGroups.Remove($groupName)
            } catch {
                if (Test-ADIdentityNotFound -ErrorRecord $_) {
                    Write-AppLog "Gruppe '$groupName' existiert nicht mehr" -Level "INFO"
                    [void]$script:CreatedGroups.Remove($groupName)
                } else {
                    Write-AppLog "Fehler beim Löschen der Gruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }

        # Nicht gelöschte Gruppen bleiben in der Liste, damit sie erneut bereinigt werden können

        Hide-Progress
        Show-CreatedObjectCount

        $message = "Gruppenlöschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Gruppenlöschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Gruppenlöschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Remove-CreatedComputer {
    <#
    .SYNOPSIS
    Löscht alle erstellten Computer
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Löschung aller erstellten Computer..." -Level "INFO"

        if (-not $script:CreatedComputers -or $script:CreatedComputers.Count -eq 0) {
            Write-AppLog "Keine Computer zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Information")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($script:CreatedComputers.Count) erstellten Computer löschen?`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "Computer löschen", "YesNo", "Warning")

        if ($result -ne "Yes") {
            Write-AppLog "Computerlöschung abgebrochen" -Level "INFO"
            return
        }
        if (-not $PSCmdlet.ShouldProcess("$($script:CreatedComputers.Count) erstellte Computer", "Löschen")) { return }

        Show-Progress -Text "Lösche Computer..."

        $deletedCount = 0
        $errorCount = 0
        $total = $script:CreatedComputers.Count

        $computersToDelete = @($script:CreatedComputers)
        for ($i = 0; $i -lt $computersToDelete.Count; $i++) {
            $computerName = $computersToDelete[$i]
            Write-GuiProgress -Current ($i + 1) -Total $total -Text "Lösche Computer: $computerName"

            try {
                # Recursive: entfernt auch vom Tool angelegte Unterobjekte (z.B. BitLocker-Recovery-Informationen)
                Get-ADComputer -Identity $computerName -ErrorAction Stop | Remove-ADObject -Recursive -Confirm:$false -ErrorAction Stop
                Write-AppLog "Computer '$computerName' gelöscht" -Level "SUCCESS"
                $deletedCount++
                [void]$script:CreatedComputers.Remove($computerName)
            } catch {
                if (Test-ADIdentityNotFound -ErrorRecord $_) {
                    Write-AppLog "Computer '$computerName' existiert nicht mehr" -Level "INFO"
                    [void]$script:CreatedComputers.Remove($computerName)
                } else {
                    Write-AppLog "Fehler beim Löschen des Computers '$computerName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }

        # Nicht gelöschte Computer bleiben in der Liste

        Hide-Progress
        Show-CreatedObjectCount

        $message = "Computerlöschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Computerlöschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Computerlöschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Remove-CreatedOU {
    <#
    .SYNOPSIS
    Löscht alle erstellten OUs
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Löschung aller erstellten OUs..." -Level "INFO"

        if (-not $script:CreatedOUs -or $script:CreatedOUs.Count -eq 0) {
            Write-AppLog "Keine OUs zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine OUs erstellt.", "Hinweis", "OK", "Information")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($script:CreatedOUs.Count) erstellten OUs löschen?`n`n" +
            "ACHTUNG: Dies löscht auch alle Objekte in diesen OUs!`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "OUs löschen", "YesNo", "Warning")

        if ($result -ne "Yes") {
            Write-AppLog "OU-Löschung abgebrochen" -Level "INFO"
            return
        }
        if (-not $PSCmdlet.ShouldProcess("$($script:CreatedOUs.Count) erstellte OUs", "Löschen")) { return }

        Show-Progress -Text "Lösche OUs..."

        $deletedCount = 0
        $errorCount = 0
        $skippedCount = 0

        # Sortiere OUs nach Tiefe (tiefste zuerst)
        $ousToDelete = @(@($script:CreatedOUs) | Sort-Object { ($_ -split ',').Count } -Descending)
        $total = $ousToDelete.Count

        for ($i = 0; $i -lt $ousToDelete.Count; $i++) {
            $ou = $ousToDelete[$i]
            Write-GuiProgress -Current ($i + 1) -Total $total -Text "Lösche OU: $ou"

            try {
                # Nur vom Tool erstellte OUs; bei Fremdobjekten wird explizit nachgefragt
                $status = Remove-ToolCreatedOU -DistinguishedName $ou
                switch ($status) {
                    'Deleted' {
                        Write-AppLog "OU '$ou' und alle enthaltenen Objekte gelöscht" -Level "SUCCESS"
                        $deletedCount++
                        [void]$script:CreatedOUs.Remove($ou)
                    }
                    'NotFound' { [void]$script:CreatedOUs.Remove($ou) }
                    default { $skippedCount++ }
                }
            } catch {
                Write-AppLog "Fehler beim Löschen der OU '$ou': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }

        # Übersprungene/fehlgeschlagene OUs bleiben in der Liste

        Hide-Progress
        Show-CreatedObjectCount

        $message = "OU-Löschung abgeschlossen:`n`nGelöscht: $deletedCount`nÜbersprungen: $skippedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei OU-Löschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der OU-Löschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Remove-CreatedServiceAccount {
    <#
    .SYNOPSIS
    Löscht alle erstellten Dienstkonten
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Löschung aller erstellten Dienstkonten..." -Level "INFO"

        if (-not $script:CreatedServiceAccounts -or $script:CreatedServiceAccounts.Count -eq 0) {
            Write-AppLog "Keine Dienstkonten zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Dienstkonten erstellt.", "Hinweis", "OK", "Information")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($script:CreatedServiceAccounts.Count) erstellten Dienstkonten löschen?`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "Dienstkonten löschen", "YesNo", "Warning")

        if ($result -ne "Yes") {
            Write-AppLog "Dienstkonto-Löschung abgebrochen" -Level "INFO"
            return
        }
        if (-not $PSCmdlet.ShouldProcess("$($script:CreatedServiceAccounts.Count) erstellte Dienstkonten", "Löschen")) { return }

        Show-Progress -Text "Lösche Dienstkonten..."

        $deletedCount = 0
        $errorCount = 0
        $total = $script:CreatedServiceAccounts.Count

        $accountsToDelete = @($script:CreatedServiceAccounts)
        for ($i = 0; $i -lt $accountsToDelete.Count; $i++) {
            $accountName = $accountsToDelete[$i]
            Write-GuiProgress -Current ($i + 1) -Total $total -Text "Lösche Dienstkonto: $accountName"

            try {
                Remove-ADUser -Identity $accountName -Confirm:$false -ErrorAction Stop
                Write-AppLog "Dienstkonto '$accountName' gelöscht" -Level "SUCCESS"
                $deletedCount++
                [void]$script:CreatedServiceAccounts.Remove($accountName)
            } catch {
                if (Test-ADIdentityNotFound -ErrorRecord $_) {
                    Write-AppLog "Dienstkonto '$accountName' existiert nicht mehr" -Level "INFO"
                    [void]$script:CreatedServiceAccounts.Remove($accountName)
                } else {
                    Write-AppLog "Fehler beim Löschen des Dienstkontos '$accountName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }

        # Nicht gelöschte Dienstkonten bleiben in der Liste

        Hide-Progress
        Show-CreatedObjectCount

        $message = "Dienstkonto-Löschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Dienstkonto-Löschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Dienstkonto-Löschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Clear-CreatedTestData {
    try {
        Write-AppLog "Starte Bereinigung..." -Level "INFO"

        $result = [System.Windows.MessageBox]::Show(
            "WARNUNG: Dies löscht alle von diesem Tool erstellten Gruppen, Computer, Dienstkonten, Drucker und Test-OUs!`n`n" +
            "(Benutzer werden NICHT einzeln gelöscht - vom Tool erstellte Benutzer innerhalb gelöschter Test-OUs werden jedoch mit entfernt.`n" +
            "Enthält eine OU fremde Objekte, wird vorher separat nachgefragt.)`n`nMöchten Sie fortfahren?",
            "Bereinigung",
            "YesNo",
            "Warning"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Bereinige Testdaten..."

        $totalItems = $script:CreatedGroups.Count + $script:CreatedComputers.Count +
                     $script:CreatedOUs.Count + $script:CreatedServiceAccounts.Count + $script:CreatedPrinters.Count
        $currentItem = 0
        $successCount = 0
        $errorCount = 0

        # Gruppen löschen (alle aus $script:CreatedGroups)
        if ($script:CreatedGroups -and $script:CreatedGroups.Count -gt 0) {
            Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Gruppen..."

            # Kopie erstellen, da wir während der Iteration löschen
            $groupsToDelete = @($script:CreatedGroups)

            foreach ($group in $groupsToDelete) {
                $currentItem++
                try {
                    # Prüfe ob Gruppe existiert
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $group)'" -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        Remove-ADGroup -Identity $existingGroup.DistinguishedName -Confirm:$false -ErrorAction Stop
                        Write-AppLog "Gruppe '$group' gelöscht" -Level "SUCCESS"
                        $successCount++
                    } else {
                        Write-AppLog "Gruppe '$group' existiert nicht mehr" -Level "DEBUG"
                    }
                    [void]$script:CreatedGroups.Remove($group)
                }
                catch {
                    Write-AppLog "Fehler beim Löschen von Gruppe '$group': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Gruppe: $group"
            }
        }

        # Computer löschen
        if ($script:CreatedComputers -and $script:CreatedComputers.Count -gt 0) {
            Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Computer..."

            $computersToDelete = @($script:CreatedComputers)
            foreach ($computer in $computersToDelete) {
                $currentItem++
                try {
                    $existingComputer = Get-ADComputer -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $computer)'" -ErrorAction SilentlyContinue
                    if ($existingComputer) {
                        # Recursive: entfernt auch vom Tool angelegte BitLocker-Recovery-Unterobjekte
                        Remove-ADObject -Identity $existingComputer.DistinguishedName -Recursive -Confirm:$false -ErrorAction Stop
                        Write-AppLog "Computer '$computer' gelöscht" -Level "SUCCESS"
                        $successCount++
                    }
                    [void]$script:CreatedComputers.Remove($computer)
                }
                catch {
                    Write-AppLog "Fehler beim Löschen von Computer '$computer': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Computer: $computer"
            }
        }

        # Dienstkonten löschen
        if ($script:CreatedServiceAccounts -and $script:CreatedServiceAccounts.Count -gt 0) {
            Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Dienstkonten..."

            $serviceAccountsToDelete = @($script:CreatedServiceAccounts)
            foreach ($serviceAccount in $serviceAccountsToDelete) {
                $currentItem++
                try {
                    $existingAccount = Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-ADFilterValue -Value $serviceAccount)'" -ErrorAction SilentlyContinue
                    if ($existingAccount) {
                        Remove-ADUser -Identity $existingAccount.DistinguishedName -Confirm:$false -ErrorAction Stop
                        Write-AppLog "Dienstkonto '$serviceAccount' gelöscht" -Level "SUCCESS"
                        $successCount++
                    }
                    [void]$script:CreatedServiceAccounts.Remove($serviceAccount)
                }
                catch {
                    Write-AppLog "Fehler beim Löschen von Dienstkonto '$serviceAccount': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Dienstkonto: $serviceAccount"
            }
        }

        # Drucker löschen
        foreach ($printerDn in @($script:CreatedPrinters)) {
            $currentItem++
            try {
                Remove-ADObject -Identity $printerDn -Confirm:$false -ErrorAction Stop
                Write-AppLog "Drucker '$printerDn' gelöscht" -Level "SUCCESS"
                $successCount++
                [void]$script:CreatedPrinters.Remove($printerDn)
            }
            catch {
                if (Test-ADIdentityNotFound -ErrorRecord $_) {
                    [void]$script:CreatedPrinters.Remove($printerDn)
                } else {
                    Write-AppLog "Fehler beim Löschen von Drucker '$printerDn': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
            Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche Drucker"
        }

        # OUs löschen (in umgekehrter Reihenfolge für Hierarchien)
        if ($script:CreatedOUs -and $script:CreatedOUs.Count -gt 0) {
            Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche OUs..."

            # Sortiere OUs nach Tiefe (tiefste zuerst)
            $ousToDelete = @(@($script:CreatedOUs) | Sort-Object { ($_ -split ',').Count } -Descending)

            foreach ($ou in $ousToDelete) {
                $currentItem++
                try {
                    # Prüfe ob es eine Test-OU ist (USERS, GROUPS, etc.)
                    $ouName = ($ou -split ',')[0] -replace 'OU=', ''
                    $isTestOU = $ouName -in @('USERS', 'GROUPS', 'COMPUTERS', 'SERVICES', 'RESOURCES', 'USER', 'COMPUTER', 'SERVICE', 'RESOURCE')

                    if (-not $isTestOU) {
                        # Bleibt in der Liste und kann über "OUs löschen" entfernt werden
                        Write-AppLog "OU '$ou' ist keine Test-OU, überspringe..." -Level "DEBUG"
                        continue
                    }

                    # Nur vom Tool erstellte OUs; bei Fremdobjekten wird explizit nachgefragt
                    $status = Remove-ToolCreatedOU -DistinguishedName $ou
                    if ($status -eq 'Deleted') {
                        Write-AppLog "OU '$ou' gelöscht" -Level "SUCCESS"
                        $successCount++
                    }
                    if ($status -ne 'Skipped') {
                        [void]$script:CreatedOUs.Remove($ou)
                    }
                }
                catch {
                    Write-AppLog "Fehler beim Löschen von OU '$ou': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Write-GuiProgress -Current $currentItem -Total $totalItems -Text "Lösche OU: $($ou -split ',' | Select-Object -First 1)"
            }
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = @"
Bereinigung abgeschlossen:

Erfolgreich gelöscht: $successCount
Fehler: $errorCount

Hinweis: Benutzer wurden nicht einzeln gelöscht.
Diese können Sie über '🗑️ Löschen' im Bereich 'Erstellte Benutzer verwalten' entfernen.
OUs aus der OU-Struktur entfernen Sie über '🗑️ OUs'.
"@

        [System.Windows.MessageBox]::Show($message, "Bereinigung abgeschlossen", "OK", "Information")

    }
    catch {
        Write-AppLog "Fehler bei Bereinigung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

#region Gruppen & Organisationsstruktur - Erweiterte Funktionen

function New-AutomaticGroup {
    <#
    .SYNOPSIS
    Erstellt automatisch Gruppen basierend auf Abteilungen, Standorten und Berufsbezeichnungen
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte automatische Gruppenerstellung..." -Level "INFO"

        $createDepartmentGroups = $script:GuiControls.CheckBoxCreateDepartmentGroups.IsChecked
        $createLocationGroups = $script:GuiControls.CheckBoxCreateLocationGroups.IsChecked
        $createJobTitleGroups = $script:GuiControls.CheckBoxCreateJobTitleGroups.IsChecked

        if (-not ($createDepartmentGroups -or $createLocationGroups -or $createJobTitleGroups)) {
            Write-AppLog "Keine Gruppentypen für automatische Erstellung ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens einen Gruppentyp aus.", "Hinweis", "OK", "Warning")
            return
        }

        if (-not $script:CreatedUsers -or $script:CreatedUsers.Count -eq 0) {
            Write-AppLog "Keine Benutzer vorhanden, aus denen Gruppen erstellt werden können" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt. Gruppen werden basierend auf Benutzerattributen erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        # Bestimme Gruppen-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "Automatische Gruppen erstellen")) { return }

        # Erstelle dedizierte Test-OUs wenn nötig
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }

        Show-Progress -Text "Analysiere Benutzerattribute..."

        # Sammle Benutzer je Attributwert (einmalige AD-Abfrage pro Benutzer, keine erneuten Suchen pro Gruppe)
        $comparer = [System.StringComparer]::OrdinalIgnoreCase
        $usersByDepartment = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ($comparer)
        $usersByLocation = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ($comparer)
        $usersByJobTitle = New-Object 'System.Collections.Generic.Dictionary[string,System.Collections.Generic.List[string]]' ($comparer)

        $addToIndex = {
            param($Index, [string]$Key, [string]$Sam)
            if ([string]::IsNullOrWhiteSpace($Key)) { return }
            if (-not $Index.ContainsKey($Key)) { $Index[$Key] = New-Object System.Collections.Generic.List[string] }
            $Index[$Key].Add($Sam)
        }

        $userIndex = 0
        $userTotal = $script:CreatedUsers.Count
        foreach ($userName in @($script:CreatedUsers)) {
            $userIndex++
            try {
                $user = Get-ADUser -Identity $userName -Properties Department, City, Title -ErrorAction Stop

                if ($createDepartmentGroups) { & $addToIndex $usersByDepartment $user.Department $user.SamAccountName }
                if ($createLocationGroups) { & $addToIndex $usersByLocation $user.City $user.SamAccountName }
                if ($createJobTitleGroups) { & $addToIndex $usersByJobTitle $user.Title $user.SamAccountName }
            } catch {
                Write-AppLog "Fehler beim Abrufen der Attribute für Benutzer '$userName': $($_.Exception.Message)" -Level "WARN"
            }
            if ($userIndex % 25 -eq 0) {
                Write-GuiProgress -Current $userIndex -Total $userTotal -Text "Analysiere Benutzerattribute"
            }
        }

        # Einzigartige Werte extrahieren
        $uniqueDepartments = @($usersByDepartment.Keys)
        $uniqueLocations = @($usersByLocation.Keys)
        $uniqueJobTitles = @($usersByJobTitle.Keys)

        # Gruppennamen von unzulässigen Zeichen bereinigen
        $toGroupName = { param([string]$Prefix, [string]$Value) "$Prefix$($Value -replace '[^\w\-\.]', '_')" }

        $totalGroups = $uniqueDepartments.Count + $uniqueLocations.Count + $uniqueJobTitles.Count
        $currentGroup = 0
        $successCount = 0
        $errorCount = 0

        # Erstelle Abteilungsgruppen
        if ($createDepartmentGroups) {
            foreach ($dept in $uniqueDepartments) {
                $currentGroup++
                Write-GuiProgress -Current $currentGroup -Total $totalGroups -Text "Erstelle Abteilungsgruppe: $dept"

                $groupName = & $toGroupName "DEPT_" $dept
                $groupDescription = "Abteilung: $dept"

                try {
                    # Prüfe ob Gruppe bereits existiert
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $groupName)'" -ErrorAction SilentlyContinue
                    if (-not $existingGroup) {
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Description $groupDescription `
                            -Path $groupOU `
                            -ErrorAction Stop

                        $script:CreatedGroups.Add($groupName)
                        Write-AppLog "Abteilungsgruppe '$groupName' erfolgreich erstellt" -Level "SUCCESS"

                        # Füge Benutzer der Gruppe hinzu
                        $usersInDept = $usersByDepartment[$dept]
                        if ($usersInDept.Count -gt 0) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $usersInDept.ToArray() -ErrorAction Stop
                                Write-AppLog "$($usersInDept.Count) Benutzer zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-AppLog "Fehler beim Hinzufügen von Benutzern zu '$groupName': $($_.Exception.Message)" -Level "WARN"
                            }
                        }

                        $successCount++
                    } else {
                        Write-AppLog "Gruppe '$groupName' existiert bereits, übersprungen" -Level "INFO"
                    }
                } catch {
                    Write-AppLog "Fehler beim Erstellen der Abteilungsgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }

        # Erstelle Standortgruppen
        if ($createLocationGroups) {
            foreach ($location in $uniqueLocations) {
                $currentGroup++
                Write-GuiProgress -Current $currentGroup -Total $totalGroups -Text "Erstelle Standortgruppe: $location"

                $groupName = & $toGroupName "LOC_" $location
                $groupDescription = "Standort: $location"

                try {
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $groupName)'" -ErrorAction SilentlyContinue
                    if (-not $existingGroup) {
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Description $groupDescription `
                            -Path $groupOU `
                            -ErrorAction Stop

                        $script:CreatedGroups.Add($groupName)
                        Write-AppLog "Standortgruppe '$groupName' erfolgreich erstellt" -Level "SUCCESS"

                        # Füge Benutzer der Gruppe hinzu
                        $usersInLocation = $usersByLocation[$location]
                        if ($usersInLocation.Count -gt 0) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $usersInLocation.ToArray() -ErrorAction Stop
                                Write-AppLog "$($usersInLocation.Count) Benutzer zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-AppLog "Fehler beim Hinzufügen von Benutzern zu '$groupName': $($_.Exception.Message)" -Level "WARN"
                            }
                        }

                        $successCount++
                    } else {
                        Write-AppLog "Gruppe '$groupName' existiert bereits, übersprungen" -Level "INFO"
                    }
                } catch {
                    Write-AppLog "Fehler beim Erstellen der Standortgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }

        # Erstelle Berufsbezeichnungsgruppen
        if ($createJobTitleGroups) {
            foreach ($title in $uniqueJobTitles) {
                $currentGroup++
                Write-GuiProgress -Current $currentGroup -Total $totalGroups -Text "Erstelle Berufsgruppe: $title"

                $groupName = & $toGroupName "JOB_" $title
                $groupDescription = "Berufsbezeichnung: $title"

                try {
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$(ConvertTo-ADFilterValue -Value $groupName)'" -ErrorAction SilentlyContinue
                    if (-not $existingGroup) {
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Description $groupDescription `
                            -Path $groupOU `
                            -ErrorAction Stop

                        $script:CreatedGroups.Add($groupName)
                        Write-AppLog "Berufsgruppe '$groupName' erfolgreich erstellt" -Level "SUCCESS"

                        # Füge Benutzer der Gruppe hinzu
                        $usersWithTitle = $usersByJobTitle[$title]
                        if ($usersWithTitle.Count -gt 0) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $usersWithTitle.ToArray() -ErrorAction Stop
                                Write-AppLog "$($usersWithTitle.Count) Benutzer zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-AppLog "Fehler beim Hinzufügen von Benutzern zu '$groupName': $($_.Exception.Message)" -Level "WARN"
                            }
                        }

                        $successCount++
                    } else {
                        Write-AppLog "Gruppe '$groupName' existiert bereits, übersprungen" -Level "INFO"
                    }
                } catch {
                    Write-AppLog "Fehler beim Erstellen der Berufsgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = "Automatische Gruppenerstellung abgeschlossen.`n`nErstellt: $successCount`nFehler: $errorCount`n`nDetails:`n"
        if ($createDepartmentGroups) { $message += "- $($uniqueDepartments.Count) Abteilungsgruppen`n" }
        if ($createLocationGroups) { $message += "- $($uniqueLocations.Count) Standortgruppen`n" }
        if ($createJobTitleGroups) { $message += "- $($uniqueJobTitles.Count) Berufsgruppen`n" }

        [System.Windows.MessageBox]::Show($message, "Gruppen erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei automatischer Gruppenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Gruppenerstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-GroupHierarchyLevel {
    <#
    .SYNOPSIS
    Erstellt rekursiv eine Ebene einer verschachtelten Gruppenhierarchie (Hashtable = weitere Ebene, Array = Blattgruppen)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Structure,
        [Parameter(Mandatory = $true)][string]$TargetOU,
        [Parameter(Mandatory = $true)][string]$GroupCategory,
        [Parameter(Mandatory = $true)][hashtable]$State,
        [string]$ParentGroup,
        [int]$Level = 1
    )

    foreach ($key in $Structure.Keys) {
        # Universal kann Universal/Global enthalten, Global nur Global (gleiche Domäne)
        $groupScope = if ($Level -le 2) { "Universal" } else { "Global" }
        try {
            if (-not $PSCmdlet.ShouldProcess($key, "Gruppe erstellen")) { continue }
            New-ADGroup -Name $key -GroupScope $groupScope -GroupCategory $GroupCategory `
                -Description "Hierarchie-Ebene $Level" -Path $TargetOU -ErrorAction Stop
            $script:CreatedGroups.Add($key)
            $State.SuccessCount++

            if ($ParentGroup) {
                Add-ADGroupMember -Identity $ParentGroup -Members $key -ErrorAction Stop
                Write-AppLog "Gruppe '$key' erstellt und zu '$ParentGroup' hinzugefügt (Ebene $Level)" -Level "SUCCESS"
            } else {
                Write-AppLog "Stammgruppe '$key' erstellt (Ebene $Level)" -Level "SUCCESS"
            }
        } catch {
            Write-AppLog "Fehler bei Gruppe '$key': $($_.Exception.Message)" -Level "ERROR"
            $State.ErrorCount++
            continue
        }

        $children = $Structure[$key]
        if ($children -is [hashtable]) {
            New-GroupHierarchyLevel -Structure $children -TargetOU $TargetOU -GroupCategory $GroupCategory -State $State -ParentGroup $key -Level ($Level + 1)
        } else {
            foreach ($leafGroup in @($children)) {
                try {
                    if (-not $PSCmdlet.ShouldProcess($leafGroup, "Gruppe erstellen")) { continue }
                    New-ADGroup -Name $leafGroup -GroupScope Global -GroupCategory $GroupCategory `
                        -Description "Hierarchie-Ebene $($Level + 1)" -Path $TargetOU -ErrorAction Stop
                    $script:CreatedGroups.Add($leafGroup)
                    Add-ADGroupMember -Identity $key -Members $leafGroup -ErrorAction Stop
                    $State.SuccessCount++
                    Write-AppLog "Gruppe '$leafGroup' erstellt und zu '$key' hinzugefügt (Ebene $($Level + 1))" -Level "SUCCESS"
                } catch {
                    Write-AppLog "Fehler bei Gruppe '$leafGroup': $($_.Exception.Message)" -Level "ERROR"
                    $State.ErrorCount++
                }
            }
        }
    }
}

function New-NestedGroupStructure {
    <#
    .SYNOPSIS
    Erstellt verschachtelte Gruppenhierarchien basierend auf der ausgewählten Struktur
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    try {
        Write-AppLog "Starte Erstellung verschachtelter Gruppenstruktur..." -Level "INFO"

        $selectedHierarchy = $script:GuiControls.ComboBoxGroupHierarchy.SelectedItem
        if (-not $selectedHierarchy) {
            Write-AppLog "Keine Hierarchie ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Hierarchie-Struktur aus.", "Hinweis", "OK", "Warning")
            return
        }

        $hierarchyType = $selectedHierarchy.Content
        $groupCategory = if ([bool]$script:GuiControls.CheckBoxNestedSecurity.IsChecked) { "Security" } else { "Distribution" }

        # Bestimme Gruppen-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        # Erstelle dedizierte Test-OUs wenn nötig
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }

        if (-not $PSCmdlet.ShouldProcess($groupOU, "Gruppenstruktur '$hierarchyType' erstellen")) { return }

        Show-Progress -Text "Erstelle verschachtelte Gruppenstruktur..."

        $successCount = 0
        $errorCount = 0

        switch ($hierarchyType) {
            "Flache Struktur" {
                # Keine Verschachtelung, nur einfache Gruppen
                $groups = @("Users", "Managers", "Admins")
                foreach ($group in $groups) {
                    try {
                        $groupName = "FLAT_$group"
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory $groupCategory `
                            -Description "Flache Struktur - $group" `
                            -Path $groupOU `
                            -ErrorAction Stop

                        $script:CreatedGroups.Add($groupName)
                        $successCount++
                        Write-AppLog "Gruppe '$groupName' erstellt" -Level "SUCCESS"
                    } catch {
                        Write-AppLog "Fehler beim Erstellen der Gruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                        $errorCount++
                    }
                }
            }

            "2-stufige Hierarchie" {
                # Parent -> Child Struktur
                $structure = @{
                    "ALL_USERS" = @("USERS_Standard", "USERS_Power", "USERS_Guest")
                    "ALL_ADMINS" = @("ADMINS_Local", "ADMINS_Domain", "ADMINS_Enterprise")
                }

                foreach ($parent in $structure.Keys) {
                    try {
                        # Erstelle Parent-Gruppe
                        New-ADGroup -Name $parent `
                            -GroupScope Global `
                            -GroupCategory $groupCategory `
                            -Description "Übergeordnete Gruppe" `
                            -Path $groupOU `
                            -ErrorAction Stop

                        $script:CreatedGroups.Add($parent)
                                                $successCount++
                        Write-AppLog "Parent-Gruppe '$parent' erstellt" -Level "SUCCESS"

                        # Erstelle Child-Gruppen
                        foreach ($child in $structure[$parent]) {
                            try {
                                New-ADGroup -Name $child `
                                    -GroupScope Global `
                                    -GroupCategory $groupCategory `
                                    -Description "Untergruppe von $parent" `
                                    -Path $groupOU `
                                    -ErrorAction Stop

                                $script:CreatedGroups.Add($child)

                                # Füge Child zu Parent hinzu
                                Add-ADGroupMember -Identity $parent -Members $child -ErrorAction Stop

                                $successCount++
                                Write-AppLog "Child-Gruppe '$child' erstellt und zu '$parent' hinzugefügt" -Level "SUCCESS"
                            } catch {
                                Write-AppLog "Fehler bei Child-Gruppe '$child': $($_.Exception.Message)" -Level "ERROR"
                                $errorCount++
                            }
                        }
                    } catch {
                        Write-AppLog "Fehler bei Parent-Gruppe '$parent': $($_.Exception.Message)" -Level "ERROR"
                        $errorCount++
                    }
                }
            }

            "3-stufige Hierarchie" {
                # Organisation -> Department -> Team Struktur
                $structure = @{
                    "ORG_Company" = @{
                        "DEPT_IT" = @("TEAM_Development", "TEAM_Infrastructure", "TEAM_Support")
                        "DEPT_HR" = @("TEAM_Recruiting", "TEAM_Payroll", "TEAM_Training")
                        "DEPT_Finance" = @("TEAM_Accounting", "TEAM_Controlling", "TEAM_Treasury")
                    }
                }

                foreach ($org in $structure.Keys) {
                    try {
                        # Level 1: Organisation
                        New-ADGroup -Name $org `
                            -GroupScope Universal `
                            -GroupCategory $groupCategory `
                            -Description "Organisationsebene" `
                            -Path $groupOU `
                            -ErrorAction Stop

                        $script:CreatedGroups.Add($org)
                                                $successCount++
                        Write-AppLog "Organisation '$org' erstellt" -Level "SUCCESS"

                        foreach ($dept in $structure[$org].Keys) {
                            try {
                                # Level 2: Department
                                New-ADGroup -Name $dept `
                                    -GroupScope Global `
                                    -GroupCategory $groupCategory `
                                    -Description "Abteilungsebene" `
                                    -Path $groupOU `
                                    -ErrorAction Stop

                                $script:CreatedGroups.Add($dept)
                                                                Add-ADGroupMember -Identity $org -Members $dept -ErrorAction Stop
                                $successCount++
                                Write-AppLog "Department '$dept' erstellt und zu '$org' hinzugefügt" -Level "SUCCESS"

                                foreach ($team in $structure[$org][$dept]) {
                                    try {
                                        # Level 3: Team
                                        # Global: eine DomainLocal-Gruppe kann nicht Mitglied einer Global-Gruppe sein
                                        New-ADGroup -Name $team `
                                            -GroupScope Global `
                                            -GroupCategory $groupCategory `
                                            -Description "Teamebene" `
                                            -Path $groupOU `
                                            -ErrorAction Stop

                                        $script:CreatedGroups.Add($team)
                                                                                Add-ADGroupMember -Identity $dept -Members $team -ErrorAction Stop
                                        $successCount++
                                        Write-AppLog "Team '$team' erstellt und zu '$dept' hinzugefügt" -Level "SUCCESS"
                                    } catch {
                                        Write-AppLog "Fehler bei Team '$team': $($_.Exception.Message)" -Level "ERROR"
                                        $errorCount++
                                    }
                                }
                            } catch {
                                Write-AppLog "Fehler bei Department '$dept': $($_.Exception.Message)" -Level "ERROR"
                                $errorCount++
                            }
                        }
                    } catch {
                        Write-AppLog "Fehler bei Organisation '$org': $($_.Exception.Message)" -Level "ERROR"
                        $errorCount++
                    }
                }
            }

            "Vollständige Hierarchie" {
                # Fünfstufige Hierarchie: Region -> Land -> Stadt -> Abteilung -> Team (Präfix FULL_ vermeidet Namenskonflikte)
                $structure = @{
                    "FULL_REGION_EMEA" = @{
                        "FULL_COUNTRY_Germany" = @{
                            "FULL_CITY_Berlin" = @{
                                "FULL_DEPT_Sales" = @("FULL_TEAM_Inside", "FULL_TEAM_Field")
                                "FULL_DEPT_Tech" = @("FULL_TEAM_Dev", "FULL_TEAM_QA")
                            }
                            "FULL_CITY_Munich" = @{
                                "FULL_DEPT_RnD" = @("FULL_TEAM_Research", "FULL_TEAM_Innovation")
                            }
                        }
                        "FULL_COUNTRY_UK" = @{
                            "FULL_CITY_London" = @{
                                "FULL_DEPT_Finance" = @("FULL_TEAM_Audit", "FULL_TEAM_Tax")
                            }
                        }
                    }
                }

                $hierarchyState = @{ SuccessCount = 0; ErrorCount = 0 }
                New-GroupHierarchyLevel -Structure $structure -TargetOU $groupOU -GroupCategory $groupCategory -State $hierarchyState
                $successCount += $hierarchyState.SuccessCount
                $errorCount += $hierarchyState.ErrorCount
            }
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = "Verschachtelte Gruppenstruktur erstellt:`n`nTyp: $hierarchyType`nErstellt: $successCount Gruppen`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Struktur erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei verschachtelter Gruppenstruktur: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Measure-OUStructureNode {
    <#
    .SYNOPSIS
    Zählt die OUs einer OU-Strukturvorlage (Hashtable = OU mit Unter-OUs, Array = Blatt-OUs)
    #>
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object]$Structure)

    if ($Structure -is [hashtable]) {
        $count = 0
        foreach ($key in $Structure.Keys) { $count += 1 + (Measure-OUStructureNode -Structure $Structure[$key]) }
        return $count
    }
    return @($Structure).Count
}

function New-OUStructureLevel {
    <#
    .SYNOPSIS
    Erstellt rekursiv eine Ebene einer OU-Strukturvorlage (ohne Löschschutz, damit die Bereinigung funktioniert)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object]$Structure,
        [Parameter(Mandatory = $true)][string]$ParentPath,
        [Parameter(Mandatory = $true)][string]$StructureType,
        [Parameter(Mandatory = $true)][hashtable]$State,
        [int]$Level = 1
    )

    $ouNames = if ($Structure -is [hashtable]) { @($Structure.Keys) } else { @($Structure) }
    foreach ($ouName in $ouNames) {
        $ouPath = "OU=$ouName,$ParentPath"
        $State.Processed++
        Write-GuiProgress -Current $State.Processed -Total $State.Total -Text "Erstelle OU-Struktur"
        try {
            $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$(ConvertTo-ADFilterValue -Value $ouPath)'" -ErrorAction SilentlyContinue
            if ($existingOU) {
                Write-AppLog "OU '$ouPath' existiert bereits und wird nicht erneut angelegt" -Level "INFO"
                $State.ExistingCount++
            } elseif ($PSCmdlet.ShouldProcess($ouPath, "OU erstellen")) {
                New-ADOrganizationalUnit -Name $ouName -Path $ParentPath -Description "Ebene $Level - $StructureType" `
                    -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
                $script:CreatedOUs.Add($ouPath)
                $State.Created.Add($ouPath)
                Write-AppLog "OU '$ouName' unter '$ParentPath' erstellt" -Level "SUCCESS"
            } else {
                continue
            }
        } catch {
            Write-AppLog "Fehler bei OU '$ouPath': $($_.Exception.Message)" -Level "ERROR"
            $State.ErrorCount++
            continue
        }

        if ($Structure -is [hashtable] -and @($Structure[$ouName]).Count -gt 0) {
            New-OUStructureLevel -Structure $Structure[$ouName] -ParentPath $ouPath -StructureType $StructureType -State $State -Level ($Level + 1)
        }
    }
}

function New-OUStructure {
    <#
    .SYNOPSIS
    Erstellt eine OU-Struktur nach Firmengröße unterhalb der Ziel-OU
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte OU-Struktur-Erstellung..." -Level "INFO"

    $selectedStructure = $script:GuiControls.ComboBoxOUStructure.SelectedItem
    if (-not $selectedStructure) {
        Write-AppLog "Keine OU-Struktur ausgewählt" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Firmenstruktur aus.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }
    $structureType = [string]$selectedStructure.Content

    $targetOU = ([string]$script:GuiControls.ComboBoxTargetOU.Text).Trim()
    if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
        Write-AppLog "Keine gültige Ziel-OU ausgewählt" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie eine gültige Ziel-OU aus (z. B. über 'Test-Umgebung erstellen').", "Hinweis", "OK", "Warning") | Out-Null
        return
    }
    if (-not (Test-TargetOU -TargetOU $targetOU)) { return }

    # Firmenname als Wurzel-OU (Zeichen mit Sonderbedeutung im DN werden entfernt)
    $companyOU = (([string]$script:GuiControls.TextBoxCompanyName.Text) -replace '[,+"\\<>;=#/]', '').Trim()
    if (-not $companyOU) { $companyOU = "TestCompany" }

    $ouStructures = @{
        "Kleine Firma (unter 50 MA)" = @{
            $companyOU = @{
                "Users" = @("Management", "Employees")
                "Computers" = @("Workstations", "Laptops")
                "Groups" = @()
                "Resources" = @()
            }
        }
        "Mittlere Firma (50-500 MA)" = @{
            $companyOU = @{
                "Departments" = @{
                    "IT" = @("Users", "Computers", "Service Accounts")
                    "HR" = @("Users", "Resources")
                    "Finance" = @("Users", "Resources")
                    "Sales" = @("Users", "Computers")
                }
                "Infrastructure" = @{
                    "Servers" = @("Application", "Database", "Web")
                    "Network" = @("Devices", "Printers")
                }
                "Security Groups" = @("Department Groups", "Resource Groups", "Role Groups")
            }
        }
        "Große Firma (500+ MA)" = @{
            $companyOU = @{
                "Business Units" = @{
                    "Corporate" = @{
                        "Executive" = @("Users", "Computers")
                        "IT" = @{
                            "Development" = @("Users", "Computers", "Test Accounts")
                            "Operations" = @("Users", "Computers", "Service Accounts")
                            "Security" = @("Users", "Computers", "Privileged Accounts")
                        }
                        "Finance" = @("Users", "Computers", "Resources")
                    }
                    "Production" = @{
                        "Manufacturing" = @("Users", "Computers", "Service Accounts")
                        "Quality" = @("Users", "Computers")
                        "Logistics" = @("Users", "Computers")
                    }
                    "Sales & Marketing" = @{
                        "Sales" = @("Inside Sales", "Field Sales", "Partners")
                        "Marketing" = @("Digital", "Events", "Content")
                    }
                }
                "Infrastructure" = @{
                    "Tier 0" = @("Domain Controllers", "PKI", "ADFS")
                    "Tier 1" = @("Servers", "Management", "Backup")
                    "Tier 2" = @("Workstations", "Kiosks", "Mobile")
                }
                "Security" = @{
                    "Groups" = @("Global", "Domain Local", "Universal")
                    "Service Accounts" = @("Tier 0", "Tier 1", "Tier 2")
                    "Privileged" = @("Admin Accounts", "Service Accounts")
                }
            }
        }
        "Konzern (Multi-Standort)" = @{
            $companyOU = @{
                "Global" = @{
                    "EMEA" = @{
                        "Germany" = @{
                            "Berlin" = @("Users", "Computers", "Groups", "Resources")
                            "Munich" = @("Users", "Computers", "Groups", "Resources")
                            "Hamburg" = @("Users", "Computers", "Groups", "Resources")
                        }
                        "UK" = @{
                            "London" = @("Users", "Computers", "Groups", "Resources")
                            "Manchester" = @("Users", "Computers", "Groups", "Resources")
                        }
                        "France" = @{
                            "Paris" = @("Users", "Computers", "Groups", "Resources")
                        }
                    }
                    "Americas" = @{
                        "USA" = @{
                            "New York" = @("Users", "Computers", "Groups", "Resources")
                            "San Francisco" = @("Users", "Computers", "Groups", "Resources")
                        }
                        "Canada" = @{
                            "Toronto" = @("Users", "Computers", "Groups", "Resources")
                        }
                    }
                    "APAC" = @{
                        "Japan" = @{
                            "Tokyo" = @("Users", "Computers", "Groups", "Resources")
                        }
                        "Australia" = @{
                            "Sydney" = @("Users", "Computers", "Groups", "Resources")
                        }
                    }
                }
                "Global Infrastructure" = @{
                    "Core Services" = @("Domain Controllers", "DNS", "DHCP", "PKI")
                    "Identity Management" = @("ADFS", "Azure AD Connect", "MFA")
                    "Security" = @("Privileged Access", "Service Accounts", "Break Glass")
                }
            }
        }
    }

    $structure = $ouStructures[$structureType]
    if (-not $structure) {
        Write-AppLog "Unbekannte OU-Strukturvorlage: '$structureType'" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Unbekannte Strukturvorlage: $structureType", "Fehler", "OK", "Error") | Out-Null
        return
    }

    $state = @{
        Created = New-Object System.Collections.Generic.List[string]
        ExistingCount = 0
        ErrorCount = 0
        Processed = 0
        Total = (Measure-OUStructureNode -Structure $structure)
    }

    $result = [System.Windows.MessageBox]::Show(
        "Soll die OU-Struktur '$structureType' ($($state.Total) OUs) unterhalb von`n$targetOU`nerstellt werden?`n`nWurzel-OU: $companyOU",
        "OU-Struktur erstellen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess($targetOU, "OU-Struktur '$structureType' erstellen")) { return }

    Show-Progress -Text "Erstelle OU-Struktur..."
    New-OUStructureLevel -Structure $structure -ParentPath $targetOU -StructureType $structureType -State $state
    Hide-Progress
    Show-CreatedObjectCount

    $docPath = Get-ExportFilePath -FileName "OU_Structure_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $documentation = @"
OU-Struktur Dokumentation
=========================
Erstellt am: $(Get-Date)
Strukturvorlage: $structureType
Basis-OU: $targetOU

Erstellte OUs ($($state.Created.Count)):
$($state.Created | ForEach-Object { "- $_" } | Out-String)
Bereits vorhanden: $($state.ExistingCount)
Fehler: $($state.ErrorCount)
"@
    $documentation | Out-File -FilePath $docPath -Encoding UTF8

    Write-AppLog "OU-Struktur '$structureType': $($state.Created.Count) erstellt, $($state.ExistingCount) vorhanden, $($state.ErrorCount) Fehler" -Level "INFO"
    [System.Windows.MessageBox]::Show(
        "OU-Struktur erstellt.`n`nVorlage: $structureType`nErstellt: $($state.Created.Count)`nBereits vorhanden: $($state.ExistingCount)`nFehler: $($state.ErrorCount)`n`nDokumentation:`n$docPath",
        "OU-Struktur erstellt", "OK", "Information") | Out-Null
}

function New-TestComputer {
    <#
    .SYNOPSIS
    Erstellt Computer-Objekte in Active Directory
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Computer-Erstellung..." -Level "INFO"

        $computerCount = $script:GuiControls.TextBoxComputerCount.Text
        $computerType = $script:GuiControls.ComboBoxComputerType.SelectedItem
        $randomNames = $script:GuiControls.CheckBoxRandomComputerNames.IsChecked

        if ([string]::IsNullOrWhiteSpace($computerCount)) {
            $computerCount = 10 # Default
        } else {
            $computerCount = ConvertTo-IntOrZero -Value $computerCount
        }

        if ($computerCount -le 0) {
            Write-AppLog "Ungültige Anzahl Computer" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Computern an.", "Hinweis", "OK", "Warning")
            return
        }

        if (-not $computerType) {
            Write-AppLog "Kein Computer-Typ ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Computer-Typ aus.", "Hinweis", "OK", "Warning")
            return
        }

        $type = $computerType.Content

        # Bestimme Ziel-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $computerCount Computer vom Typ '$type' erstellen?`n`n" +
            "Ziel: Test-OU 'COMPUTERS' unterhalb von $targetOU`n" +
            "Zufällige Namen: $(if ($randomNames) { 'Ja' } else { 'Nein' })",
            "Computer erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "$computerCount Computer erstellen")) { return }
        # Erstelle Test-OUs wenn nötig
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        $computerOU = if ($testOUs["COMPUTERS"]) { $testOUs["COMPUTERS"] } else { $targetOU }

        Show-Progress -Text "Erstelle Computer..."
        $successCount = 0
        $errorCount = 0

        # Computer-Präfixe basierend auf Typ
        $prefix = switch ($type) {
            "Arbeitsplatzrechner" { "WS" }
            "Notebooks" { "LT" }
            "Server" { "SRV" }
            "Virtuelle Maschinen" { "VM" }
            default { "PC" }
        }

        # Betriebssystem basierend auf Typ
        $operatingSystem = switch ($type) {
            "Server" { "Windows Server 2022 Datacenter" }
            "Virtuelle Maschinen" { "Windows Server 2022 Standard" }
            default { "Windows 11 Enterprise" }
        }

        # Standorte für zufällige Namen
        $locations = @("BER", "MUC", "HAM", "FRA", "STG", "DUS", "CGN")
        $departments = @("IT", "HR", "FIN", "MKT", "OPS", "DEV", "SUP")

        for ($i = 1; $i -le $computerCount; $i++) {
            try {
                # Generiere Computer-Namen
                $computerName = if ($randomNames) {
                    $loc = $locations | Get-Random
                    $dept = $departments | Get-Random
                    $num = Get-Random -Minimum 1000 -Maximum 9999
                    "$prefix-$loc-$dept-$num"
                } else {
                    "$prefix-$('{0:D4}' -f $i)"
                }
                # NetBIOS-Computernamen sind auf 15 Zeichen begrenzt
                if ($computerName.Length -gt 15) {
                    $computerName = "$prefix-$loc$dept$num"
                }

                # Erstelle Computer
                $computerParams = @{
                    Name = $computerName
                    SamAccountName = "$computerName`$"
                    Path = $computerOU
                    Enabled = $true
                    OperatingSystem = $operatingSystem
                    OperatingSystemVersion = "10.0 (22621)"
                    Description = "$type - erstellt am $(Get-Date -Format 'yyyy-MM-dd')"
                    Location = if ($randomNames) { $locations | Get-Random } else { "Hauptstandort" }
                }

                # Zusätzliche Attribute für Server
                if ($type -eq "Server") {
                    $computerParams.OperatingSystemServicePack = "21H2"
                    $computerParams.DNSHostName = "$computerName.$((Get-CachedADDomain).DNSRoot)"
                }

                New-ADComputer @computerParams -ErrorAction Stop
                $script:CreatedComputers.Add($computerName)
                Write-AppLog "Computer '$computerName' erfolgreich erstellt" -Level "SUCCESS"
                $successCount++

            } catch {
                Write-AppLog "Fehler beim Erstellen von Computer: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }

            Write-GuiProgress -Current $i -Total $computerCount -Text "Erstelle Computer"
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = @"
Computer-Erstellung abgeschlossen:

Typ: $type
Erstellt: $successCount
Fehler: $errorCount
Ziel-OU: $computerOU
"@

        [System.Windows.MessageBox]::Show($message, "Computer erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Computer-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-TestServiceAccount {
    <#
    .SYNOPSIS
    Erstellt Dienstkonten (Benutzerkonten mit SPNs) in Active Directory
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Dienstkonto-Erstellung..." -Level "INFO"

        $serviceType = $script:GuiControls.ComboBoxServiceType.SelectedItem
        $accountCount = $script:GuiControls.TextBoxServiceAccountCount.Text

        if (-not $serviceType) {
            Write-AppLog "Kein Dienst-Typ ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Dienst-Typ aus.", "Hinweis", "OK", "Warning")
            return
        }

        if ([string]::IsNullOrWhiteSpace($accountCount)) {
            $accountCount = 5 # Default
        } else {
            $parsedCount = 0
            $accountCount = if ([int]::TryParse(([string]$accountCount).Trim(), [ref]$parsedCount)) { $parsedCount } else { 0 }
        }

        if ($accountCount -le 0) {
            Write-AppLog "Ungültige Anzahl Dienstkonten" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Dienstkonten an.", "Hinweis", "OK", "Warning")
            return
        }

        $type = $serviceType.Content

        # Bestimme Ziel-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $accountCount Dienstkonten für '$type' erstellen?`n`n" +
            "Ziel: Test-OU 'SERVICES' unterhalb von $targetOU",
            "Dienstkonten erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "$accountCount Dienstkonten erstellen")) { return }
        # Erstelle Test-OUs wenn nötig
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        $serviceOU = if ($testOUs["SERVICES"]) { $testOUs["SERVICES"] } else { $targetOU }

        Show-Progress -Text "Erstelle Dienstkonten..."
        $successCount = 0
        $errorCount = 0

        # Dienstkonto-Präfixe und Eigenschaften
        $serviceConfig = @{
            "SQL-Server-Dienst" = @{
                Prefix = "svc_sql"
                Description = "SQL-Server-Dienstkonto"
                SPNs = @("MSSQLSvc/")
            }
            "IIS-Anwendungspool" = @{
                Prefix = "svc_iis"
                Description = "Identität eines IIS-Anwendungspools"
                SPNs = @("HTTP/")
            }
            "Windows-Dienst" = @{
                Prefix = "svc_win"
                Description = "Windows-Dienstkonto"
                SPNs = @()
            }
            "Geplante Aufgabe" = @{
                Prefix = "svc_task"
                Description = "Dienstkonto für geplante Aufgaben"
                SPNs = @()
            }
            "Eigene Anwendung" = @{
                Prefix = "svc_app"
                Description = "Dienstkonto für eine eigene Anwendung"
                SPNs = @()
            }
        }

        $config = $serviceConfig[$type]
        $domain = (Get-CachedADDomain).DNSRoot

        for ($i = 1; $i -le $accountCount; $i++) {
            try {
                # Generiere Dienstkonto-Namen
                $accountName = "$($config.Prefix)_$(Get-Random -Minimum 1000 -Maximum 9999)"

                # Erstelle Dienstkonto
                $serviceParams = @{
                    Name = $accountName
                    SamAccountName = $accountName
                    UserPrincipalName = "$accountName@$domain"
                    Path = $serviceOU
                    Enabled = $true
                    PasswordNeverExpires = $true
                    CannotChangePassword = $true
                    Description = "$($config.Description) - erstellt am $(Get-Date -Format 'yyyy-MM-dd')"
                    DisplayName = "Dienstkonto $type $i"
                    AccountPassword = (Get-RandomSecurePassword -Complexity "Hochsicher (20+ Zeichen)")
                }

                # Füge SPNs hinzu wenn vorhanden (Hostname je Account eindeutig, um doppelte SPNs zu vermeiden)
                if ($config.SPNs.Count -gt 0) {
                    $spns = New-Object System.Collections.Generic.List[string]
                    $hostname = "$($accountName -replace '_', '-').$domain"
                    foreach ($spnPrefix in $config.SPNs) {
                        $spns.Add("$spnPrefix$hostname")
                        if ($spnPrefix -eq "HTTP/") {
                            $spns.Add("$spnPrefix${hostname}:80")
                            $spns.Add("$spnPrefix${hostname}:443")
                        } elseif ($spnPrefix -eq "MSSQLSvc/") {
                            $spns.Add("$spnPrefix${hostname}:1433")
                        }
                    }
                    $serviceParams.ServicePrincipalNames = $spns.ToArray()
                }

                New-ADUser @serviceParams -ErrorAction Stop
                $script:CreatedServiceAccounts.Add($accountName)
                Write-AppLog "Dienstkonto '$accountName' erfolgreich erstellt" -Level "SUCCESS"
                $successCount++

            } catch {
                Write-AppLog "Fehler beim Erstellen von Dienstkonto: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }

            Write-GuiProgress -Current $i -Total $accountCount -Text "Erstelle Dienstkonten"
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = @"
Dienstkonto-Erstellung abgeschlossen:

Typ: $type
Erstellt: $successCount
Fehler: $errorCount
Ziel-OU: $serviceOU

Hinweis: Alle Dienstkonten haben:
- Passwort läuft nie ab
- Benutzer kann Passwort nicht ändern
- Hochsichere Passwörter (20+ Zeichen)
"@

        [System.Windows.MessageBox]::Show($message, "Dienstkonten erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Dienstkonto-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-TestPrinter {
    <#
    .SYNOPSIS
    Erstellt veröffentlichte Drucker (printQueue-Objekte) in der Test-OU RESOURCES

    .DESCRIPTION
    Es werden nur AD-Objekte angelegt, keine echten Druckwarteschlangen. Server und IP-Adressen sind fiktiv
    (Dokumentations-Adressbereich 192.0.2.0/24). Die DistinguishedNames werden in $script:CreatedPrinters
    nachverfolgt und können über 'Drucker löschen' bzw. 'Alles löschen' entfernt werden.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Drucker-Erstellung..." -Level "INFO"

    $printerCountText = [string]$script:GuiControls.TextBoxPrinterCount.Text
    $printerCount = if ([string]::IsNullOrWhiteSpace($printerCountText)) { 5 } else { ConvertTo-IntOrZero -Value $printerCountText }
    if ($printerCount -lt 1 -or $printerCount -gt 200) {
        Write-AppLog "Ungültige Anzahl Drucker: '$printerCountText'" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie eine Anzahl zwischen 1 und 200 an.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $printerType = $script:GuiControls.ComboBoxPrinterType.SelectedItem
    if (-not $printerType) {
        Write-AppLog "Kein Drucker-Typ ausgewählt" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Drucker-Typ aus.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }
    $type = [string]$printerType.Content
    $typeCode = switch ($type) {
        "Netzwerkdrucker" { "NET" }
        "Lokale Drucker" { "LOC" }
        "Multifunktionsgeräte" { "MFP" }
        default { "PRN" }
    }

    $targetOU = ([string]$script:GuiControls.ComboBoxTargetOU.Text).Trim()
    if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
        $targetOU = (Get-CachedADDomain).DistinguishedName
    }

    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie $printerCount Drucker vom Typ '$type' erstellen?`n`n" +
        "Ziel: Test-OU 'RESOURCES' unterhalb von $targetOU`n`n" +
        "Hinweis: Es werden nur printQueue-Objekte in AD angelegt (fiktiver Druckserver).",
        "Drucker erstellen",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess($targetOU, "$printerCount Drucker-Objekte erstellen")) { return }

    Show-Progress -Text "Erstelle Drucker..."
    $testOUs = Initialize-TestOU -BaseOU $targetOU
    $resourceOU = if ($testOUs["RESOURCES"]) { $testOUs["RESOURCES"] } else { $targetOU }

    $domainDns = (Get-CachedADDomain).DNSRoot
    $printServer = "TEST-PRN01"
    $printServerFqdn = "$printServer.$domainDns"

    $manufacturers = @{
        "HP" = @("LaserJet Pro M404dn", "Color LaserJet Pro M454dw", "OfficeJet Pro 9015e")
        "Canon" = @("imageCLASS MF445dw", "PIXMA TR8620", "imageRUNNER ADVANCE C5560i")
        "Brother" = @("HL-L2350DW", "MFC-L2750DW", "HL-L8360CDW")
        "Epson" = @("WorkForce Pro WF-4830", "EcoTank ET-4760", "SureColor P700")
        "Xerox" = @("VersaLink C405", "WorkCentre 6515", "Phaser 6510")
    }
    $locations = @(
        "EG - Empfang",
        "EG - Kopierraum",
        "1. OG - Vertrieb",
        "2. OG - IT-Abteilung",
        "3. OG - Geschäftsleitung",
        "Lager - Versand",
        "Besprechungsraum A",
        "Besprechungsraum B"
    )

    $successCount = 0
    $errorCount = 0
    $usedNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    for ($i = 1; $i -le $printerCount; $i++) {
        Write-GuiProgress -Current $i -Total $printerCount -Text "Erstelle Drucker"
        try {
            # Eindeutigen Namen ermitteln (im Lauf und in der Ziel-OU)
            $printerName = $null
            for ($attempt = 0; $attempt -lt 20 -and -not $printerName; $attempt++) {
                $candidate = "PRN-$typeCode-$(Get-Random -Minimum 1000 -Maximum 10000)"
                if ($usedNames.Contains($candidate)) { continue }
                $existing = Get-ADObject -Filter "Name -eq '$candidate'" -SearchBase $resourceOU -SearchScope OneLevel -ErrorAction SilentlyContinue
                if (-not $existing) { $printerName = $candidate }
            }
            if (-not $printerName) { throw "Kein freier Druckername gefunden." }
            [void]$usedNames.Add($printerName)

            $manufacturer = @($manufacturers.Keys) | Get-Random
            $model = $manufacturers[$manufacturer] | Get-Random
            $isColor = $model -like "*Color*" -or $model -like "*PIXMA*" -or $model -like "*EcoTank*" -or $model -like "*SureColor*" -or $model -like "*VersaLink*"

            # Pflichtattribute der Klasse printQueue: printerName, serverName, shortServerName, uNCName, versionNumber
            $printerAttributes = @{
                'printerName' = "$printerName ($manufacturer $model)"
                'serverName' = $printServerFqdn
                'shortServerName' = $printServer
                'uNCName' = "\\$printServerFqdn\$printerName"
                'versionNumber' = [int]4
                'printShareName' = $printerName
                'location' = $locations | Get-Random
                'description' = "$type - $manufacturer $model (Testobjekt)"
                'driverName' = "$manufacturer Universal Print Driver"
                'driverVersion' = [int]4
                'printColor' = [bool]$isColor
                'printDuplexSupported' = $true
                'printStaplingSupported' = [bool]($typeCode -eq "MFP")
                'printMaxResolutionSupported' = [int]$(if ($manufacturer -eq "Epson") { 2400 } else { 1200 })
                'portName' = [string[]]@("IP_192.0.2.$(Get-Random -Minimum 10 -Maximum 250)")
            }

            $printer = New-ADObject -Name $printerName -Type 'printQueue' -Path $resourceOU `
                -OtherAttributes $printerAttributes -PassThru -ErrorAction Stop
            $script:CreatedPrinters.Add([string]$printer.DistinguishedName)
            Write-AppLog "Drucker '$printerName' erstellt" -Level "SUCCESS"
            $successCount++
        } catch {
            Write-AppLog "Fehler beim Erstellen eines Druckers: $($_.Exception.Message)" -Level "ERROR"
            $errorCount++
        }
    }

    Hide-Progress
    Show-CreatedObjectCount
    Write-AppLog "Drucker erstellt: $successCount erfolgreich, $errorCount Fehler" -Level "INFO"
    [System.Windows.MessageBox]::Show(
        "Drucker-Erstellung abgeschlossen.`n`nTyp: $type`nErstellt: $successCount`nFehler: $errorCount`nZiel-OU: $resourceOU",
        "Drucker erstellt", "OK", "Information") | Out-Null
}

function Remove-CreatedPrinter {
    <#
    .SYNOPSIS
    Löscht alle vom Tool erstellten Drucker-Objekte (printQueue)
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Löschung aller erstellten Drucker..." -Level "INFO"

    if ($script:CreatedPrinters.Count -eq 0) {
        Write-AppLog "Keine Drucker zum Löschen vorhanden" -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden in dieser Sitzung noch keine Drucker erstellt.", "Hinweis", "OK", "Information") | Out-Null
        return
    }

    $result = [System.Windows.MessageBox]::Show(
        "Möchten Sie wirklich ALLE $($script:CreatedPrinters.Count) erstellten Drucker-Objekte löschen?`n`nDiese Aktion kann nicht rückgängig gemacht werden!",
        "Drucker löschen", "YesNo", "Warning")
    if ($result -ne "Yes") {
        Write-AppLog "Drucker-Löschung abgebrochen" -Level "INFO"
        return
    }
    if (-not $PSCmdlet.ShouldProcess("$($script:CreatedPrinters.Count) Drucker-Objekte", "Löschen")) { return }

    $outcome = Remove-CreatedPrinterObject
    Show-CreatedObjectCount
    [System.Windows.MessageBox]::Show("Drucker-Löschung abgeschlossen.`n`nGelöscht: $($outcome.Deleted)`nFehler: $($outcome.Failed)", "Abgeschlossen", "OK", "Information") | Out-Null
}

function Remove-CreatedPrinterObject {
    <#
    .SYNOPSIS
    Löscht die nachverfolgten printQueue-Objekte ohne Rückfrage (für 'Drucker löschen' und 'Alles löschen')
    .OUTPUTS
    Objekt mit den Zählern Deleted und Failed
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $deleted = 0
    $failed = 0
    $printersToDelete = @($script:CreatedPrinters)

    Show-Progress -Text "Lösche Drucker..."
    for ($i = 0; $i -lt $printersToDelete.Count; $i++) {
        $printerDn = $printersToDelete[$i]
        Write-GuiProgress -Current ($i + 1) -Total $printersToDelete.Count -Text "Lösche Drucker"
        if (-not $PSCmdlet.ShouldProcess($printerDn, "Drucker-Objekt löschen")) { continue }
        try {
            Remove-ADObject -Identity $printerDn -Confirm:$false -ErrorAction Stop
            Write-AppLog "Drucker '$printerDn' gelöscht" -Level "SUCCESS"
            [void]$script:CreatedPrinters.Remove($printerDn)
            $deleted++
        } catch {
            if (Test-ADIdentityNotFound -ErrorRecord $_) {
                Write-AppLog "Drucker '$printerDn' existiert nicht mehr" -Level "INFO"
                [void]$script:CreatedPrinters.Remove($printerDn)
            } else {
                Write-AppLog "Fehler beim Löschen des Druckers '$printerDn': $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
        }
    }
    Hide-Progress

    return [PSCustomObject]@{ Deleted = $deleted; Failed = $failed }
}

function New-ComputerBitLockerData {
    <#
    .SYNOPSIS
    Erstellt BitLocker Recovery Keys für ausgewählte Computer
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte BitLocker-Datenerstellung für Computer..." -Level "INFO"

        if (-not $script:CreatedComputers -or $script:CreatedComputers.Count -eq 0) {
            Write-AppLog "Keine Computer für BitLocker-Daten vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        # Anzahl der Computer bestimmen
        $computerCount = $script:GuiControls.TextBoxBitLockerComputerCount.Text
        $randomSelection = [bool]$script:GuiControls.CheckBoxBitLockerRandomSelection.IsChecked

        if ([string]::IsNullOrWhiteSpace($computerCount)) {
            $computerCount = $script:CreatedComputers.Count
        } else {
            $computerCount = ConvertTo-IntOrZero -Value $computerCount
            if ($computerCount -gt $script:CreatedComputers.Count) {
                $computerCount = $script:CreatedComputers.Count
                Write-AppLog "Anzahl auf verfügbare Computer reduziert: $computerCount" -Level "INFO"
            }
        }

        if ($computerCount -le 0) {
            Write-AppLog "Ungültige Anzahl Computer für BitLocker" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Computern an.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie BitLocker Recovery Keys für $computerCount Computer erstellen?`n`n" +
            "Zufällige Auswahl: $(if ($randomSelection) { 'Ja' } else { 'Nein (erste X Computer)' })",
            "BitLocker Keys erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess("Erstellte Computer", "BitLocker-Wiederherstellungsdaten erstellen")) { return }

        Show-Progress -Text "Erstelle BitLocker Recovery Keys..."

        # Computer auswählen
        # @() erzwingt ein Array - bei nur einem Computer würde sonst ein String indiziert (einzelnes Zeichen)
        $selectedComputers = @(if ($randomSelection) {
            $script:CreatedComputers | Get-Random -Count $computerCount
        } else {
            $script:CreatedComputers | Select-Object -First $computerCount
        })

        $successCount = 0
        $errorCount = 0
        $bitlockerData = New-Object System.Collections.Generic.List[object]
        $exportPath = $null
        $docPath = $null

        for ($i = 0; $i -lt $selectedComputers.Count; $i++) {
            $computer = $selectedComputers[$i]
            Write-GuiProgress -Current ($i + 1) -Total $selectedComputers.Count -Text "Erstelle BitLocker Key für $computer"

            try {
                # Generiere Recovery-Informationen
                $recoveryGuid = [System.Guid]::NewGuid()
                $recoveryPassword = Get-BitLockerRecoveryPassword
                $recoveryId = $recoveryPassword.Substring(0, 8)
                # 40 Hex-Zeichen (20 Zufallsbytes) - eine GUID hat nur 32 Hex-Zeichen
                $tpmBytes = New-Object byte[] 20
                $script:CryptoRng.GetBytes($tpmBytes)
                $tpmKeyHash = ([System.BitConverter]::ToString($tpmBytes) -replace '-', '').ToUpper()

                # Hole Computer-Objekt
                $computerObj = Get-ADComputer -Identity $computer -ErrorAction Stop

                # Simuliere verschiedene BitLocker-Attribute
                $bitlockerAttributes = @{
                    'msTPM-OwnerInformation' = $tpmKeyHash
                    'info' = "BitLocker-Wiederherstellungs-ID: $recoveryId`nSchutzstatus: aktiviert`nVerschlüsselung: AES-256`nTPM: vorhanden und bereit (simuliert)"
                }

                # Setze Attribute am Computer-Objekt
                Set-ADComputer -Identity $computer -Replace $bitlockerAttributes -ErrorAction Stop

                # Versuche msFVE-RecoveryInformation zu erstellen (benötigt spezielle Rechte)
                try {
                    New-ADObject -Name $recoveryGuid.ToString() `
                        -Type 'msFVE-RecoveryInformation' `
                        -Path $computerObj.DistinguishedName `
                        -OtherAttributes @{
                            'msFVE-RecoveryGuid' = $recoveryGuid.ToByteArray()
                            'msFVE-RecoveryPassword' = $recoveryPassword
                            'msFVE-VolumeGuid' = [System.Guid]::NewGuid().ToByteArray()
                        } `
                        -ErrorAction Stop

                    Write-AppLog "BitLocker Recovery-Objekt für '$computer' erstellt" -Level "DEBUG"
                } catch {
                    # Fallback wenn keine Rechte für msFVE-RecoveryInformation
                    Write-AppLog "Konnte msFVE-RecoveryInformation für '$computer' nicht erstellen (Rechte/Schema), verwende Fallback: $($_.Exception.Message)" -Level "DEBUG"
                }

                # Speichere Daten für Export
                $bitlockerData.Add([PSCustomObject]@{
                    ComputerName = $computer
                    RecoveryID = $recoveryId
                    RecoveryPassword = $recoveryPassword
                    RecoveryGuid = $recoveryGuid
                    TPMKeyHash = $tpmKeyHash
                    EncryptionMethod = "AES-256"
                    ProtectionStatus = "Enabled"
                    VolumeType = "OperatingSystem"
                    CreatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                })

                $successCount++
                Write-AppLog "BitLocker-Daten für '$computer' erstellt" -Level "SUCCESS"

            } catch {
                Write-AppLog "Fehler bei BitLocker-Daten für '$computer': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }

        # Exportiere BitLocker-Daten
        if ($bitlockerData.Count -gt 0) {
            $exportPath = Get-ExportFilePath -FileName "BitLocker_ComputerKeys_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $bitlockerData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-AppLog "BitLocker-Keys exportiert nach: $exportPath" -Level "INFO"

            # Erstelle zusätzliche Dokumentation
            $docPath = Get-ExportFilePath -FileName "BitLocker_Documentation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            $documentation = @"
BitLocker Recovery Keys Dokumentation
=====================================
Erstellt am: $(Get-Date)
Computer verarbeitet: $($selectedComputers.Count)
Erfolgreich: $successCount
Fehler: $errorCount

Recovery Key Format:
--------------------
Die Recovery Keys bestehen aus 8 Blöcken mit je 6 Ziffern (48 Ziffern gesamt).
Format: XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX

Wichtige Hinweise:
------------------
- Recovery Keys sicher aufbewahren!
- Keys sind pro Volume eindeutig
- Bei echtem BitLocker werden Keys in AD unter CN=<GUID>,<Computer DN> gespeichert
- TPM-Informationen sind in msTPM-OwnerInformation gespeichert

Test-Szenarien:
---------------
1. Recovery Key Abfrage simulieren
2. TPM-Status prüfen
3. Verschlüsselungsstatus testen
4. Key-Rotation durchführen
"@
            $documentation | Out-File -FilePath $docPath -Encoding UTF8
        }

        Hide-Progress

        $message = @"
BitLocker-Daten erfolgreich erstellt:

Computer ausgewählt: $($selectedComputers.Count)
Erfolgreich: $successCount
Fehler: $errorCount

Dateien erstellt:
- Keys: $exportPath
- Dokumentation: $docPath
"@

        [System.Windows.MessageBox]::Show($message, "BitLocker-Daten erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei BitLocker-Datenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-LAPSData {
    <#
    .SYNOPSIS
    Erstellt LAPS (Local Administrator Password Solution) Daten für ausgewählte Systeme
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte LAPS-Datenerstellung..." -Level "INFO"

        if (-not $script:CreatedComputers -or $script:CreatedComputers.Count -eq 0) {
            Write-AppLog "Keine Computer für LAPS-Daten vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        # Parameter auslesen
        $systemCount = $script:GuiControls.TextBoxLAPSSystemCount.Text
        $includeServers = [bool]$script:GuiControls.CheckBoxLAPSIncludeServers.IsChecked
        $includeWorkstations = [bool]$script:GuiControls.CheckBoxLAPSIncludeWorkstations.IsChecked

        if (-not ($includeServers -or $includeWorkstations)) {
            Write-AppLog "Keine System-Typen für LAPS ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens einen System-Typ aus (Server oder Workstations).", "Hinweis", "OK", "Warning")
            return
        }

        # Systeme filtern
        $eligibleSystems = New-Object System.Collections.Generic.List[object]
        foreach ($computer in $script:CreatedComputers) {
            try {
                $compObj = Get-ADComputer -Identity $computer -Properties OperatingSystem -ErrorAction Stop
                $os = $compObj.OperatingSystem

                $isServer = $os -like "*Server*"
                $isWorkstation = $os -notlike "*Server*"

                if (($isServer -and $includeServers) -or ($isWorkstation -and $includeWorkstations)) {
                    $eligibleSystems.Add([PSCustomObject]@{
                        Name = $computer
                        Type = if ($isServer) { "Server" } else { "Workstation" }
                        OS = $os
                    })
                }
            } catch {
                Write-AppLog "Fehler beim Prüfen von Computer '$computer': $($_.Exception.Message)" -Level "DEBUG"
            }
        }

        if ($eligibleSystems.Count -eq 0) {
            Write-AppLog "Keine passenden Systeme für LAPS gefunden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Keine passenden Systeme für die ausgewählten Kriterien gefunden.", "Hinweis", "OK", "Warning")
            return
        }

        # Anzahl bestimmen
        if ([string]::IsNullOrWhiteSpace($systemCount)) {
            $systemCount = $eligibleSystems.Count
        } else {
            $systemCount = ConvertTo-IntOrZero -Value $systemCount
            if ($systemCount -gt $eligibleSystems.Count) {
                $systemCount = $eligibleSystems.Count
                Write-AppLog "Anzahl auf verfügbare Systeme reduziert: $systemCount" -Level "INFO"
            }
        }

        if ($systemCount -le 0) {
            Write-AppLog "Ungültige Anzahl Systeme für LAPS" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Systemen an.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie LAPS-Passwörter für $systemCount Systeme erstellen?`n`n" +
            "Verfügbare Systeme: $($eligibleSystems.Count)`n" +
            "Server: $(@($eligibleSystems | Where-Object { $_.Type -eq 'Server' }).Count)`n" +
            "Workstations: $(@($eligibleSystems | Where-Object { $_.Type -eq 'Workstation' }).Count)",
            "LAPS-Passwörter erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess("Erstellte Computer", "LAPS-Testdaten setzen")) { return }

        Show-Progress -Text "Erstelle LAPS-Passwörter..."

        # Systeme auswählen
        # @() erzwingt ein Array (bei genau einem System sonst kein Indexzugriff möglich)
        $selectedSystems = @($eligibleSystems | Get-Random -Count $systemCount)

        $successCount = 0
        $errorCount = 0
        $lapsData = New-Object System.Collections.Generic.List[object]

        # LAPS-Passwort-Richtlinien
        $passwordComplexity = @{
            Server = 20       # Längere Passwörter für Server
            Workstation = 14  # Standard für Workstations
        }

        for ($i = 0; $i -lt $selectedSystems.Count; $i++) {
            $system = $selectedSystems[$i]
            Write-GuiProgress -Current ($i + 1) -Total $selectedSystems.Count -Text "Erstelle LAPS-Passwort für $($system.Name)"

            try {
                # Generiere LAPS-Passwort basierend auf System-Typ
                $pwdLength = $passwordComplexity[$system.Type]
                $lapsPassword = Get-RandomPasswordText -Complexity "Komplex (16 Zeichen + Spezial)" -IncludeNumbers $true -IncludeSymbols $true -ExcludeAmbiguous $true -Length $pwdLength

                # Setze Ablaufdatum (Standard: 30 Tage)
                $expirationTime = (Get-Date).AddDays(30).ToFileTimeUtc()

                # LAPS-Attribute setzen
                $lapsAttributes = @{
                    'ms-Mcs-AdmPwd' = $lapsPassword
                    'ms-Mcs-AdmPwdExpirationTime' = $expirationTime.ToString()
                }

                # Versuche die offiziellen LAPS-Attribute zu setzen
                try {
                    Set-ADComputer -Identity $system.Name -Replace $lapsAttributes -ErrorAction Stop
                    Write-AppLog "LAPS-Attribute für '$($system.Name)' gesetzt" -Level "DEBUG"
                } catch {
                    # Fallback: Verwende Custom-Attribute
                    $fallbackAttributes = @{
                        'adminDescription' = "LAPS-Kennwort gesetzt: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        'info' = "LAPS aktiv | Kennwortlänge: $pwdLength | Ablauf: $((Get-Date).AddDays(30).ToString('yyyy-MM-dd'))"
                        'comment' = "LAPS-Testkennwort (simuliert) im Attribut ms-Mcs-AdmPwd"
                    }

                    Set-ADComputer -Identity $system.Name -Replace $fallbackAttributes -ErrorAction Stop
                    Write-AppLog "LAPS-Daten als Custom-Attribute gespeichert (Fallback)" -Level "DEBUG"
                }

                # Speichere LAPS-Daten für Export
                $lapsData.Add([PSCustomObject]@{
                    ComputerName = $system.Name
                    SystemType = $system.Type
                    OperatingSystem = $system.OS
                    LocalAdminPassword = $lapsPassword
                    PasswordLength = $pwdLength
                    PasswordSetDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    PasswordExpiryDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd HH:mm:ss")
                    LastChangeBy = $env:USERNAME
                    Status = "Active"
                })

                $successCount++
                Write-AppLog "LAPS-Passwort für '$($system.Name)' erstellt" -Level "SUCCESS"

            } catch {
                Write-AppLog "Fehler bei LAPS-Passwort für '$($system.Name)': $($_.Exception.Message)" -Level "ERROR"
                $lapsData.Add([PSCustomObject]@{
                    ComputerName = $system.Name
                    SystemType = $system.Type
                    OperatingSystem = $system.OS
                    LocalAdminPassword = "ERROR"
                    PasswordLength = 0
                    PasswordSetDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    PasswordExpiryDate = "N/A"
                    LastChangeBy = $env:USERNAME
                    Status = "Failed: $($_.Exception.Message)"
                })
                $errorCount++
            }
        }

        # Exportiere LAPS-Daten
        if ($lapsData.Count -gt 0) {
            $exportPath = (Get-ExportFilePath -FileName "LAPS_Passwords_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
            $lapsData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-AppLog "LAPS-Passwörter exportiert nach: $exportPath" -Level "INFO"

            # Erstelle LAPS-Bericht
            $reportPath = (Get-ExportFilePath -FileName "LAPS_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt")
            $report = @"
LAPS (Local Administrator Password Solution) Bericht
===================================================
Erstellt am: $(Get-Date)
Erstellt von: $env:USERNAME

Zusammenfassung:
----------------
Systeme verarbeitet: $($selectedSystems.Count)
Erfolgreich: $successCount
Fehler: $errorCount

Systemverteilung:
-----------------
Server: $(@($lapsData | Where-Object { $_.SystemType -eq 'Server' -and $_.Status -eq 'Active' }).Count)
Workstations: $(@($lapsData | Where-Object { $_.SystemType -eq 'Workstation' -and $_.Status -eq 'Active' }).Count)

Passwort-Richtlinien:
---------------------
Server: $($passwordComplexity.Server) Zeichen
Workstations: $($passwordComplexity.Workstation) Zeichen
Gültigkeit: 30 Tage
Komplexität: Groß-/Kleinbuchstaben, Zahlen, Sonderzeichen

LAPS-Attribute in AD:
---------------------
- ms-Mcs-AdmPwd: Lokales Admin-Passwort (verschlüsselt)
- ms-Mcs-AdmPwdExpirationTime: Ablaufdatum
- ms-Mcs-AdmPwdHistory: Passwort-Historie (optional)

Sicherheitshinweise:
--------------------
- LAPS-Passwörter sind nur für berechtigte Administratoren sichtbar
- Passwörter werden automatisch nach Ablauf erneuert
- Jedes System hat ein eindeutiges Passwort
- Passwörter sollten niemals manuell geändert werden

PowerShell-Befehle:
-------------------
# LAPS-Passwort abrufen:
Get-ADComputer -Identity <ComputerName> -Properties ms-Mcs-AdmPwd,ms-Mcs-AdmPwdExpirationTime

# Passwort-Ablauf erzwingen:
Set-ADComputer -Identity <ComputerName> -Replace @{'ms-Mcs-AdmPwdExpirationTime'='0'}

# LAPS-Status prüfen:
Get-ADComputer -Filter * -Properties ms-Mcs-AdmPwd,ms-Mcs-AdmPwdExpirationTime |
    Where-Object {$_.ms-Mcs-AdmPwd} |
    Select Name,ms-Mcs-AdmPwdExpirationTime
"@
            $report | Out-File -FilePath $reportPath -Encoding UTF8
        }

        Hide-Progress

        $message = @"
LAPS-Passwörter erfolgreich erstellt:

Systeme verarbeitet: $($selectedSystems.Count)
Erfolgreich: $successCount
Fehler: $errorCount

Dateien erstellt:
- Passwörter: $exportPath
- Bericht: $reportPath

WICHTIG: Die exportierte CSV enthält Klartext-Passwörter!
Diese Datei muss sicher aufbewahrt oder nach dem Test gelöscht werden.
"@

        [System.Windows.MessageBox]::Show($message, "LAPS-Passwörter erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei LAPS-Datenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

#endregion

#region Test-Szenarien - Implementierung

function New-TestDataSet {
    <#
    .SYNOPSIS
    Erstellt umfangreiche Testdaten-Sets mit realistischer Verteilung
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Testdaten-Set Erstellung..." -Level "INFO"

        $dataSize = $script:GuiControls.ComboBoxTestDataSize.SelectedItem
        if (-not $dataSize) {
            Write-AppLog "Keine Testdaten-Größe ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Testdaten-Größe aus.", "Hinweis", "OK", "Warning")
            return
        }

        $realisticData = $script:GuiControls.CheckBoxRealisticData.IsChecked
        $historicalData = [bool]$script:GuiControls.CheckBoxHistoricalData.IsChecked

        # Bestimme Anzahl der zu erstellenden Objekte
        $objectCounts = switch ($dataSize.Content) {
            "Klein (10-50 Objekte)" { @{Users=30; Groups=10; Computers=10} }
            "Mittel (50-500 Objekte)" { @{Users=200; Groups=50; Computers=100} }
            "Groß (500-5000 Objekte)" { @{Users=2000; Groups=200; Computers=500} }
            "Enterprise (5000+ Objekte)" { @{Users=10000; Groups=500; Computers=2000} }
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie folgendes Testdaten-Set erstellen?`n`n" +
            "- $($objectCounts.Users) Benutzer`n" +
            "- $($objectCounts.Groups) Gruppen`n" +
            "- $($objectCounts.Computers) Computer`n`n" +
            "Realistische Verteilung: $(if ($realisticData) { 'Ja' } else { 'Nein' })`n" +
            "Historische Daten: $(if ($historicalData) { 'Ja' } else { 'Nein' })",
            "Testdaten-Set erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "Testdaten-Set erstellen")) { return }

        # Basis-OU für Testdaten
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        # Erstelle Test-OU-Struktur
        Show-Progress -Text "Erstelle Test-OU-Struktur..." -Value 0
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        $usersPath = if ($testOUs["USERS"]) { $testOUs["USERS"] } else { $targetOU }
        $groupsPath = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }
        $computersPath = if ($testOUs["COMPUTERS"]) { $testOUs["COMPUTERS"] } else { $targetOU }
        $usersByDepartment = @{}

        $totalObjects = $objectCounts.Users + $objectCounts.Groups + $objectCounts.Computers
        $currentObject = 0
        $createdUserCount = 0
        $createdGroupCount = 0
        $createdComputerCount = 0
        $usedSamNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        $usedCNs = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

        # Realistische Abteilungsverteilung
        $departmentDistribution = if ($realisticData) {
            @{
                "IT" = 0.15
                "Sales" = 0.25
                "Marketing" = 0.10
                "HR" = 0.05
                "Finance" = 0.10
                "Operations" = 0.20
                "Support" = 0.10
                "Management" = 0.05
            }
        } else {
            # Gleichmäßige Verteilung
            $depts = @("IT", "Sales", "Marketing", "HR", "Finance", "Operations", "Support", "Management")
            $distribution = @{}
            $depts | ForEach-Object { $distribution[$_] = 1.0 / $depts.Count }
            $distribution
        }

        # 1. Erstelle Benutzer
        Write-GuiProgress -Current 0 -Total $totalObjects -Text "Erstelle Benutzer..."

        foreach ($dept in $departmentDistribution.Keys) {
            $deptUserCount = [math]::Round($objectCounts.Users * $departmentDistribution[$dept])
            $usersByDepartment[$dept] = New-Object System.Collections.Generic.List[string]

            for ($i = 1; $i -le $deptUserCount; $i++) {
                $currentObject++

                try {
                    $firstName = Get-RandomFirstName
                    $lastName = Get-RandomLastName
                    $samAccountName = Get-UniqueSamAccountName -GivenName $firstName -Surname $lastName -UsedNames $usedSamNames
                    $commonName = Get-AvailableObjectName -Name "$firstName $lastName" -Path $usersPath -Suffix $samAccountName -UsedNames $usedCNs

                    # Historische Daten simulieren
                    $createdDate = if ($historicalData) {
                        # Zufälliges Datum in den letzten 5 Jahren
                        (Get-Date).AddDays(-(Get-Random -Minimum 0 -Maximum 1825))
                    } else {
                        Get-Date
                    }

                    $userParams = @{
                        Name = $commonName
                        SamAccountName = $samAccountName
                        UserPrincipalName = (Get-UserPrincipalName -SamAccountName $samAccountName)
                        GivenName = $firstName
                        Surname = $lastName
                        DisplayName = "$firstName $lastName"
                        Department = $dept
                        Title = Get-RandomJobTitle
                        Company = "Testfirma"
                        City = Get-RandomCity
                        StreetAddress = Get-RandomStreetAddress
                        PostalCode = Get-RandomPostalCode
                        Country = "DE"
                        OfficePhone = Get-RandomPhoneNumber
                        MobilePhone = Get-RandomPhoneNumber
                        Path = $usersPath
                        Enabled = $true
                        AccountPassword = (Get-InitialUserPassword)
                        ChangePasswordAtLogon = $false
                    }

                    # whenCreated ist systemverwaltet und kann nicht gesetzt werden -> historisches Datum in der Beschreibung
                    if ($historicalData) {
                        $userParams.Description = "Simuliertes Erstellungsdatum: $($createdDate.ToString('yyyy-MM-dd'))"
                    }

                    New-ADUser @userParams -ErrorAction Stop
                    $script:CreatedUsers.Add($samAccountName)
                    $usersByDepartment[$dept].Add($samAccountName)
                    $createdUserCount++

                } catch {
                    Write-AppLog "Fehler beim Erstellen von Testbenutzer: $($_.Exception.Message)" -Level "WARN"
                }

                if ($currentObject % 10 -eq 0) {
                    Write-GuiProgress -Current $currentObject -Total $totalObjects -Text "Erstelle Objekte"
                }
            }
        }

        # 2. Erstelle Gruppen
        Write-GuiProgress -Current $currentObject -Total $totalObjects -Text "Erstelle Gruppen..."

        # Erstelle Abteilungsgruppen
        foreach ($dept in $departmentDistribution.Keys) {
            try {
                $groupName = "GRP_$dept"
                New-ADGroup -Name $groupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description "Abteilungsgruppe $dept" `
                    -Path $groupsPath `
                    -ErrorAction Stop

                $script:CreatedGroups.Add($groupName)
                $createdGroupCount++
                $currentObject++

                # Nur die in diesem Lauf erstellten Benutzer der Abteilung hinzufügen (ohne erneute AD-Abfrage)
                $deptUsers = $usersByDepartment[$dept]
                if ($deptUsers -and $deptUsers.Count -gt 0) {
                    Add-ADGroupMember -Identity $groupName -Members $deptUsers.ToArray() -ErrorAction SilentlyContinue
                }

            } catch {
                Write-AppLog "Fehler beim Erstellen von Gruppe '$groupName': $($_.Exception.Message)" -Level "WARN"
            }
        }

        # Erstelle zusätzliche Gruppen
        $additionalGroupCount = $objectCounts.Groups - $departmentDistribution.Keys.Count
        for ($i = 1; $i -le $additionalGroupCount; $i++) {
            try {
                $groupType = @("Project", "Security", "Distribution", "Resource", "Application") | Get-Random
                $groupName = "$groupType`_Group_$(Get-Random -Minimum 1000 -Maximum 9999)"

                New-ADGroup -Name $groupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description "Testgruppe ($groupType)" `
                    -Path $groupsPath `
                    -ErrorAction Stop

                $script:CreatedGroups.Add($groupName)
                $createdGroupCount++
                $currentObject++

            } catch {
                Write-AppLog "Fehler beim Erstellen von Gruppe: $($_.Exception.Message)" -Level "WARN"
            }
        }

        # 3. Erstelle Computer
        Write-GuiProgress -Current $currentObject -Total $totalObjects -Text "Erstelle Computer..."

        $computerTypes = if ($realisticData) {
            @{
                "Arbeitsplatzrechner" = 0.60
                "Notebooks" = 0.25
                "Server" = 0.10
                "Virtuelle Maschinen" = 0.05
            }
        } else {
            @{
                "Arbeitsplatzrechner" = 0.25
                "Notebooks" = 0.25
                "Server" = 0.25
                "Virtuelle Maschinen" = 0.25
            }
        }

        foreach ($compType in $computerTypes.Keys) {
            $typeCount = [math]::Round($objectCounts.Computers * $computerTypes[$compType])
            $typePrefix = switch ($compType) {
                "Arbeitsplatzrechner" { "WS" }
                "Notebooks" { "LT" }
                "Server" { "SRV" }
                "Virtuelle Maschinen" { "VM" }
            }

            for ($i = 1; $i -le $typeCount; $i++) {
                try {
                    $computerName = "$typePrefix-TEST-$(Get-Random -Minimum 10000 -Maximum 99999)"

                    New-ADComputer -Name $computerName `
                        -SamAccountName "$computerName`$" `
                        -Path $computersPath `
                        -Enabled $true `
                        -Description "$compType - Testdaten-Set" `
                        -OperatingSystem $(if ($compType -eq "Server") { "Windows Server 2022" } else { "Windows 11" }) `
                        -ErrorAction Stop

                    $script:CreatedComputers.Add($computerName)
                    $createdComputerCount++
                    $currentObject++

                } catch {
                    Write-AppLog "Fehler beim Erstellen von Computer: $($_.Exception.Message)" -Level "WARN"
                }
            }
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = @"
Testdaten-Set erstellt:

Benutzer: $createdUserCount von $($objectCounts.Users)
Gruppen: $createdGroupCount von $($objectCounts.Groups)
Computer: $createdComputerCount von $($objectCounts.Computers)

Die Objekte wurden in dedizierten Test-OUs erstellt.
Details zu Fehlern finden Sie im Protokoll.
"@

        [System.Windows.MessageBox]::Show($message, "Testdaten erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Testdaten-Set Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-ChaosTestData {
    <#
    .SYNOPSIS
    Aktiviert den Chaos-Modus für fehlerhafte/problematische Testdaten
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "WARNUNG: Chaos-Modus wird aktiviert..." -Level "WARN"

        $invalidData = $script:GuiControls.CheckBoxInvalidData.IsChecked
        $missingAttributes = $script:GuiControls.CheckBoxMissingAttributes.IsChecked
        $duplicateEntries = $script:GuiControls.CheckBoxDuplicateEntries.IsChecked
        $specialCharacters = [bool]$script:GuiControls.CheckBoxSpecialCharacters.IsChecked

        if (-not ($invalidData -or $missingAttributes -or $duplicateEntries -or $specialCharacters)) {
            Write-AppLog "Keine Chaos-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Chaos-Option aus.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "WARNUNG: Der Chaos-Modus erstellt absichtlich fehlerhafte Daten!`n`n" +
            "Dies kann zu Problemen in Ihrer Test-Umgebung führen.`n`n" +
            "Ausgewählte Optionen:`n" +
            "$(if ($invalidData) { "- Ungültige Daten`n" })" +
            "$(if ($missingAttributes) { "- Fehlende Attribute`n" })" +
            "$(if ($duplicateEntries) { "- Doppelte Einträge`n" })" +
            "$(if ($specialCharacters) { "- Sonderzeichen`n" })`n" +
            "Möchten Sie wirklich fortfahren?",
            "CHAOS-MODUS WARNUNG",
            "YesNo",
            "Warning"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "Chaos-Testdaten erstellen")) { return }

        # Basis-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        Show-Progress -Text "Aktiviere Chaos-Modus..."
        # Chaos-Benutzer landen in der Test-OU USERS, damit sie gemeinsam bereinigt werden können
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        if ($testOUs["USERS"]) { $targetOU = $testOUs["USERS"] }
        $chaosCount = 0
        $errorCount = 0

        # 1. Ungültige Daten
        if ($invalidData) {
            Write-GuiProgress -Current 25 -Total 100 -Text "Erstelle ungültige Daten..."

            # Benutzer mit ungültigen E-Mail-Adressen
            for ($i = 1; $i -le 5; $i++) {
                try {
                    $invalidUser = @{
                        Name = "Invalid_User_$i"
                        SamAccountName = "invalid.user.$i"
                        Path = $targetOU
                        Enabled = $false # Deaktiviert, falls die Domänen-Richtlinie das zu kurze Passwort akzeptiert
                        EmailAddress = "not@valid@email@address.com"
                        AccountPassword = (Get-RandomSecurePassword -Complexity "Einfach (8 Zeichen)" -Length 4) # Absichtlich zu kurzes (zufälliges) Passwort
                    }

                    New-ADUser @invalidUser -ErrorAction Stop
                    $script:CreatedUsers.Add($invalidUser.SamAccountName)
                    $chaosCount++
                } catch {
                    Write-AppLog "Erwarteter Fehler bei ungültigen Daten: $($_.Exception.Message)" -Level "DEBUG"
                    $errorCount++
                    # New-ADUser legt das Objekt bei abgelehntem Passwort ggf. trotzdem (deaktiviert) an -> nachverfolgen, damit es bereinigt werden kann
                    $orphan = Get-ADUser -Filter "SamAccountName -eq '$(ConvertTo-ADFilterValue -Value $invalidUser.SamAccountName)'" -ErrorAction SilentlyContinue
                    if ($orphan -and -not $script:CreatedUsers.Contains($invalidUser.SamAccountName)) {
                        $script:CreatedUsers.Add($invalidUser.SamAccountName)
                    }
                }
            }
        }

        # 2. Fehlende Attribute
        if ($missingAttributes) {
            Write-GuiProgress -Current 50 -Total 100 -Text "Erstelle Benutzer mit fehlenden Attributen..."

            for ($i = 1; $i -le 5; $i++) {
                try {
                    $incompleteUser = @{
                        Name = "Incomplete_User_$i"
                        SamAccountName = "incomplete.user.$i"
                        Path = $targetOU
                        Enabled = $true
                        AccountPassword = (Get-RandomSecurePassword)
                        # Absichtlich fehlende Attribute: GivenName, Surname, DisplayName, Email
                    }

                    New-ADUser @incompleteUser -ErrorAction Stop
                    $script:CreatedUsers.Add($incompleteUser.SamAccountName)
                    $chaosCount++
                } catch {
                    Write-AppLog "Fehler bei Benutzer mit fehlenden Attributen: $($_.Exception.Message)" -Level "DEBUG"
                    $errorCount++
                }
            }
        }

        # 3. Doppelte Einträge
        if ($duplicateEntries) {
            Write-GuiProgress -Current 75 -Total 100 -Text "Versuche doppelte Einträge zu erstellen..."

            # Versuche denselben Benutzer mehrmals zu erstellen
            $duplicateName = "duplicate.user"
            for ($i = 1; $i -le 3; $i++) {
                try {
                    New-ADUser -Name "Duplicate User" `
                        -SamAccountName $duplicateName `
                        -Path $targetOU `
                        -Enabled $true `
                        -AccountPassword (Get-RandomSecurePassword) `
                        -ErrorAction Stop

                    if ($i -eq 1) {
                        $script:CreatedUsers.Add($duplicateName)
                        $chaosCount++
                    }
                } catch {
                    if ($i -gt 1) {
                        Write-AppLog "Erwarteter Fehler bei Duplikat: $($_.Exception.Message)" -Level "DEBUG"
                    } else {
                        $errorCount++
                    }
                }
            }
        }

        # 4. Sonderzeichen
        if ($specialCharacters) {
            Write-GuiProgress -Current 100 -Total 100 -Text "Erstelle Einträge mit Sonderzeichen..."

            $specialNames = @(
                "Müller, Dr. Hans-Peter",
                "O'Brien",
                "José García-López",
                "Иван Петров",
                "王小明",
                "Test & User",
                "User (Test)",
                "Test/User"
            )

            $specialIndex = 0
            foreach ($specialName in $specialNames) {
                $specialIndex++
                try {
                    # Normalisiere SamAccountName (rein nicht-lateinische Namen ergeben keinen gültigen Namen)
                    $samName = ConvertTo-NormalizedSamAccountName -SamAccountName $specialName
                    if ([string]::IsNullOrWhiteSpace($samName) -or $samName -notmatch '[A-Za-z0-9]') {
                        $samName = "chaos.sonder$specialIndex"
                    }

                    New-ADUser -Name $specialName `
                        -SamAccountName $samName `
                        -DisplayName $specialName `
                        -Path $targetOU `
                        -Enabled $true `
                        -AccountPassword (Get-RandomSecurePassword) `
                        -ErrorAction Stop

                    $script:CreatedUsers.Add($samName)
                    $chaosCount++
                } catch {
                    Write-AppLog "Fehler bei Sonderzeichen-Benutzer '$specialName': $($_.Exception.Message)" -Level "DEBUG"
                    $errorCount++
                }
            }
        }

        Hide-Progress
        Show-CreatedObjectCount

        $message = @"
Chaos-Modus abgeschlossen:

Erfolgreich erstellt: $chaosCount chaotische Objekte
Erwartete Fehler: $errorCount

Die erstellten Objekte können für Fehlerbehandlungs-Tests verwendet werden.
"@

        [System.Windows.MessageBox]::Show($message, "Chaos-Modus aktiviert", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler im Chaos-Modus: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler im Chaos-Modus:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Start-PerformanceTest {
    <#
    .SYNOPSIS
    Misst die Anlage-Geschwindigkeit von AD-Benutzern in Batches

    .DESCRIPTION
    Legt deaktivierte Testbenutzer (perf_...) in der Test-OU USERS an, misst die Dauer je Batch und speichert
    einen Bericht (TXT) sowie die Messwerte (CSV) im Exportordner. Die Benutzer werden in der Liste der
    erstellten Benutzer nachverfolgt und können über die Benutzer-Löschfunktion entfernt werden.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    Write-AppLog "Starte Performance-Test..." -Level "INFO"

    $objectCount = ConvertTo-IntOrZero -Value ([string]$script:GuiControls.TextBoxPerformanceCount.Text)
    $batchSize = ConvertTo-IntOrZero -Value ([string]$script:GuiControls.TextBoxBatchSize.Text)
    if ($objectCount -lt 1 -or $objectCount -gt 5000 -or $batchSize -lt 1 -or $batchSize -gt $objectCount) {
        Write-AppLog "Ungültige Performance-Test-Parameter (Objekte: $objectCount, Batch: $batchSize)" -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte geben Sie 1 bis 5000 Objekte und eine Batch-Größe zwischen 1 und der Objektanzahl an.", "Hinweis", "OK", "Warning") | Out-Null
        return
    }

    $targetOU = ([string]$script:GuiControls.ComboBoxTargetOU.Text).Trim()
    if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
        $targetOU = (Get-CachedADDomain).DistinguishedName
    }

    $batchCount = [math]::Ceiling($objectCount / $batchSize)
    $result = [System.Windows.MessageBox]::Show(
        "Performance-Test-Konfiguration:`n`n" +
        "Objekte (deaktivierte Benutzer): $objectCount`n" +
        "Batch-Größe: $batchSize`n" +
        "Batches: $batchCount`n" +
        "Ziel: Test-OU 'USERS' unterhalb von $targetOU`n`n" +
        "Dies kann je nach Größe mehrere Minuten dauern. Fortfahren?",
        "Performance-Test starten",
        "YesNo",
        "Question"
    )
    if ($result -ne "Yes") { return }
    if (-not $PSCmdlet.ShouldProcess($targetOU, "$objectCount Performance-Testbenutzer erstellen")) { return }

    Show-Progress -Text "Performance-Test läuft..." -Value 0
    $testOUs = Initialize-TestOU -BaseOU $targetOU
    $userOU = if ($testOUs["USERS"]) { $testOUs["USERS"] } else { $targetOU }

    # Eindeutiges Präfix je Lauf (maximal 20 Zeichen: pt + MMddHHmmss + _ + 4 Ziffern)
    $runId = Get-Date -Format 'MMddHHmmss'
    $batchMetrics = New-Object System.Collections.Generic.List[object]
    $successCount = 0
    $failedCount = 0
    $currentObject = 0
    $totalWatch = [System.Diagnostics.Stopwatch]::StartNew()

    for ($batchNumber = 1; $batchNumber -le $batchCount; $batchNumber++) {
        $batchObjects = [math]::Min($batchSize, $objectCount - $currentObject)
        $batchWatch = [System.Diagnostics.Stopwatch]::StartNew()
        $batchSuccess = 0

        for ($i = 1; $i -le $batchObjects; $i++) {
            $currentObject++
            $samAccountName = "pt${runId}_$('{0:D4}' -f $currentObject)"
            try {
                New-ADUser -Name $samAccountName `
                    -SamAccountName $samAccountName `
                    -UserPrincipalName (Get-UserPrincipalName -SamAccountName $samAccountName) `
                    -Path $userOU `
                    -Enabled $false `
                    -Description "Performance-Testobjekt ($runId)" `
                    -AccountPassword (Get-InitialUserPassword) `
                    -ErrorAction Stop
                $script:CreatedUsers.Add($samAccountName)
                $successCount++
                $batchSuccess++
            } catch {
                $failedCount++
                Write-AppLog "Performance-Test: Fehler bei '$samAccountName': $($_.Exception.Message)" -Level "WARN"
            }
        }

        $batchWatch.Stop()
        $batchMetrics.Add([PSCustomObject]@{
            Batch = $batchNumber
            Objekte = $batchObjects
            Erfolgreich = $batchSuccess
            DauerSekunden = [math]::Round($batchWatch.Elapsed.TotalSeconds, 3)
        })
        Write-AppLog "Batch $batchNumber von $batchCount in $([math]::Round($batchWatch.Elapsed.TotalSeconds, 2)) s abgeschlossen" -Level "DEBUG"
        Write-GuiProgress -Current $currentObject -Total $objectCount -Text "Performance-Test (Batch $batchNumber/$batchCount), Objekte"
    }

    $totalWatch.Stop()
    $totalDuration = $totalWatch.Elapsed.TotalSeconds
    Hide-Progress
    Show-CreatedObjectCount

    $avgBatchTime = ($batchMetrics | Measure-Object -Property DauerSekunden -Average).Average
    $objectsPerSecond = if ($totalDuration -gt 0) { $successCount / $totalDuration } else { 0 }
    $estimate10k = if ($objectsPerSecond -gt 0) { "$([math]::Round(10000 / $objectsPerSecond / 60, 2)) Minuten" } else { "nicht ermittelbar" }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $csvPath = Get-ExportFilePath -FileName "PerformanceTest_$timestamp.csv"
    $batchMetrics | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8 -Delimiter ';'

    $reportPath = Get-ExportFilePath -FileName "PerformanceTest_$timestamp.txt"
    $report = @"
Active-Directory-Performance-Test
=================================
Datum: $(Get-Date)
Ziel-OU: $userOU

Konfiguration:
- Objekte: $objectCount
- Batch-Größe: $batchSize
- Batches: $batchCount

Ergebnisse:
- Gesamtdauer: $([math]::Round($totalDuration, 2)) Sekunden
- Erfolgreich: $successCount
- Fehlgeschlagen: $failedCount
- Durchschnittliche Batch-Dauer: $([math]::Round($avgBatchTime, 2)) Sekunden
- Objekte pro Sekunde: $([math]::Round($objectsPerSecond, 2))
- Hochrechnung für 10.000 Objekte: $estimate10k

Messwerte je Batch: $csvPath
"@
    $report | Out-File -FilePath $reportPath -Encoding UTF8

    Write-AppLog "Performance-Test abgeschlossen: $successCount erstellt, $failedCount Fehler, $([math]::Round($objectsPerSecond, 2)) Objekte/s" -Level "SUCCESS"
    [System.Windows.MessageBox]::Show(
        "Performance-Test abgeschlossen.`n`nDauer: $([math]::Round($totalDuration, 2)) Sekunden`nErstellt: $successCount`nFehler: $failedCount`nLeistung: $([math]::Round($objectsPerSecond, 2)) Objekte/Sekunde`n`nBericht: $reportPath`nMesswerte: $csvPath`n`nDie Testbenutzer können über '🗑️ Löschen' (Erstellte Benutzer verwalten) entfernt werden.",
        "Performance-Test abgeschlossen", "OK", "Information") | Out-Null
}

#endregion

#region Sicherheit & Compliance - Implementierung

function Set-PasswordPolicyTestData {
    <#
    .SYNOPSIS
    Wendet verschiedene Passwort-Richtlinien auf erstellte Benutzer an
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte Anwendung von Passwort-Richtlinien..." -Level "INFO"

        $simulateHistory = $script:GuiControls.CheckBoxSimulatePasswordHistory.IsChecked
        $createLocked = $script:GuiControls.CheckBoxCreateLockedAccounts.IsChecked
        $expiredPasswords = $script:GuiControls.CheckBoxExpiredPasswords.IsChecked
        $lockoutRatio = 10  # Slider existiert nicht in der GUI, Standard: 10%

        if (-not ($simulateHistory -or $createLocked -or $expiredPasswords)) {
            Write-AppLog "Keine Passwort-Richtlinien ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Passwort-Richtlinie aus.", "Hinweis", "OK", "Warning")
            return
        }

        if (-not $script:CreatedUsers -or $script:CreatedUsers.Count -eq 0) {
            Write-AppLog "Keine Benutzer vorhanden für Passwort-Richtlinien" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie folgende Passwort-Richtlinien anwenden?`n`n" +
            "$(if ($simulateHistory) { "- Passwort-Historie simulieren`n" })" +
            "$(if ($createLocked) { "- $lockoutRatio% der Accounts deaktivieren (Sperre simuliert)`n" })" +
            "$(if ($expiredPasswords) { "- Passwörter als abgelaufen markieren`n" })" +
            "`nBetroffene Benutzer: $($script:CreatedUsers.Count)",
            "Passwort-Richtlinien anwenden",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess("Erstellte Benutzer", "Kennwortrichtlinien-Testdaten anwenden")) { return }

        Show-Progress -Text "Wende Passwort-Richtlinien an..."
        $processedCount = 0
        $lockedCount = 0
        $expiredCount = 0
        $historyCount = 0

        # Berechne Anzahl zu sperrender Accounts
        $accountsToLock = if ($createLocked) {
            [math]::Ceiling($script:CreatedUsers.Count * ($lockoutRatio / 100))
        } else { 0 }

        for ($i = 0; $i -lt $script:CreatedUsers.Count; $i++) {
            $user = $script:CreatedUsers[$i]
            Write-GuiProgress -Current ($i + 1) -Total $script:CreatedUsers.Count -Text "Verarbeite Benutzer"

            try {
                # 1. Passwort-Historie simulieren
                if ($simulateHistory) {
                    # AD erlaubt für pwdLastSet nur 0 (Änderung erzwingen) oder -1 (aktueller Zeitpunkt);
                    # beliebige historische Zeitstempel werden vom DC abgelehnt.
                    Set-ADUser -Identity $user -Replace @{ 'pwdLastSet' = 0 } -ErrorAction Stop
                    Set-ADUser -Identity $user -Replace @{ 'pwdLastSet' = -1 } -ErrorAction Stop

                    $historyCount++
                    Write-AppLog "Passwort-Historie für '$user' simuliert" -Level "DEBUG"
                }

                # 2. Account sperren (simuliert)
                if ($createLocked -and $lockedCount -lt $accountsToLock) {
                    # badPwdCount/lockoutTime sind systemverwaltet und können nicht direkt gesetzt werden.
                    # Eine echte Sperre entsteht nur durch fehlgeschlagene Anmeldungen - daher wird der Account deaktiviert.
                    Disable-ADAccount -Identity $user -ErrorAction Stop
                    $lockedCount++
                    Write-AppLog "Account '$user' deaktiviert (Sperre simuliert)" -Level "DEBUG"
                }

                # 3. Passwort als abgelaufen markieren
                if ($expiredPasswords) {
                    # pwdLastSet = 0 markiert das Passwort als abgelaufen (Änderung bei nächster Anmeldung erforderlich)
                    Set-ADUser -Identity $user -ChangePasswordAtLogon $true -ErrorAction Stop

                    $expiredCount++
                    Write-AppLog "Passwort für '$user' als abgelaufen markiert" -Level "DEBUG"
                }

                $processedCount++

            } catch {
                Write-AppLog "Fehler bei Passwort-Richtlinien für '$user': $($_.Exception.Message)" -Level "WARN"
            }
        }

        Hide-Progress

        $message = @"
Passwort-Richtlinien angewendet:

Verarbeitete Benutzer: $processedCount
$(if ($simulateHistory) { "Passwort-Historie simuliert: $historyCount`n" })$(if ($createLocked) { "Gesperrte Konten: $lockedCount`n" })$(if ($expiredPasswords) { "Abgelaufene Passwörter: $expiredCount" })

Die Änderungen können in den Benutzer-Eigenschaften überprüft werden.
"@

        [System.Windows.MessageBox]::Show($message, "Passwort-Richtlinien angewendet", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei Passwort-Richtlinien: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Anwendung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function New-RBACRole {
    <#
    .SYNOPSIS
    Erstellt RBAC-Rollen und Berechtigungsgruppen
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()
    try {
        Write-AppLog "Starte RBAC-Rollen-Erstellung..." -Level "INFO"

        $selectedRole = $script:GuiControls.ComboBoxRBACRoles.SelectedItem
        if (-not $selectedRole) {
            Write-AppLog "Keine RBAC-Rolle ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine RBAC-Rolle aus.", "Hinweis", "OK", "Warning")
            return
        }

        # Feste Anzahl Rolleninstanzen je Klick
        $roleCount = 5

        # Basis-OU
        $targetOU = $script:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $roleCount RBAC-Rollen für '$($selectedRole.Content)' erstellen?`n`n" +
            "Dies erstellt Sicherheitsgruppen mit entsprechenden Beschreibungen und Strukturen.",
            "RBAC-Rollen erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }
        if (-not $PSCmdlet.ShouldProcess($targetOU, "RBAC-Rollengruppen erstellen")) { return }
        # Erstelle Security Groups OU wenn nötig
        $testOUs = Initialize-TestOU -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }

        Show-Progress -Text "Erstelle RBAC-Rollen..."
        $successCount = 0
        $errorCount = 0

        # RBAC-Rollen-Definitionen
        $rbacDefinitions = @{
            "Helpdesk Operator" = @{
                Prefix = "RBAC_Helpdesk"
                Description = "Helpdesk - Kennwort zurücksetzen, Konto entsperren"
                Permissions = @("Reset-Password", "Unlock-Account", "Read-User")
                Tier = 2
            }
            "Server Operator" = @{
                Prefix = "RBAC_ServerOp"
                Description = "Server-Operator - Serververwaltung"
                Permissions = @("Manage-Server", "Remote-Desktop", "Event-Logs")
                Tier = 1
            }
            "Backup Operator" = @{
                Prefix = "RBAC_Backup"
                Description = "Sicherungs-Operator - Sicherung und Wiederherstellung"
                Permissions = @("Backup-Files", "Restore-Files", "Manage-VSS")
                Tier = 1
            }
            "Account Operator" = @{
                Prefix = "RBAC_AccountOp"
                Description = "Konten-Operator - Benutzer- und Gruppenverwaltung"
                Permissions = @("Create-User", "Modify-User", "Create-Group", "Modify-Group")
                Tier = 2
            }
            "Print Operator" = @{
                Prefix = "RBAC_PrintOp"
                Description = "Druck-Operator - Druckerverwaltung"
                Permissions = @("Manage-Printers", "Manage-Print-Queue", "Install-Drivers")
                Tier = 2
            }
        }

        $roleDefinition = $rbacDefinitions[$selectedRole.Content]

        # Erstelle Hierarchische RBAC-Struktur
        for ($i = 1; $i -le $roleCount; $i++) {
            try {
                # 1. Erstelle Haupt-RBAC-Gruppe
                $mainGroupName = "$($roleDefinition.Prefix)_$i"
                New-ADGroup -Name $mainGroupName `
                    -GroupScope DomainLocal `
                    -GroupCategory Security `
                    -Description "$($roleDefinition.Description) - Instanz $i" `
                    -Path $groupOU `
                    -OtherAttributes @{
                        'info' = "Tier: $($roleDefinition.Tier)`nBerechtigungen: $($roleDefinition.Permissions -join ', ')"
                    } `
                    -ErrorAction Stop

                $script:CreatedGroups.Add($mainGroupName)
                Write-AppLog "RBAC-Hauptgruppe '$mainGroupName' erstellt" -Level "SUCCESS"

                # 2. Erstelle Permissions-Untergruppen
                foreach ($permission in $roleDefinition.Permissions) {
                    $permGroupName = "$mainGroupName`_$($permission -replace '-', '')"

                    New-ADGroup -Name $permGroupName `
                        -GroupScope Global `
                        -GroupCategory Security `
                        -Description "Berechtigung: $permission für $mainGroupName" `
                        -Path $groupOU `
                        -ErrorAction Stop

                    # Füge Permission-Gruppe zur Haupt-RBAC-Gruppe hinzu
                    Add-ADGroupMember -Identity $mainGroupName -Members $permGroupName -ErrorAction Stop

                    $script:CreatedGroups.Add($permGroupName)
                    Write-AppLog "Permission-Gruppe '$permGroupName' erstellt und zugewiesen" -Level "DEBUG"
                }

                # 3. Erstelle Beispiel-Benutzer für diese Rolle
                if ($script:CreatedUsers.Count -gt 0) {
                    # Weise zufällige Benutzer der Rolle zu
                    $assignCount = [math]::Min(3, $script:CreatedUsers.Count)
                    $assignedUsers = $script:CreatedUsers | Get-Random -Count $assignCount

                    foreach ($user in $assignedUsers) {
                        try {
                            Add-ADGroupMember -Identity $mainGroupName -Members $user -ErrorAction Stop
                            Write-AppLog "Benutzer '$user' zu RBAC-Rolle '$mainGroupName' hinzugefügt" -Level "DEBUG"
                        } catch {
                            Write-AppLog "Fehler beim Zuweisen von '$user' zu '$mainGroupName': $($_.Exception.Message)" -Level "WARN"
                        }
                    }
                }

                $successCount++

            } catch {
                Write-AppLog "Fehler beim Erstellen von RBAC-Rolle: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }

            Write-GuiProgress -Current $i -Total $roleCount -Text "Erstelle RBAC-Rollen"
        }

        Hide-Progress
        Show-CreatedObjectCount

        # Erstelle Dokumentation
        $docPath = (Get-ExportFilePath -FileName "RBAC_Structure_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt")
        $documentation = @"
RBAC-Rollen Dokumentation
========================
Erstellt am: $(Get-Date)
Rolle: $($selectedRole.Content)
Anzahl: $roleCount

Struktur:
- Tier: $($roleDefinition.Tier)
- Berechtigungen: $($roleDefinition.Permissions -join ', ')

Erstellte Gruppen:
$($script:CreatedGroups | Where-Object { $_ -like "$($roleDefinition.Prefix)*" } | ForEach-Object { "- $_" } | Out-String)

Hinweise:
- DomainLocal Gruppen für Ressourcen-Zuweisung
- Global Gruppen für Berechtigungs-Gruppierung
- Benutzer können mehreren Rollen zugewiesen werden
"@

        $documentation | Out-File -FilePath $docPath -Encoding UTF8

        $message = @"
RBAC-Rollen erfolgreich erstellt:

Rolle: $($selectedRole.Content)
Erstellt: $successCount
Fehler: $errorCount

Die RBAC-Struktur wurde dokumentiert in:
$docPath
"@

        [System.Windows.MessageBox]::Show($message, "RBAC-Rollen erstellt", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei RBAC-Rollen-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Get-BitLockerRecoveryPassword {
    <#
    .SYNOPSIS
    Generiert ein BitLocker-kompatibles Recovery-Passwort
    #>
    # Echte Recovery-Passwörter bestehen aus 8 Blöcken (6 Ziffern), jeder Block ist durch 11 teilbar (< 720896)
    $blocks = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt 8; $i++) {
        $blocks.Add(('{0:D6}' -f ((Get-CryptoRandomInt -MaxExclusive 65536) * 11)))
    }
    return $blocks -join '-'
}

#endregion

#region Erweiterte Features - Implementierung

function Invoke-AdvancedFeature {
    <#
    .SYNOPSIS
    Führt erweiterte Features für Test-Umgebungen aus

    .DESCRIPTION
    Erstellt DNS-Einträge, Service Principal Names (SPNs) und dokumentiert FSMO-Rollen
    #>
    try {
        Write-AppLog "Starte Ausführung erweiterter Features..." -Level "INFO"

        $createDNS = $script:GuiControls.CheckBoxCreateDNSEntries.IsChecked
        $createSPNs = $script:GuiControls.CheckBoxCreateSPNs.IsChecked
        $documentFSMO = $script:GuiControls.CheckBoxDocumentFSMO.IsChecked

        if (-not ($createDNS -or $createSPNs -or $documentFSMO)) {
            Write-AppLog "Keine erweiterten Features ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein erweitertes Feature aus.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie folgende erweiterte Features ausführen?`n`n" +
            "$(if ($createDNS) { "- DNS-Einträge erstellen (simuliert)`n" })" +
            "$(if ($createSPNs) { "- Service Principal Names erstellen`n" })" +
            "$(if ($documentFSMO) { "- FSMO-Rollen dokumentieren`n" })" +
            "`nDies kann je nach Anzahl der Objekte einige Zeit dauern.",
            "Erweiterte Features",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Führe erweiterte Features aus..." -Value 0
        $successCount = 0
        $errorCount = 0
        $reportData = @()

        # 1. DNS-Einträge erstellen (simuliert)
        if ($createDNS -and $script:CreatedComputers.Count -gt 0) {
            Write-GuiProgress -Current 1 -Total 3 -Text "Erstelle DNS-Einträge..."

            $dnsFile = (Get-ExportFilePath -FileName "DNS_Entries_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
            $dnsEntries = @()
            $domain = (Get-CachedADDomain).DNSRoot
            $ipBase = "10.0.1."

            for ($i = 0; $i -lt $script:CreatedComputers.Count; $i++) {
                $computer = $script:CreatedComputers[$i]
                $ip = "$ipBase$(100 + $i)"

                # A-Record
                $dnsEntries += [PSCustomObject]@{
                    RecordType = "A"
                    Name = $computer
                    FQDN = "$computer.$domain"
                    Value = $ip
                    TTL = 3600
                    Zone = $domain
                }

                # PTR-Record
                $octets = $ip.Split('.')
                $ptrName = "$($octets[3]).$($octets[2]).$($octets[1]).$($octets[0]).in-addr.arpa"
                $dnsEntries += [PSCustomObject]@{
                    RecordType = "PTR"
                    Name = $ptrName
                    FQDN = $ptrName
                    Value = "$computer.$domain"
                    TTL = 3600
                    Zone = "$($octets[2]).$($octets[1]).$($octets[0]).in-addr.arpa"
                }

                Write-AppLog "DNS-Einträge für '$computer' erstellt (IP: $ip)" -Level "DEBUG"
                $successCount++
            }

            $dnsEntries | Export-Csv -Path $dnsFile -NoTypeInformation -Encoding UTF8
            $reportData += "DNS-Einträge: $dnsFile ($($dnsEntries.Count) Einträge)"
        }

        # 2. Service Principal Names erstellen
        if ($createSPNs -and $script:CreatedServiceAccounts.Count -gt 0) {
            Write-GuiProgress -Current 2 -Total 3 -Text "Erstelle Service Principal Names..."

            $spnFile = (Get-ExportFilePath -FileName "SPNs_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv")
            $spnData = New-Object System.Collections.Generic.List[object]
            $domain = (Get-CachedADDomain).DNSRoot

            foreach ($serviceAccount in $script:CreatedServiceAccounts) {
                try {
                    # Existenz des Dienstkontos prüfen (wirft bei gelöschtem Konto)
                    $null = Get-ADUser -Identity $serviceAccount -ErrorAction Stop

                    # Erstelle verschiedene SPNs basierend auf Dienst-Typ
                    # (Accounts heißen svc_sql_####, svc_iis_#### usw.; Hostname je Account eindeutig, damit keine doppelten SPNs entstehen)
                    $spns = New-Object System.Collections.Generic.List[string]
                    $hostLabel = $serviceAccount -replace '_', '-'

                    # SQL-Server-Dienstkonten
                    if ($serviceAccount -like "svc_sql*") {
                        $spns.Add("MSSQLSvc/$hostLabel.$domain")
                        $spns.Add("MSSQLSvc/$hostLabel.${domain}:1433")
                    }
                    # IIS-/Web-Dienstkonten
                    elseif ($serviceAccount -like "svc_iis*" -or $serviceAccount -like "svc_web*") {
                        $spns.Add("HTTP/$hostLabel.$domain")
                        $spns.Add("HTTP/$hostLabel.${domain}:80")
                        $spns.Add("HTTP/$hostLabel.${domain}:443")
                    }
                    # Sonstige Dienstkonten (generisch)
                    elseif ($serviceAccount -like "svc_*") {
                        $spns.Add("HOST/$hostLabel.$domain")
                    }
                    # Standard
                    else {
                        $spns.Add("HOST/$hostLabel.$domain")
                    }

                    # SPNs zum Account hinzufügen
                    foreach ($spn in $spns) {
                        try {
                            Set-ADUser -Identity $serviceAccount -Add @{servicePrincipalName=$spn} -ErrorAction Stop

                            $spnData.Add([PSCustomObject]@{
                                Account = $serviceAccount
                                SPN = $spn
                                Status = "Created"
                                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            })

                            Write-AppLog "SPN '$spn' zu Dienstkonto '$serviceAccount' hinzugefügt" -Level "DEBUG"
                        } catch {
                            $spnData.Add([PSCustomObject]@{
                                Account = $serviceAccount
                                SPN = $spn
                                Status = "Failed: $($_.Exception.Message)"
                                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            })
                            $errorCount++
                        }
                    }

                    $successCount++

                } catch {
                    Write-AppLog "Fehler bei SPN-Erstellung für '$serviceAccount': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }

            $spnData | Export-Csv -Path $spnFile -NoTypeInformation -Encoding UTF8
            $reportData += "SPNs: $spnFile ($($spnData.Count) SPNs)"
        }

        # 3. FSMO-Rollen dokumentieren
        if ($documentFSMO) {
            Write-GuiProgress -Current 3 -Total 3 -Text "Dokumentiere FSMO-Rollen..."

            $fsmoFile = (Get-ExportFilePath -FileName "FSMO_Documentation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt")

            try {
                $forest = Get-ADForest
                $domain = Get-ADDomain

                $fsmoDoc = @"
FSMO-Rollen Dokumentation
=========================
Erstellt am: $(Get-Date)

Forest-Level FSMO-Rollen:
- Schema Master: $($forest.SchemaMaster)
- Domain Naming Master: $($forest.DomainNamingMaster)

Domain-Level FSMO-Rollen:
- PDC Emulator: $($domain.PDCEmulator)
- RID Master: $($domain.RIDMaster)
- Infrastructure Master: $($domain.InfrastructureMaster)

Forest-Informationen:
- Name: $($forest.Name)
- Mode: $($forest.ForestMode)
- Domains: $($forest.Domains -join ', ')

Domain-Informationen:
- Name: $($domain.Name)
- NetBIOS: $($domain.NetBIOSName)
- Mode: $($domain.DomainMode)
"@

                $fsmoDoc | Out-File -FilePath $fsmoFile -Encoding UTF8
                $reportData += "FSMO-Dokumentation: $fsmoFile"
                $successCount++

            } catch {
                Write-AppLog "Fehler bei FSMO-Dokumentation: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }

        Hide-Progress

        $message = @"
Erweiterte Features abgeschlossen:

Erfolgreiche Operationen: $successCount
Fehler: $errorCount

Erstellte Berichte:
$(($reportData | ForEach-Object { "- $_" }) -join "`n")
"@

        [System.Windows.MessageBox]::Show($message, "Erweiterte Features", "OK", "Information")

    } catch {
        Hide-Progress
        Write-AppLog "Fehler bei erweiterten Features: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Ausführung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

#endregion

function Show-Progress {
    <#
    .SYNOPSIS
    Zeigt die Fortschrittsanzeige an
    #>
    param(
        [string]$Text = "Vorgang läuft...",
        [int]$Value = 0
    )

    try {
        Set-UiBusyState -Busy $true
        $script:GuiControls.GridProgressArea.Visibility = [System.Windows.Visibility]::Visible
        $script:GuiControls.LabelProgress.Content = $Text
        $script:GuiControls.ProgressBarMain.Value = $Value

        # UI aktualisieren (Dispatcher-Nachrichten verarbeiten, damit die GUI nicht einfriert)
        Invoke-UiRefresh
    } catch {
        Write-AppLog "Fehler beim Anzeigen des Fortschritts: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Hide-Progress {
    <#
    .SYNOPSIS
    Versteckt die Fortschrittsanzeige
    #>
    try {
        $script:GuiControls.GridProgressArea.Visibility = [System.Windows.Visibility]::Collapsed
        $script:GuiControls.ProgressBarMain.Value = 0
        Set-UiBusyState -Busy $false
    } catch {
        Write-AppLog "Fehler beim Verstecken des Fortschritts: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Write-GuiProgress {
    <#
    .SYNOPSIS
    Aktualisiert den Fortschrittsbalken
    #>
    param(
        [int]$Current,
        [int]$Total,
        [string]$Text = $null
    )

    try {
        if ($Total -le 0) { $Total = 1 }
        $percentage = [math]::Min(100, [math]::Round(($Current / $Total) * 100, 0))

        if ($Text) {
            Show-Progress -Text "$Text ($Current von $Total)" -Value $percentage
        } else {
            $script:GuiControls.ProgressBarMain.Value = $percentage
            Invoke-UiRefresh
        }
    } catch {
        Write-AppLog "Fehler beim Aktualisieren des Fortschritts: $($_.Exception.Message)" -Level "ERROR"
    }
}

#endregion

function Show-MainWindow {
    try {
        Initialize-Application
        Write-AppLog "Starte GUI..."
        $null = $script:Window.ShowDialog()
    } catch {
        Write-AppLog "Kritischer Fehler in der Anwendung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Ein kritischer Fehler ist aufgetreten:`n$($_.Exception.Message)", "Kritischer Fehler", "OK", "Error")
    } finally {
        Write-AppLog "Anwendung beendet."
    }
}

#endregion

# ============================================================================
# SCRIPT ENTRY POINT
# ============================================================================
Show-MainWindow

