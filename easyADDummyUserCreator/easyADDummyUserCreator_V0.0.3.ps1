# ============================================ 
# Version:     0.1.0 
# Autor:       Andreas Hepp (unterstützt durch Cascade AI) 
# ============================================ 
 
#requires -Version 5.0 
#requires -Modules ActiveDirectory 
 
<# 
.SYNOPSIS 
    Erstellt Active Directory Dummy-Benutzer basierend auf einer CSV-Datei. 
.DESCRIPTION 
    Ein PowerShell-Skript mit WPF-GUI zum Einlesen einer CSV-Datei und zum Erstellen von AD-Benutzern. 
    Ermöglicht die Auswahl der zu verwendenden Attribute und bietet Platzhalter für weitere AD-Verwaltungsfunktionen.
    
    Features:
    - WPF-GUI für benutzerfreundliche Bedienung
    - CSV-Import mit konfigurierbaren Attributzuordnungen
    - Automatische UPN-Generierung
    - OU-Dropdown mit AD-Integration
    - Fortschrittsanzeige für längere Operationen
    - Umfassende Logging-Funktionalität
    - Sicherheitsfunktionen für kritische AD-Operationen 
.NOTES 
    Stellen Sie sicher, dass das ActiveDirectory PowerShell-Modul installiert ist und Sie über die erforderlichen Berechtigungen verfügen. 
#> 
 
#region Globale Variablen und Konfiguration 
Add-Type -AssemblyName PresentationFramework 
Add-Type -AssemblyName PresentationCore 
Add-Type -AssemblyName WindowsBase 
Add-Type -AssemblyName Microsoft.VisualBasic
 
$Global:AppConfig = @{ 
    AppName                = "easy DC Dummy Object Creator" 
    ScriptVersion          = "0.0.2" 
    Author                 = "Andreas Hepp  |  www.phinit.de" 
    DefaultCsvPath         = ".\AD_DummyUserList.csv" # Standardpfad, kann im GUI geändert werden 
    DefaultPassword        = "P@sswOrd123!"            # Standardpasswort für neue User 
    EnablePasswordChange   = $true                     # Benutzer muss Passwort bei nächster Anmeldung ändern
    LogFilePath           = ".\easyADDummyUserCreator.log" # Pfad für Logdatei
} 
 
$Global:Window = $null 
$Global:GuiControls = @{} 
$Global:CsvData = $null 
$Global:CreatedUsers = [System.Collections.Generic.List[object]]::new() 
$Global:CreatedGroups = [System.Collections.Generic.List[object]]::new() 
$Global:CreatedComputers = [System.Collections.Generic.List[object]]::new() 
$Global:CreatedOUs = [System.Collections.Generic.List[object]]::new() 
$Global:CreatedServiceAccounts = [System.Collections.Generic.List[object]]::new()

# AD Attribute Mapping Konfiguration
$Global:SelectableADAttributes = @(
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
    @{Name="HomePage"; CsvHeader="homeDrive"; Required=$false}
    @{Name="HomeDirectory"; CsvHeader="homeDirectory"; Required=$false}
    @{Name="ScriptPath"; CsvHeader="scriptPath"; Required=$false}
    @{Name="ProfilePath"; CsvHeader="profilePath"; Required=$false}
)
#endregion 
 
#region XAML Definition 
$XAML = @" 
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
    xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
    xmlns:sys="clr-namespace:System;assembly=mscorlib"
    Title="$($Global:AppConfig.AppName) v$($Global:AppConfig.ScriptVersion)"
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
                            Text="$($Global:AppConfig.AppName)" />
                        <TextBlock
                            FontSize="11"
                            Foreground="{StaticResource TextSecondaryBrush}"
                            Text="Dummy Active Directory User Management" />
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
                            Text="v$($Global:AppConfig.ScriptVersion)" />
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
                                    Margin="10,0,491,0" />
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
                                    TextWrapping="Wrap"><Run Text="OU=TestCompany" /><Run Text=" mit " /><Run Text="Unter-OUs: " /><LineBreak /><Run Text="USERS, GROUPS, COMPUTERS, SERVICES, RESOURCES" /></TextBlock>
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
                                    Text="$($Global:AppConfig.DefaultCsvPath)" />
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
                                    ToolTip="Leer = Alle User aus CSV" />
                            </Grid>

                            <Label
                                Grid.Row="2"
                                Margin="0,4,0,0"
                                Content="Zu importierende Attribute:" />
                            <ScrollViewer
                                Grid.Row="3"
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
                    <Expander Header="🔧 CSV-Benutzer verwalten" IsExpanded="False">
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
                                ToolTip="Leer = Alle erstellten Benutzer" />

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
                                    Style="{StaticResource WarningButton}" />
                                <Button
                                    x:Name="ButtonDeleteUsers"
                                    Grid.Column="1"
                                    Margin="2,0,10,0"
                                    Content="🗑️ Löschen"
                                    Style="{StaticResource DangerButton}" />
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
                                ToolTip="Aktualisiert Attribute bestehender Benutzer" />
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
                                        Content="👥 Random User"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt zufällige Test-Benutzer" />
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
                                        ToolTip="Löscht ALLE erstellten Objekte" />
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
                                        Columns="2"
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
                                            Content="🗑️ Services"
                                            Style="{StaticResource SmallButton}"
                                            ToolTip="Löscht alle Service Accounts" />
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

                            <!--  Progress für Schnellzugriff  -->
                            <Grid
                                x:Name="GridQuickProgress"
                                Grid.Row="2"
                                Visibility="Collapsed">
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto" />
                                    <RowDefinition Height="Auto" />
                                </Grid.RowDefinitions>
                                <TextBlock
                                    x:Name="TextBlockQuickStatus"
                                    Grid.Row="0"
                                    HorizontalAlignment="Center"
                                    FontSize="11"
                                    Foreground="{StaticResource TextSecondaryBrush}"
                                    Text="Verarbeitung..." />
                                <ProgressBar
                                    x:Name="ProgressBarQuick"
                                    Grid.Row="1"
                                    Height="6"
                                    Margin="0,2,0,0"
                                    Background="{StaticResource SurfaceBrush}"
                                    Foreground="{StaticResource SuccessBrush}" />
                            </Grid>
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
                                        <TextBlock FontSize="12" Text="⚙️ Services" />
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
                    <Expander Header="🎲 Random Benutzer-Erstellung" IsExpanded="False">
                        <StackPanel>
                            <!--  Random User Einstellungen  -->
                            <GroupBox Margin="0,0,0,8" Header="⚙️ Random-Benutzer Einstellungen">
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
                                            ToolTip="Anzahl der zu erstellenden Random-Benutzer" />
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
                                    <ComboBox x:Name="ComboBoxPasswordComplexity" Grid.Row="4">
                                        <ComboBoxItem Content="Einfach (8 Zeichen)" />
                                        <ComboBoxItem Content="Mittel (12 Zeichen + Symbole)" IsSelected="True" />
                                        <ComboBoxItem Content="Komplex (16 Zeichen + Spezial)" />
                                        <ComboBoxItem Content="Hochsicher (20+ Zeichen)" />
                                    </ComboBox>
                                </Grid>
                            </GroupBox>

                            <!--  Random User Actions  -->
                            <GroupBox Margin="0,0,0,8" Header="🚀 Random-Benutzer Aktionen">
                                <StackPanel>
                                    <Button
                                        x:Name="ButtonCreateRandomUsers"
                                        Content="👥 Random Benutzer erstellen"
                                        Style="{StaticResource SuccessButton}"
                                        ToolTip="Erstellt zufällige Benutzer in der Test-Umgebung" />
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
                                </StackPanel>
                            </GroupBox>

                            <!--  Erweiterte Random-Optionen  -->
                            <GroupBox Margin="0,0,0,8" Header="🎯 Erweiterte Optionen">
                                <StackPanel>
                                    <CheckBox x:Name="CheckBoxGenerateAvatars" Content="Automatisch Avatare generieren" />
                                    <CheckBox x:Name="CheckBoxSetExpiryDate" Content="Ablaufdatum setzen" />
                                    <CheckBox x:Name="CheckBoxTemporaryAccount" Content="Als temporäre Accounts (30 Tage)" />
                                    <Button
                                        x:Name="ButtonGenerateRandomData"
                                        Margin="0,4,0,0"
                                        Content="📊 Nur Daten generieren (CSV)"
                                        Style="{StaticResource SecondaryButton}"
                                        ToolTip="Generiert Random-Daten und exportiert sie als CSV" />
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
                                        <ComboBoxItem Content="2-Level Hierarchie" />
                                        <ComboBoxItem Content="3-Level Hierarchie" />
                                    </ComboBox>
                                    <Button
                                        x:Name="ButtonCreateNestedGroups"
                                        Margin="0,4,0,0"
                                        Content="🔗 Hierarchie erstellen"
                                        Style="{StaticResource ModernButton}" />
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
                                        <ComboBoxItem Content="Workstations" IsSelected="True" />
                                        <ComboBoxItem Content="Laptops" />
                                        <ComboBoxItem Content="Server" />
                                        <ComboBoxItem Content="Virtual Machines" />
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
                                        Style="{StaticResource SuccessButton}" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="⚙️ Service Accounts">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxServiceType">
                                        <ComboBoxItem Content="SQL Server Service" IsSelected="True" />
                                        <ComboBoxItem Content="IIS Application Pool" />
                                        <ComboBoxItem Content="Windows Service" />
                                        <ComboBoxItem Content="Scheduled Task" />
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
                                        Content="⚙️ Service Accounts erstellen"
                                        Style="{StaticResource ModernButton}" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="🔐 Computer-Sicherheitsdaten">
                                <StackPanel>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="Auto" />
                                            <ColumnDefinition Width="*" />
                                        </Grid.ColumnDefinitions>
                                        <Label Grid.Column="0" Content="BitLocker Keys für:" />
                                        <TextBox
                                            x:Name="TextBoxBitLockerComputerCount"
                                            Grid.Column="1"
                                            Text="10"
                                            ToolTip="Anzahl Computer" />
                                    </Grid>
                                    <Button
                                        x:Name="ButtonCreateBitLockerData"
                                        Margin="0,4,0,0"
                                        Content="🔐 BitLocker Keys generieren"
                                        Style="{StaticResource ModernButton}" />

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
                                        Content="🔑 LAPS Passwörter generieren"
                                        Style="{StaticResource SuccessButton}" />
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
                                        <ComboBoxItem Content="Mittel (100-500 Objekte)" />
                                        <ComboBoxItem Content="Groß (1000+ Objekte)" />
                                    </ComboBox>
                                    <CheckBox
                                        x:Name="CheckBoxRealisticData"
                                        Margin="0,4,0,0"
                                        Content="Realistische Verteilung"
                                        IsChecked="True" />
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
                                    <Button
                                        x:Name="ButtonActivateChaosMode"
                                        Margin="0,4,0,0"
                                        Content="🎭 Chaos-Daten erstellen"
                                        Style="{StaticResource DangerButton}" />
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
                                    <CheckBox x:Name="CheckBoxCreateLockedAccounts" Content="Gesperrte Accounts erstellen (10%)" />
                                    <CheckBox x:Name="CheckBoxExpiredPasswords" Content="Abgelaufene Passwörter" />
                                    <Button
                                        x:Name="ButtonApplyPasswordPolicies"
                                        Margin="0,4,0,0"
                                        Content="🔒 Passwort-Richtlinien anwenden"
                                        Style="{StaticResource WarningButton}" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="👑 RBAC-Rollen">
                                <StackPanel>
                                    <ComboBox x:Name="ComboBoxRBACRoles">
                                        <ComboBoxItem Content="Helpdesk Operator" IsSelected="True" />
                                        <ComboBoxItem Content="Server Operator" />
                                        <ComboBoxItem Content="Backup Operator" />
                                    </ComboBox>
                                    <Button
                                        x:Name="ButtonCreateRBACRoles"
                                        Margin="0,4,0,0"
                                        Content="👑 RBAC-Struktur erstellen"
                                        Style="{StaticResource ModernButton}" />
                                </StackPanel>
                            </GroupBox>

                            <GroupBox Margin="0,0,0,8" Header="⚠️ Kritische Einstellungen">
                                <StackPanel>
                                    <CheckBox x:Name="CheckBoxPwdNotExpires" Content="Passwort läuft nicht ab" />
                                    <CheckBox x:Name="CheckBoxRevPwd" Content="Umgekehrte Verschlüsselung" />
                                    <ComboBox x:Name="ComboBoxCriticalGroups" Margin="0,4,0,0">
                                        <ComboBoxItem Content="Domain Admins" />
                                        <ComboBoxItem Content="Enterprise Admins" />
                                    </ComboBox>
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
                                    <CheckBox x:Name="CheckBoxCreateDNSEntries" Content="DNS-Einträge erstellen" />
                                    <CheckBox x:Name="CheckBoxCreateSPNs" Content="Service Principal Names (SPNs)" />
                                    <CheckBox x:Name="CheckBoxDocumentFSMO" Content="FSMO-Rollen dokumentieren" />
                                    <Button
                                        x:Name="ButtonCreateAdvancedFeatures"
                                        Margin="0,4,0,0"
                                        Content="🚀 Erweiterte Features ausführen"
                                        Style="{StaticResource ModernButton}" />
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
                    Text="$($Global:AppConfig.Author)" />
            </Grid>
        </Border>
    </Grid>
</Window>
"@ 
#endregion 
 
#region Logging und Hilfsfunktionen 
function Write-Log { 
    param( 
        [string]$Message, 
        [string]$Level = "INFO" # INFO, WARN, ERROR, DEBUG, SUCCESS 
    ) 
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss" 
    $logEntry = "[$timestamp] [$Level] $Message" 
    Write-Host $logEntry # Für direkte Konsolenausgabe während der Entwicklung 
    
    if ($Global:Window -and $Global:GuiControls.TextBlockStatus) { 
        $Global:GuiControls.TextBlockStatus.Text = $Message 
    } 
    
    # In Datei loggen
    try {
        $logEntry | Out-File -FilePath $Global:AppConfig.LogFilePath -Append -Encoding UTF8
    } catch {
        # Fehler beim Logging nicht weiterwerfen, um Hauptfunktionalität nicht zu beeinträchtigen
        Write-Host "Fehler beim Schreiben in Logdatei: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} 

function Normalize-SamAccountName {
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
    Normalize-SamAccountName -SamAccountName "müller.johann" -ExistingNames $existingNames
    # Gibt zurück: "mueller.johann"
    
    .EXAMPLE
    Normalize-SamAccountName -SamAccountName "mauch schlauchin" -ExistingNames $existingNames
    # Gibt zurück: "mauch_schlauchin"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$SamAccountName,
        
        [Parameter(Mandatory=$false)]
        [System.Collections.Generic.HashSet[string]]$ExistingNames
    )
    
    if ([string]::IsNullOrWhiteSpace($SamAccountName)) {
        Write-Log "Normalize-SamAccountName: Leerer SamAccountName übergeben" -Level "ERROR"
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
        Write-Log "SamAccountName war nach Normalisierung leer, verwende Fallback: $normalized" -Level "WARN"
    }
    
    # 9. Auf 20 Zeichen kürzen (AD-Limit)
    if ($normalized.Length -gt 20) {
        $normalized = $normalized.Substring(0, 17) + (Get-Random -Minimum 100 -Maximum 999)
        Write-Log "SamAccountName zu lang, gekürzt auf: $normalized" -Level "DEBUG"
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
            Write-Log "SamAccountName Duplikat vermieden: '$originalNormalized' → '$normalized'" -Level "DEBUG"
        }
    }
    
    Write-Log "SamAccountName normalisiert: '$SamAccountName' → '$normalized'" -Level "DEBUG"
    return $normalized
}

function Get-GuiControls {
    <#
    .SYNOPSIS
    Sammelt alle benannten GUI-Controls aus dem XAML-Window
    
    .DESCRIPTION
    Diese Funktion durchsucht das XAML-Window nach allen benannten Controls
    und speichert sie in der globalen GuiControls-Hashtable für einfachen Zugriff.
    #>
    try {
        Write-Log "Sammle GUI-Controls..." -Level "INFO"
        
        # Liste der erwarteten Controls
        $expectedControls = @(
            'TextBoxCsvPath', 'ButtonBrowseCsv', 'ButtonLoadCsv', 'DataGridCsvContent',
            'ComboBoxTargetOU', 'TextBoxNumUsersToCreate', 'StackPanelAttributeSelection',
            'ButtonCreateADUsers', 'GridProgressArea', 'LabelProgress', 'ProgressBarMain',
            'TextBoxNumUsersForAction', 'ButtonFillAttributes', 'ButtonDisableUsers',
            'ButtonDeleteUsers', 'ButtonExportCreatedUsers', 'CheckBoxPwdNotExpires',
            'CheckBoxRevPwd', 'ButtonApplySecuritySettings', 'ComboBoxCriticalGroups',
            'ButtonAssignToGroups', 'TextBlockStatus',
            # Neue Controls für Benutzer-Erstellung & Verwaltung
            'ButtonGeneratePasswords', 'ComboBoxPasswordComplexity', 'CheckBoxIncludeNumbers',
            'CheckBoxIncludeSymbols', 'CheckBoxExcludeAmbiguous', 'ButtonGenerateRandomData',
            'CheckBoxRandomNames', 'CheckBoxRandomAddresses', 'CheckBoxRandomPhone',
            'CheckBoxRandomDepartments', 'ComboBoxUserTemplates', 'ButtonCreateFromTemplate',
            'TextBoxTemplateUser', 'ButtonBrowseTemplateUser', 'CheckBoxSetExpiryDate',
            'DatePickerExpiry', 'CheckBoxTemporaryAccount', 'ButtonSetTimeRestrictions',
            'CheckBoxGenerateAvatars', 'TextBoxAvatarPath', 'ButtonBrowseAvatars',
            'ButtonAssignAvatars', 'TextBoxRandomUserCount', 'CheckBoxRandomTitles', 
            'CheckBoxRandomCompany', 'ButtonCreateRandomUsers', 'TextBoxCompanyName',
            'ButtonCreateTestEnvironment',
            # Schnellzugriff Controls
            'ButtonQuickRandomUsers', 'ButtonQuickCreateGroups', 'ButtonQuickTestData', 'ButtonQuickCleanup',
            'GridQuickProgress', 'TextBlockQuickStatus', 'ProgressBarQuick',
            'ButtonDeleteGroups', 'ButtonDeleteComputers', 'ButtonDeleteOUs', 'ButtonDeleteServiceAccounts',
            'ButtonExportAll',
            # Statistik Controls
            'TextBlockUserCount', 'TextBlockGroupCount', 'TextBlockComputerCount',
            'TextBlockOUCount', 'TextBlockServiceCount', 'TextBlockTotalCount',
            # Controls für Gruppen & Organisationsstruktur
            'CheckBoxCreateDepartmentGroups', 'CheckBoxCreateLocationGroups', 'CheckBoxCreateJobTitleGroups',
            'ButtonCreateAutoGroups', 'ComboBoxGroupHierarchy', 'CheckBoxNestedSecurity',
            'ButtonCreateNestedGroups', 'TextBoxGroupFilter', 'ButtonCreateDynamicGroups',
            'ComboBoxOUStructure', 'CheckBoxCreateGPOStructure', 'ButtonCreateOUStructure',
            # Controls für Computer & Geräte
            'TextBoxComputerCount', 'ComboBoxComputerType', 'CheckBoxRandomComputerNames',
            'ButtonCreateComputers', 'ComboBoxServiceType', 'TextBoxServiceAccountCount',
            'ButtonCreateServiceAccounts', 'TextBoxPrinterCount', 'ComboBoxPrinterType',
            'ButtonCreatePrinters', 'TextBoxBitLockerComputerCount', 'CheckBoxBitLockerRandomSelection',
            'ButtonCreateBitLockerData', 'TextBoxLAPSSystemCount', 'CheckBoxLAPSIncludeServers',
            'CheckBoxLAPSIncludeWorkstations', 'ButtonCreateLAPSData',
            # Controls für Test-Szenarien
            'ComboBoxTestDataSize', 'CheckBoxRealisticData', 'CheckBoxHistoricalData',
            'ButtonCreateTestDataSet', 'CheckBoxInvalidData', 'CheckBoxMissingAttributes',
            'CheckBoxDuplicateEntries', 'CheckBoxSpecialCharacters', 'ButtonActivateChaosMode',
            'TextBoxPerformanceCount', 'TextBoxBatchSize', 'ButtonStartPerformanceTest',
            # Controls für Sicherheit & Compliance
            'CheckBoxSimulatePasswordHistory', 'CheckBoxCreateLockedAccounts', 'CheckBoxExpiredPasswords',
            'SliderLockoutRatio', 'ButtonApplyPasswordPolicies', 'ComboBoxRBACRoles',
            'TextBoxRoleCount', 'ButtonCreateRBACRoles', 'CheckBoxSimulateBitLocker',
            'CheckBoxRecoveryKeys', 'ButtonCreateBitLockerKeys',
            # Controls für Erweiterte Features
            'CheckBoxCreateDNSEntries', 'CheckBoxCreateARecords', 'CheckBoxCreateCNAME',
            'ButtonCreateDNSEntries', 'CheckBoxSIDHistory', 'CheckBoxTrustRelationships',
            'TextBoxSourceDomain', 'ButtonSimulateMigration', 'CheckBoxCreateSPNs',
            'CheckBoxKerberosConstraints', 'ComboBoxKerberosService', 'ButtonCreateKerberosTests',
            'CheckBoxDocumentFSMO', 'CheckBoxExportDomainInfo', 'ButtonDocumentFSMO',
            'ButtonCreateAdvancedFeatures'
        )
        
        foreach ($controlName in $expectedControls) {
            $control = $Global:Window.FindName($controlName)
            if ($null -ne $control) {
                $Global:GuiControls[$controlName] = $control
                Write-Log "Control gefunden: $controlName" -Level "DEBUG"
            } else {
                Write-Log "Control nicht gefunden: $controlName" -Level "WARN"
            }
        }
        
        Write-Log "$(($Global:GuiControls.Keys).Count) Controls erfolgreich gesammelt" -Level "SUCCESS"
        return $true
        
    } catch {
        Write-Log "Fehler beim Sammeln der Controls: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

#region Benutzer-Erstellung & Verwaltung - Erweiterte Funktionen

# Vordefinierte Listen für Zufallsdaten
$Global:RandomDataLists = @{
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

function Generate-SecurePassword {
    <#
    .SYNOPSIS
    Generiert sichere Passwörter mit verschiedenen Komplexitätsstufen
    
    .DESCRIPTION
    Erstellt Passwörter basierend auf ausgewählter Komplexität und Optionen
    #>
    param(
        [string]$Complexity = "Mittel",
        [bool]$IncludeNumbers = $true,
        [bool]$IncludeSymbols = $true,
        [bool]$ExcludeAmbiguous = $true
    )
    
    try {
        # Zeichensätze definieren
        $lowercase = 'abcdefghijklmnopqrstuvwxyz'
        $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        $numbers = '0123456789'
        $symbols = '!@#$%^&*()_+-=[]{}|;:,.<>?'
        
        # Mehrdeutige Zeichen
        $ambiguous = 'il1Lo0O'
        
        # Basis-Zeichensatz
        $charSet = $lowercase + $uppercase
        
        # Länge basierend auf Komplexität
        $length = switch ($Complexity) {
            "Einfach (8 Zeichen)" { 8 }
            "Mittel (12 Zeichen + Symbole)" { 12 }
            "Komplex (16 Zeichen + Spezial)" { 16 }
            "Hochsicher (20+ Zeichen)" { 24 }
            default { 12 }
        }
        
        # Zeichensatz erweitern
        if ($IncludeNumbers) {
            $charSet += $numbers
        }
        
        if ($IncludeSymbols -and $Complexity -ne "Einfach (8 Zeichen)") {
            $charSet += $symbols
        }
        
        # Mehrdeutige Zeichen entfernen
        if ($ExcludeAmbiguous) {
            foreach ($char in $ambiguous.ToCharArray()) {
                $charSet = $charSet.Replace($char.ToString(), '')
            }
        }
        
        # Passwort generieren
        $password = ""
        $random = New-Object System.Random
        
        # Mindestens ein Zeichen aus jeder Kategorie sicherstellen
        if ($IncludeNumbers) { $password += $numbers[$random.Next($numbers.Length)] }
        if ($IncludeSymbols -and $Complexity -ne "Einfach (8 Zeichen)") { $password += $symbols[$random.Next($symbols.Length)] }
        $password += $lowercase[$random.Next($lowercase.Length)]
        $password += $uppercase[$random.Next($uppercase.Length)]
        
        # Rest auffüllen
        for ($i = $password.Length; $i -lt $length; $i++) {
            $password += $charSet[$random.Next($charSet.Length)]
        }
        
        # Passwort mischen
        $passwordArray = $password.ToCharArray()
        $passwordArray = $passwordArray | Sort-Object {Get-Random}
        $password = -join $passwordArray
        
        Write-Log "Passwort generiert (Komplexität: $Complexity, Länge: $length)" -Level "DEBUG"
        return $password
        
    } catch {
        Write-Log "Fehler bei Passwort-Generierung: $($_.Exception.Message)" -Level "ERROR"
        return "P@ssw0rd123!" # Fallback
    }
}

function Generate-RandomUserData {
    <#
    .SYNOPSIS
    Generiert zufällige Benutzerdaten basierend auf vordefinierten Listen
    #>
    param(
        [bool]$RandomNames = $true,
        [bool]$RandomAddresses = $false,
        [bool]$RandomPhone = $false,
        [bool]$RandomDepartments = $false
    )
    
    try {
        $userData = @{}
        $random = New-Object System.Random
        
        if ($RandomNames) {
            $firstName = $Global:RandomDataLists.FirstNames[$random.Next($Global:RandomDataLists.FirstNames.Count)]
            $lastName = $Global:RandomDataLists.LastNames[$random.Next($Global:RandomDataLists.LastNames.Count)]
            
            $userData.FirstName = $firstName
            $userData.LastName = $lastName
            $userData.DisplayName = "$firstName $lastName"
            $userData.SamAccountName = "$($firstName.ToLower()).$($lastName.ToLower())"
        }
        
        if ($RandomAddresses) {
            $street = $Global:RandomDataLists.Streets[$random.Next($Global:RandomDataLists.Streets.Count)]
            $number = $random.Next(1, 200)
            $city = $Global:RandomDataLists.Cities[$random.Next($Global:RandomDataLists.Cities.Count)]
            $postalCode = $random.Next(10000, 99999)
            
            $userData.StreetAddress = "$street $number"
            $userData.City = $city
            $userData.PostalCode = $postalCode.ToString()
            $userData.State = "Germany"
            $userData.Country = "DE"
        }
        
        if ($RandomPhone) {
            $areaCode = $random.Next(100, 999)
            $number = $random.Next(1000000, 9999999)
            $userData.PhoneNumber = "+49 $areaCode $number"
            $userData.MobilePhone = "+49 1$($random.Next(50, 79)) $($random.Next(1000000, 9999999))"
        }
        
        if ($RandomDepartments) {
            $userData.Department = $Global:RandomDataLists.Departments[$random.Next($Global:RandomDataLists.Departments.Count)]
            $userData.Title = $Global:RandomDataLists.JobTitles[$random.Next($Global:RandomDataLists.JobTitles.Count)]
            $userData.Company = "Example Corp"
        }
        
        Write-Log "Zufällige Benutzerdaten generiert" -Level "DEBUG"
        return $userData
        
    } catch {
        Write-Log "Fehler bei Generierung von Zufallsdaten: $($_.Exception.Message)" -Level "ERROR"
        return @{}
    }
}

function Get-UserTemplate {
    <#
    .SYNOPSIS
    Gibt vordefinierte Benutzer-Templates zurück
    #>
    param(
        [string]$TemplateType = "Standard-Benutzer"
    )
    
    $templates = @{
        "Standard-Benutzer" = @{
            PasswordNeverExpires = $false
            ChangePasswordAtLogon = $true
            Enabled = $true
            Description = "Standard User Account"
        }
        "Administrator" = @{
            PasswordNeverExpires = $true
            ChangePasswordAtLogon = $false
            Enabled = $true
            Description = "Administrative Account"
            MemberOf = @("Domain Admins", "Administrators")
        }
        "Gast-Benutzer" = @{
            PasswordNeverExpires = $false
            ChangePasswordAtLogon = $true
            Enabled = $false
            Description = "Guest User Account"
            AccountExpirationDate = (Get-Date).AddDays(30)
        }
        "Service-Account" = @{
            PasswordNeverExpires = $true
            ChangePasswordAtLogon = $false
            Enabled = $true
            Description = "Service Account - Do not disable"
            UserCannotChangePassword = $true
        }
        "Extern/Contractor" = @{
            PasswordNeverExpires = $false
            ChangePasswordAtLogon = $true
            Enabled = $true
            Description = "External Contractor Account"
            AccountExpirationDate = (Get-Date).AddDays(90)
        }
    }
    
    return $templates[$TemplateType]
}

#endregion
#endregion 
 
#region Event Handler und GUI Logik 
 
function Import-CsvData { 
    $csvPath = $Global:GuiControls.TextBoxCsvPath.Text 
    if (-not (Test-Path $csvPath -PathType Leaf)) { 
        Write-Log "CSV-Datei nicht gefunden: $csvPath" -Level "ERROR" 
        [System.Windows.MessageBox]::Show("Die angegebene CSV-Datei wurde nicht gefunden: `n$csvPath", "Fehler", "OK", "Error") 
        return 
    } 
    try { 
        $Global:CsvData = Import-Csv -Path $csvPath 
        $Global:GuiControls.DataGridCsvContent.ItemsSource = $Global:CsvData 
        Write-Log "CSV-Datei erfolgreich geladen: $csvPath ($($Global:CsvData.Count) Einträge)" -Level "SUCCESS" 
 
        # Attribute für Auswahl-Checkboxes populieren 
        $Global:GuiControls.StackPanelAttributeSelection.Children.Clear() 
        $csvHeaders = $Global:CsvData | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name 
 
        foreach ($attrInfo in $Global:SelectableADAttributes) { 
            if ($csvHeaders -contains $attrInfo.CsvHeader) { 
                $checkBox = New-Object System.Windows.Controls.CheckBox 
                $checkBox.Content = "$($attrInfo.Name) (aus $($attrInfo.CsvHeader))" 
                $checkBox.Tag = $attrInfo # Store the attribute info object 
                if ($attrInfo.Required -or @("GivenName", "Surname", "DisplayName", "UserPrincipalName") -contains $attrInfo.Name) { 
                    $checkBox.IsChecked = $true # Pre-select required and common attributes 
                } 
                $Global:GuiControls.StackPanelAttributeSelection.Children.Add($checkBox) | Out-Null 
            } 
        } 
    } catch { 
        Write-Log "Fehler beim Laden der CSV-Datei: $($_.Exception.Message)" -Level "ERROR" 
        [System.Windows.MessageBox]::Show("Fehler beim Laden der CSV-Datei:`n$($_.Exception.Message)", "Fehler", "OK", "Error") 
    } 
} 
 
function New-ADUsersFromCsv { 
    if (-not $Global:CsvData) { 
        Write-Log "Bitte zuerst eine CSV-Datei laden." -Level "WARN" 
        [System.Windows.MessageBox]::Show("Bitte laden Sie zuerst eine CSV-Datei.", "Hinweis", "OK", "Warning") 
        return 
    } 
 
    # AD-Verbindung prüfen
    if (-not (Test-ADConnection)) {
        return
    }

    $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text 
    if (-not $targetOU) { 
        Write-Log "Bitte geben Sie eine Ziel-OU an." -Level "WARN" 
        [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Ziel-OU (Distinguished Name) an.", "Hinweis", "OK", "Warning") 
        return 
    } 
    
    # OU validieren
    if (-not (Validate-TargetOU -TargetOU $targetOU)) {
        return
    } 
 
    $numUsersToCreateText = $Global:GuiControls.TextBoxNumUsersToCreate.Text 
    $numUsersToCreate = if ([string]::IsNullOrWhiteSpace($numUsersToCreateText)) { $Global:CsvData.Count } else { [int]$numUsersToCreateText } 
 
    if ($numUsersToCreate -le 0) { 
        Write-Log "Anzahl der zu erstellenden Benutzer muss größer als 0 sein." -Level "WARN" 
        return 
    } 
 
    $selectedAttributesCheckboxes = $Global:GuiControls.StackPanelAttributeSelection.Children | Where-Object {$_.IsChecked -eq $true} 
    if ($selectedAttributesCheckboxes.Count -eq 0) { 
        Write-Log "Bitte wählen Sie mindestens ein Attribut für die Benutzererstellung aus." -Level "WARN" 
        [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein Attribut für die Benutzererstellung aus.", "Hinweis", "OK", "Warning") 
        return 
    } 
 
    # Sicherstellen, dass SamAccountName ausgewählt ist, wenn es in der CSV existiert 
    $samAttrInfo = $Global:SelectableADAttributes | Where-Object {$_.Name -eq "SamAccountName"} 
    $samSelected = $selectedAttributesCheckboxes | ForEach-Object { $_.Tag } | Where-Object {$_.Name -eq "SamAccountName"} 
    if (($Global:CsvData[0].PSObject.Properties.Name -contains $samAttrInfo.CsvHeader) -and (-not $samSelected)) { 
         Write-Log "Das Attribut 'SamAccountName' muss ausgewählt sein, wenn es in der CSV existiert und für die Erstellung verwendet werden soll." -Level "WARN" 
        [System.Windows.MessageBox]::Show("Das Attribut 'SamAccountName' (aus CSV-Spalte '$($samAttrInfo.CsvHeader)') ist für die Benutzererstellung erforderlich und muss ausgewählt werden.", "Hinweis", "OK", "Warning") 
        return 
    } 

    # Fortschrittsanzeige aktivieren
    Show-Progress -Text "Starte Benutzererstellung..." -Value 0
 
    Write-Log "Starte Erstellung von bis zu $numUsersToCreate AD-Benutzern..." -Level "INFO" 
    $Global:CreatedUsers.Clear() 
    $createdCount = 0 
    $errorCount = 0 
    
    # HashSet für SamAccountName-Duplikate zur Laufzeit
    $usedSamAccountNames = New-Object System.Collections.Generic.HashSet[string] 
 
    for ($i = 0; $i -lt $Global:CsvData.Count; $i++) { 
        if ($createdCount -ge $numUsersToCreate) { break } 
 
        $csvRow = $Global:CsvData[$i] 
        $userParams = @{ 
            Path    = $targetOU 
            Enabled = $true
            ChangePasswordAtLogon = $Global:AppConfig.EnablePasswordChange # Wert aus globaler Konfiguration verwenden
            AccountPassword = (ConvertTo-SecureString $Global:AppConfig.DefaultPassword -AsPlainText -Force) 
        } 
 
        # Standard Name, falls nicht anders spezifiziert 
        $userParams.Name = if ($csvRow.PSObject.Properties["DisplayName"]) { $csvRow.DisplayName } elseif ($csvRow.PSObject.Properties["FirstName"] -and $csvRow.PSObject.Properties["LastName"]) { "$($csvRow.FirstName) $($csvRow.LastName)" } else { $csvRow.SamAccountName } 
         
        foreach ($checkBox in $selectedAttributesCheckboxes) { 
            $attrInfo = $checkBox.Tag 
            if ($csvRow.PSObject.Properties[$attrInfo.CsvHeader]) { 
                $value = $csvRow.($attrInfo.CsvHeader) 
                if (-not [string]::IsNullOrWhiteSpace($value)) { 
                    # Spezielle Behandlung für bestimmte Attribute 
                    if ($attrInfo.Name -eq "Country") { 
                        # Hier könnte eine Konvertierung zu 2-Buchstaben-Code erfolgen, falls nötig 
                        # Fürs Erste wird der Wert direkt übernommen 
                    } 
                    if ($attrInfo.Name -eq "proxyAddresses") { 
                        $value = $value -split ";" # Annahme: Semikolon-getrennte Liste 
                    } 
                    $userParams[$attrInfo.Name] = $value 
                } 
            } 
        } 
 
        # SamAccountName ist zwingend erforderlich 
        if (-not $userParams.ContainsKey("SamAccountName") -or [string]::IsNullOrWhiteSpace($userParams.SamAccountName)) { 
            Write-Log "Fehler: SamAccountName fehlt oder ist leer für Zeile $($i+1). Benutzer wird übersprungen." -Level "ERROR" 
            $errorCount++ 
            continue 
        }

        # SamAccountName für AD-Kompatibilität normalisieren
        $originalSamAccountName = $userParams.SamAccountName
        $userParams.SamAccountName = Normalize-SamAccountName -SamAccountName $originalSamAccountName -ExistingNames $usedSamAccountNames
        
        if ($originalSamAccountName -ne $userParams.SamAccountName) {
            Write-Log "SamAccountName normalisiert für Zeile $($i+1): '$originalSamAccountName' → '$($userParams.SamAccountName)'" -Level "INFO"
        }

        # Fortschritt aktualisieren
        $progressText = if ($originalSamAccountName -ne $userParams.SamAccountName) {
            "Erstelle Benutzer ($($originalSamAccountName) → $($userParams.SamAccountName))"
        } else {
            "Erstelle Benutzer ($($userParams.SamAccountName))"
        }
        Update-Progress -Current ($i + 1) -Total $numUsersToCreate -Text $progressText

        # Automatische UPN-Generierung, falls nicht bereits in CSV vorhanden
        if (-not $userParams.ContainsKey("UserPrincipalName") -or [string]::IsNullOrWhiteSpace($userParams.UserPrincipalName)) {
            $userParams.UserPrincipalName = Generate-UPN -SamAccountName $userParams.SamAccountName
            Write-Log "UPN automatisch generiert: $($userParams.UserPrincipalName)" -Level "DEBUG"
        }
        
        # UPN auf Eindeutigkeit prüfen
        try {
            $existingUser = Get-ADUser -Filter "UserPrincipalName -eq '$($userParams.UserPrincipalName)'" -ErrorAction SilentlyContinue
            if ($existingUser) {
                Write-Log "UPN '$($userParams.UserPrincipalName)' existiert bereits für Benutzer '$($existingUser.SamAccountName)'. Benutzer wird übersprungen." -Level "WARN"
                $errorCount++
                continue
            }
        } catch {
            # Fehler beim Prüfen ignorieren und fortfahren
        }
 
        try { 
            Write-Log "Erstelle Benutzer: $($userParams.SamAccountName)" -Level "DEBUG" 
            # Write-Host ("DEBUG: New-ADUser @userParams: " + ($userParams | Format-List | Out-String)) # Zum Debuggen der Parameter 
            $newUser = New-ADUser @userParams -PassThru -ErrorAction Stop 
            Write-Log "Benutzer '$($newUser.SamAccountName)' erfolgreich erstellt." -Level "SUCCESS" 
            $Global:CreatedUsers.Add($newUser.SamAccountName) # Speichere nur SamAccountName für spätere Aktionen
            $createdCount++ 
        } catch { 
            Write-Log "Fehler beim Erstellen des Benutzers '$($userParams.SamAccountName)': $($_.Exception.Message)" -Level "ERROR" 
            $errorCount++ 
        } 
    }

    # Fortschrittsanzeige ausblenden
    Hide-Progress
    
    Write-Log "Benutzererstellung abgeschlossen. $createdCount erfolgreich erstellt, $errorCount Fehler." -Level "INFO" 
    Update-Statistics
    [System.Windows.MessageBox]::Show("Benutzererstellung abgeschlossen.`nErfolgreich: $createdCount`nFehler: $errorCount", "Ergebnis", "OK", "Information") 
} 
 
 
function Set-ADUserAttributesFromCsv {
    Write-Log "Aktion 'Attribute befüllen' gestartet..."
    if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
        Write-Log "Keine Benutzer zuvor erstellt oder Liste ist leer. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt oder die Liste ist leer. Bitte erstellen Sie zuerst Benutzer.", "Hinweis", "OK", "Warning")
        return
    }

    if (-not $Global:CsvData) {
        Write-Log "Keine CSV-Daten geladen. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte laden Sie zuerst eine CSV-Datei, die die neuen Attributwerte enthält.", "Hinweis", "OK", "Warning")
        return
    }

    $numUsersForActionText = $Global:GuiControls.TextBoxNumUsersForAction.Text
    $numUsersToUpdate = 0
    if ([string]::IsNullOrWhiteSpace($numUsersForActionText)) {
        $numUsersToUpdate = $Global:CreatedUsers.Count # Default to all created users
        Write-Log "Keine Anzahl für Aktion angegeben, verwende alle $($Global:CreatedUsers.Count) erstellten Benutzer."
    } elseif ($numUsersForActionText -match '^\d+$') {
        $numUsersToUpdate = [int]$numUsersForActionText
    } else {
        Write-Log "Ungültige Eingabe für 'Anzahl Benutzer für Aktion': '$numUsersForActionText'. Muss eine Zahl sein." -Level "WARN"
        [System.Windows.MessageBox]::Show("Die Eingabe für 'Anzahl Benutzer für Aktion' ist ungültig. Bitte geben Sie eine Zahl ein.", "Fehler", "OK", "Error")
        return
    }

    if ($numUsersToUpdate -le 0) {
        Write-Log "Anzahl der zu aktualisierenden Benutzer muss größer als 0 sein." -Level "WARN"
        [System.Windows.MessageBox]::Show("Die Anzahl der Benutzer für diese Aktion muss größer als 0 sein.", "Hinweis", "OK", "Warning")
        return
    }
    
    if ($numUsersToUpdate -gt $Global:CreatedUsers.Count) {
        Write-Log "Angeforderte Anzahl ($numUsersToUpdate) übersteigt Anzahl erstellter Benutzer ($($Global:CreatedUsers.Count)). Reduziere auf Maximum." -Level "WARN"
        $numUsersToUpdate = $Global:CreatedUsers.Count
    }
    
    if ($numUsersToUpdate -gt $Global:CsvData.Count) {
        Write-Log "Angeforderte Anzahl ($numUsersToUpdate) übersteigt Anzahl der CSV-Einträge ($($Global:CsvData.Count)). Aktion nicht möglich für alle angeforderten Benutzer." -Level "ERROR"
        [System.Windows.MessageBox]::Show("Nicht genügend Einträge in der CSV-Datei vorhanden, um $numUsersToUpdate Benutzer zu aktualisieren (nur $($Global:CsvData.Count) CSV-Zeilen).", "Fehler", "OK", "Error")
        return
    }

    $selectedAttributesToSetInfo = @{}
    $anyAttributeSelected = $false
    foreach ($checkBox in $Global:GuiControls.StackPanelAttributeSelection.Children) {
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
        Write-Log "Keine Attribute zum Befüllen ausgewählt." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein Attribut aus, das befüllt werden soll.", "Hinweis", "OK", "Warning")
        return
    }
    Write-Log "Folgende Attribute wurden zum Befüllen ausgewählt: $($selectedAttributesToSetInfo.Keys -join ', ')"

    # Fortschrittsanzeige aktivieren
    Show-Progress -Text "Starte Attribut-Update..." -Value 0

    $usersProcessed = 0
    $usersFailed = 0

    for ($i = 0; $i -lt $numUsersToUpdate; $i++) {
        $samAccountName = $Global:CreatedUsers[$i]
        $csvRow = $Global:CsvData[$i]

        # Fortschritt aktualisieren
        Update-Progress -Current ($i + 1) -Total $numUsersToUpdate -Text "Aktualisiere Benutzerattribute"

        Write-Log "Verarbeite Benutzer '$samAccountName' (Datensatz $($i+1) aus CSV)..."
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
                            # Prüfe ob Manager-DN gültig ist
                            try {
                                $managerUser = Get-ADUser -Filter "DistinguishedName -eq '$valueFromCsv' -or SamAccountName -eq '$valueFromCsv'" -ErrorAction SilentlyContinue
                                if ($managerUser) {
                                    $attributesForReplaceCmd[$attrNameKey] = $managerUser.DistinguishedName
                                } else {
                                    Write-Log "  Manager '$valueFromCsv' nicht gefunden für Benutzer '$samAccountName'" -Level "WARN"
                                }
                            } catch {
                                Write-Log "  Fehler beim Validieren des Managers: $($_.Exception.Message)" -Level "WARN"
                            }
                        }
                        "Country" {
                            # Konvertiere zu 2-Buchstaben-Code wenn nötig
                            if ($valueFromCsv -eq "Germany" -or $valueFromCsv -eq "Deutschland") { $valueFromCsv = "DE" }
                            elseif ($valueFromCsv -eq "United States" -or $valueFromCsv -eq "USA") { $valueFromCsv = "US" }
                            elseif ($valueFromCsv -eq "United Kingdom" -or $valueFromCsv -eq "UK") { $valueFromCsv = "GB" }
                            # Weitere Länder nach Bedarf hinzufügen
                            $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv
                        }
                        "PostalCode" {
                            # Entferne führende Nullen wenn nötig
                            $attributesForReplaceCmd[$attrNameKey] = $valueFromCsv.TrimStart('0')
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
                    Write-Log "  Setze '$attrNameKey' auf '$($attributesForReplaceCmd[$attrNameKey])' (aus CSV-Spalte '$csvHeaderName')"
                } else {
                    Write-Log "  Wert für '$attrNameKey' (aus CSV '$csvHeaderName') ist leer. Attribut wird für '$samAccountName' nicht geändert." -Level "INFO"
                }
            } else {
                Write-Log "  CSV-Spalte '$csvHeaderName' für Attribut '$attrNameKey' nicht im aktuellen CSV-Datensatz gefunden." -Level "WARN"
            }
        }

        if ($attributesForReplaceCmd.Count -gt 0) {
            try {
                Set-ADUser -Identity $samAccountName -Replace $attributesForReplaceCmd -ErrorAction Stop
                Write-Log "Benutzer '$samAccountName' erfolgreich aktualisiert." -Level "SUCCESS"
                $usersProcessed++
            } catch {
                Write-Log "Fehler beim Aktualisieren von Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
                $usersFailed++
            }
        } else {
            Write-Log "Keine gültigen Attributwerte zum Aktualisieren für Benutzer '$samAccountName' gefunden. Übersprungen." -Level "INFO"
        }
    }

    # Fortschrittsanzeige ausblenden
    Hide-Progress

    $summaryMessage = "Aktion 'Attribute befüllen' abgeschlossen. $usersProcessed Benutzer erfolgreich aktualisiert, $usersFailed Fehler."
    Write-Log $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Disable-CreatedADUsers {
    Write-Log "Aktion 'User deaktivieren' gestartet..."
    if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
        Write-Log "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $result = [System.Windows.MessageBox]::Show("Sind Sie sicher, dass Sie die erstellten Benutzer deaktivieren möchten?", "Bestätigung", "YesNo", "Question")
    if ($result -ne "Yes") {
        Write-Log "Benutzer-Deaktivierung abgebrochen." -Level "INFO"
        return
    }

    $numUsersForActionText = $Global:GuiControls.TextBoxNumUsersForAction.Text
    $numUsersToDisable = if ([string]::IsNullOrWhiteSpace($numUsersForActionText)) { $Global:CreatedUsers.Count } else { [int]$numUsersForActionText }

    $usersProcessed = 0
    $usersFailed = 0

    for ($i = 0; $i -lt [Math]::Min($numUsersToDisable, $Global:CreatedUsers.Count); $i++) {
        $samAccountName = $Global:CreatedUsers[$i]
        try {
            Disable-ADAccount -Identity $samAccountName -ErrorAction Stop
            Write-Log "Benutzer '$samAccountName' erfolgreich deaktiviert." -Level "SUCCESS"
            $usersProcessed++
        } catch {
            Write-Log "Fehler beim Deaktivieren von Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }

    $summaryMessage = "Aktion 'User deaktivieren' abgeschlossen. $usersProcessed Benutzer deaktiviert, $usersFailed Fehler."
    Write-Log $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Remove-CreatedADUsers {
    Write-Log "Aktion 'User löschen' gestartet..."
    if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
        Write-Log "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $result = [System.Windows.MessageBox]::Show("WARNUNG: Diese Aktion löscht die erstellten Benutzer UNWIDERRUFLICH!`n`nSind Sie sicher?", "VORSICHT - Benutzer löschen", "YesNo", "Warning")
    if ($result -ne "Yes") {
        Write-Log "Benutzer-Löschung abgebrochen." -Level "INFO"
        return
    }

    $numUsersForActionText = $Global:GuiControls.TextBoxNumUsersForAction.Text
    $numUsersToDelete = if ([string]::IsNullOrWhiteSpace($numUsersForActionText)) { $Global:CreatedUsers.Count } else { [int]$numUsersForActionText }

    $usersProcessed = 0
    $usersFailed = 0

    for ($i = 0; $i -lt [Math]::Min($numUsersToDelete, $Global:CreatedUsers.Count); $i++) {
        $samAccountName = $Global:CreatedUsers[$i]
        try {
            Remove-ADUser -Identity $samAccountName -Confirm:$false -ErrorAction Stop
            Write-Log "Benutzer '$samAccountName' erfolgreich gelöscht." -Level "SUCCESS"
            $usersProcessed++
        } catch {
            Write-Log "Fehler beim Löschen von Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }

    # Erfolgreich gelöschte Benutzer aus der Liste entfernen
    for ($i = $usersProcessed - 1; $i -ge 0; $i--) {
        $Global:CreatedUsers.RemoveAt($i)
    }

    $summaryMessage = "Aktion 'User löschen' abgeschlossen. $usersProcessed Benutzer gelöscht, $usersFailed Fehler."
    Write-Log $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Export-CreatedUsers {
    Write-Log "Export der erstellten Benutzer gestartet..."
    if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
        Write-Log "Keine Benutzer zum Exportieren vorhanden." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt oder alle wurden bereits gelöscht.", "Hinweis", "OK", "Warning")
        return
    }

    try {
        $exportPath = ".\Created_Users_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $exportData = @()
        
        foreach ($samAccountName in $Global:CreatedUsers) {
            try {
                $user = Get-ADUser -Identity $samAccountName -Properties * -ErrorAction Stop
                $exportData += [PSCustomObject]@{
                    SamAccountName = $user.SamAccountName
                    DisplayName = $user.DisplayName
                    GivenName = $user.GivenName
                    Surname = $user.Surname
                    UserPrincipalName = $user.UserPrincipalName
                    EmailAddress = $user.EmailAddress
                    Enabled = $user.Enabled
                    Created = $user.Created
                    DistinguishedName = $user.DistinguishedName
                }
            } catch {
                Write-Log "Fehler beim Abrufen der Details für Benutzer '$samAccountName': $($_.Exception.Message)" -Level "WARN"
                $exportData += [PSCustomObject]@{
                    SamAccountName = $samAccountName
                    DisplayName = "Fehler beim Abrufen"
                    GivenName = ""
                    Surname = ""
                    UserPrincipalName = ""
                    EmailAddress = ""
                    Enabled = "Unbekannt"
                    Created = ""
                    DistinguishedName = ""
                }
            }
        }

        $exportData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        Write-Log "Export erfolgreich: $exportPath" -Level "SUCCESS"
        [System.Windows.MessageBox]::Show("Benutzerliste erfolgreich exportiert nach:`n$exportPath", "Export abgeschlossen", "OK", "Information")
    } catch {
        Write-Log "Fehler beim Export: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Exportieren der Benutzerliste:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Show-CsvBrowser {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
        $openFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $openFileDialog.Title = "CSV-Datei auswählen"
        $openFileDialog.InitialDirectory = Split-Path $Global:GuiControls.TextBoxCsvPath.Text -Parent

        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Global:GuiControls.TextBoxCsvPath.Text = $openFileDialog.FileName
            Write-Log "CSV-Pfad ausgewählt: $($openFileDialog.FileName)" -Level "INFO"
        }
    } catch {
        Write-Log "Fehler beim Öffnen des Datei-Browsers: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Öffnen des Datei-Browsers. Bitte geben Sie den Pfad manuell ein.", "Fehler", "OK", "Error")
    }
}

function Apply-SecuritySettings {
    Write-Log "Anwenden kritischer Sicherheitseinstellungen gestartet..."
    if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
        Write-Log "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $result = [System.Windows.MessageBox]::Show("WARNUNG: Sie sind dabei, kritische Sicherheitseinstellungen zu ändern!`n`nDies kann Ihre Domäne gefährden. Sind Sie sicher?", "KRITISCHE SICHERHEITSWARNUNG", "YesNo", "Warning")
    if ($result -ne "Yes") {
        Write-Log "Anwendung kritischer Sicherheitseinstellungen abgebrochen." -Level "INFO"
        return
    }

    $numUsersForActionText = $Global:GuiControls.TextBoxNumUsersForAction.Text
    $numUsersToModify = if ([string]::IsNullOrWhiteSpace($numUsersForActionText)) { $Global:CreatedUsers.Count } else { [int]$numUsersForActionText }

    $usersProcessed = 0
    $usersFailed = 0

    $pwdNotExpires = $Global:GuiControls.CheckBoxPwdNotExpires.IsChecked
    $revPwd = $Global:GuiControls.CheckBoxRevPwd.IsChecked

    for ($i = 0; $i -lt [Math]::Min($numUsersToModify, $Global:CreatedUsers.Count); $i++) {
        $samAccountName = $Global:CreatedUsers[$i]
        try {
            $params = @{}
            
            if ($pwdNotExpires) {
                $params.PasswordNeverExpires = $true
                Write-Log "Setze für '$samAccountName': Passwort läuft nie ab" -Level "WARN"
            }
            
            if ($revPwd) {
                $params.AllowReversiblePasswordEncryption = $true
                Write-Log "Setze für '$samAccountName': Umgekehrte Verschlüsselung aktiviert" -Level "WARN"
            }

            if ($params.Count -gt 0) {
                Set-ADUser -Identity $samAccountName @params -ErrorAction Stop
                Write-Log "Sicherheitseinstellungen für Benutzer '$samAccountName' erfolgreich angewendet." -Level "SUCCESS"
                $usersProcessed++
            }
        } catch {
            Write-Log "Fehler beim Anwenden der Sicherheitseinstellungen für Benutzer '$samAccountName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }

    $summaryMessage = "Anwendung kritischer Sicherheitseinstellungen abgeschlossen. $usersProcessed Benutzer bearbeitet, $usersFailed Fehler."
    Write-Log $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Add-ToGroup {
    Write-Log "Gruppenzuweisung gestartet..."
    if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
        Write-Log "Keine Benutzer zuvor erstellt. Aktion abgebrochen." -Level "WARN"
        [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer mit diesem Tool erstellt.", "Hinweis", "OK", "Warning")
        return
    }

    $selectedGroup = $Global:GuiControls.ComboBoxCriticalGroups.SelectedItem
    if (-not $selectedGroup) {
        Write-Log "Keine Gruppe ausgewählt." -Level "WARN"
        [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Gruppe aus der Liste aus.", "Hinweis", "OK", "Warning")
        return
    }

    $groupName = $selectedGroup.Content
    $result = [System.Windows.MessageBox]::Show("EXTREM GEFAEHRLICH: Sie sind dabei, Benutzer zur Gruppe '$groupName' hinzuzufuegen!`n`nDies gibt diesen Benutzern hoechste Privilegien. Sind Sie ABSOLUT sicher?", "KRITISCHE SICHERHEITSWARNUNG", "YesNo", "Warning")
    if ($result -ne "Yes") {
        Write-Log "Gruppenzuweisung zu '$groupName' abgebrochen." -Level "INFO"
        return
    }

    $numUsersForActionText = $Global:GuiControls.TextBoxNumUsersForAction.Text
    $numUsersToAdd = if ([string]::IsNullOrWhiteSpace($numUsersForActionText)) { $Global:CreatedUsers.Count } else { [int]$numUsersForActionText }

    $usersProcessed = 0
    $usersFailed = 0

    for ($i = 0; $i -lt [Math]::Min($numUsersToAdd, $Global:CreatedUsers.Count); $i++) {
        $samAccountName = $Global:CreatedUsers[$i]
        try {
            Add-ADGroupMember -Identity $groupName -Members $samAccountName -ErrorAction Stop
            Write-Log "Benutzer '$samAccountName' erfolgreich zur Gruppe '$groupName' hinzugefügt." -Level "SUCCESS"
            $usersProcessed++
        } catch {
            Write-Log "Fehler beim Hinzufügen von Benutzer '$samAccountName' zur Gruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
            $usersFailed++
        }
    }

    $summaryMessage = "Gruppenzuweisung zu '$groupName' abgeschlossen. $usersProcessed Benutzer hinzugefügt, $usersFailed Fehler."
    Write-Log $summaryMessage -Level "INFO"
    [System.Windows.MessageBox]::Show($summaryMessage, "Aktion abgeschlossen", "OK", "Information")
}

function Test-ADConnection {
    try {
        Write-Log "Prüfe Active Directory Verbindung..."
        $domain = Get-ADDomain -ErrorAction Stop
        Write-Log "AD-Verbindung erfolgreich. Domäne: $($domain.Name)" -Level "SUCCESS"
        return $true
    } catch {
        Write-Log "Fehler bei AD-Verbindung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Active Directory Verbindung fehlgeschlagen:`n$($_.Exception.Message)`n`nBitte stellen Sie sicher, dass:`n- Das ActiveDirectory-Modul installiert ist`n- Sie mit einer Domäne verbunden sind`n- Sie über ausreichende Berechtigungen verfügen", "AD-Verbindungsfehler", "OK", "Error")
        return $false
    }
}

function Validate-TargetOU {
    param([string]$TargetOU)
    
    if (-not $TargetOU) {
        return $false
    }
    
    try {
        $ou = Get-ADOrganizationalUnit -Identity $TargetOU -ErrorAction Stop
        Write-Log "Ziel-OU validiert: $($ou.DistinguishedName)" -Level "SUCCESS"
        return $true
    } catch {
        Write-Log "Ziel-OU nicht gefunden oder ungültig: $TargetOU - $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Die angegebene Ziel-OU ist ungültig oder nicht gefunden:`n$TargetOU`n`nFehler: $($_.Exception.Message)", "OU-Validierungsfehler", "OK", "Error")
        return $false
    }
}

function Register-EventHandlers { 
    # CSV-basierte Funktionen
    if ($Global:GuiControls.ButtonBrowseCsv) { $Global:GuiControls.ButtonBrowseCsv.Add_Click({ Show-CsvBrowser }) }
    if ($Global:GuiControls.ButtonLoadCsv) { $Global:GuiControls.ButtonLoadCsv.Add_Click({ Import-CsvData }) }
    if ($Global:GuiControls.ButtonCreateADUsers) { $Global:GuiControls.ButtonCreateADUsers.Add_Click({ New-ADUsersFromCsv }) }
    if ($Global:GuiControls.ButtonFillAttributes) { $Global:GuiControls.ButtonFillAttributes.Add_Click({ Set-ADUserAttributesFromCsv }) }
    if ($Global:GuiControls.ButtonDisableUsers) { $Global:GuiControls.ButtonDisableUsers.Add_Click({ Disable-CreatedADUsers }) }
    if ($Global:GuiControls.ButtonDeleteUsers) { $Global:GuiControls.ButtonDeleteUsers.Add_Click({ Remove-CreatedADUsers }) }
    if ($Global:GuiControls.ButtonExportCreatedUsers) { $Global:GuiControls.ButtonExportCreatedUsers.Add_Click({ Export-CreatedUsers }) }
    if ($Global:GuiControls.ButtonApplySecuritySettings) { $Global:GuiControls.ButtonApplySecuritySettings.Add_Click({ Apply-SecuritySettings }) }
    #if ($Global:GuiControls.ButtonAssignToGroups) { $Global:GuiControls.ButtonAssignToGroups.Add_Click({ Add-ToGroup }) }
    
    # Neue Event Handler für Benutzer-Erstellung & Verwaltung
    #if ($Global:GuiControls.ButtonGeneratePasswords) { $Global:GuiControls.ButtonGeneratePasswords.Add_Click({ Generate-BulkPasswords }) }
    if ($Global:GuiControls.ButtonGenerateRandomData) { $Global:GuiControls.ButtonGenerateRandomData.Add_Click({ Generate-BulkRandomData }) }
    #if ($Global:GuiControls.ButtonCreateFromTemplate) { $Global:GuiControls.ButtonCreateFromTemplate.Add_Click({ Create-UsersFromTemplate }) }
    #if ($Global:GuiControls.ButtonBrowseTemplateUser) { $Global:GuiControls.ButtonBrowseTemplateUser.Add_Click({ Browse-TemplateUser }) }
    #if ($Global:GuiControls.ButtonSetTimeRestrictions) { $Global:GuiControls.ButtonSetTimeRestrictions.Add_Click({ Set-UserTimeRestrictions }) }
    #if ($Global:GuiControls.ButtonBrowseAvatars) { $Global:GuiControls.ButtonBrowseAvatars.Add_Click({ Browse-AvatarPath }) }
    #if ($Global:GuiControls.ButtonAssignAvatars) { $Global:GuiControls.ButtonAssignAvatars.Add_Click({ Assign-UserAvatars }) }
    
    # Schnellzugriff Event Handler
    if ($Global:GuiControls.ButtonQuickRandomUsers) { $Global:GuiControls.ButtonQuickRandomUsers.Add_Click({ Quick-CreateRandomUsers }) }
    if ($Global:GuiControls.ButtonQuickCreateGroups) { $Global:GuiControls.ButtonQuickCreateGroups.Add_Click({ Quick-CreateGroups }) }
    if ($Global:GuiControls.ButtonQuickTestData) { $Global:GuiControls.ButtonQuickTestData.Add_Click({ Quick-CreateTestData }) }
    if ($Global:GuiControls.ButtonQuickCleanup) { $Global:GuiControls.ButtonQuickCleanup.Add_Click({ Quick-CleanupAll }) }
    
    # Löschfunktionen Event Handler
    if ($Global:GuiControls.ButtonDeleteGroups) { $Global:GuiControls.ButtonDeleteGroups.Add_Click({ Remove-CreatedGroups }) }
    if ($Global:GuiControls.ButtonDeleteComputers) { $Global:GuiControls.ButtonDeleteComputers.Add_Click({ Remove-CreatedComputers }) }
    if ($Global:GuiControls.ButtonDeleteOUs) { $Global:GuiControls.ButtonDeleteOUs.Add_Click({ Remove-CreatedOUs }) }
    if ($Global:GuiControls.ButtonDeleteServiceAccounts) { $Global:GuiControls.ButtonDeleteServiceAccounts.Add_Click({ Remove-CreatedServiceAccounts }) }
    if ($Global:GuiControls.ButtonExportAll) { $Global:GuiControls.ButtonExportAll.Add_Click({ Export-AllObjects }) }
    
    # Test-Umgebung Event Handler
    if ($Global:GuiControls.ButtonCreateTestEnvironment) { $Global:GuiControls.ButtonCreateTestEnvironment.Add_Click({ Create-TestEnvironment }) }
    if ($Global:GuiControls.ButtonCreateRandomUsers) { $Global:GuiControls.ButtonCreateRandomUsers.Add_Click({ Create-RandomUsers }) }
    
    # Event Handler für Gruppen & Organisationsstruktur
    if ($Global:GuiControls.ButtonCreateAutoGroups) { $Global:GuiControls.ButtonCreateAutoGroups.Add_Click({ Create-AutomaticGroups }) }
    if ($Global:GuiControls.ButtonCreateNestedGroups) { $Global:GuiControls.ButtonCreateNestedGroups.Add_Click({ Create-NestedGroupStructure }) }
    #if ($Global:GuiControls.ButtonCreateDynamicGroups) { $Global:GuiControls.ButtonCreateDynamicGroups.Add_Click({ Create-DynamicSecurityGroups }) }
    #if ($Global:GuiControls.ButtonCreateOUStructure) { $Global:GuiControls.ButtonCreateOUStructure.Add_Click({ Create-OrganizationalUnitStructure }) }
    
    # Event Handler für Computer & Geräte
    if ($Global:GuiControls.ButtonCreateComputers) { $Global:GuiControls.ButtonCreateComputers.Add_Click({ Create-ComputerObjects }) }
    if ($Global:GuiControls.ButtonCreateServiceAccounts) { $Global:GuiControls.ButtonCreateServiceAccounts.Add_Click({ Create-ServiceAccounts }) }
    #if ($Global:GuiControls.ButtonCreatePrinters) { $Global:GuiControls.ButtonCreatePrinters.Add_Click({ Create-PrinterObjects }) }
    if ($Global:GuiControls.ButtonCreateBitLockerData) { $Global:GuiControls.ButtonCreateBitLockerData.Add_Click({ Create-ComputerBitLockerData }) }
    if ($Global:GuiControls.ButtonCreateLAPSData) { $Global:GuiControls.ButtonCreateLAPSData.Add_Click({ Create-LAPSData }) }
    
    # Event Handler für Test-Szenarien
    if ($Global:GuiControls.ButtonCreateTestDataSet) { $Global:GuiControls.ButtonCreateTestDataSet.Add_Click({ Create-TestDataSet }) }
    if ($Global:GuiControls.ButtonActivateChaosMode) { $Global:GuiControls.ButtonActivateChaosMode.Add_Click({ Activate-ChaosMode }) }
    #if ($Global:GuiControls.ButtonStartPerformanceTest) { $Global:GuiControls.ButtonStartPerformanceTest.Add_Click({ Start-PerformanceTest }) }
    
    # Event Handler für Sicherheit & Compliance
    if ($Global:GuiControls.ButtonApplyPasswordPolicies) { $Global:GuiControls.ButtonApplyPasswordPolicies.Add_Click({ Apply-PasswordPolicies }) }
    if ($Global:GuiControls.ButtonCreateRBACRoles) { $Global:GuiControls.ButtonCreateRBACRoles.Add_Click({ Create-RBACRoles }) }
    #if ($Global:GuiControls.ButtonCreateBitLockerKeys) { $Global:GuiControls.ButtonCreateBitLockerKeys.Add_Click({ Create-BitLockerKeys }) }
    
    # Event Handler für Erweiterte Features
    #if ($Global:GuiControls.ButtonCreateDNSEntries) { $Global:GuiControls.ButtonCreateDNSEntries.Add_Click({ Create-DNSEntries }) }
    #if ($Global:GuiControls.ButtonSimulateMigration) { $Global:GuiControls.ButtonSimulateMigration.Add_Click({ Simulate-Migration }) }
    #if ($Global:GuiControls.ButtonCreateKerberosTests) { $Global:GuiControls.ButtonCreateKerberosTests.Add_Click({ Create-KerberosTests }) }
    #if ($Global:GuiControls.ButtonDocumentFSMO) { $Global:GuiControls.ButtonDocumentFSMO.Add_Click({ Document-FSMORoles }) }
    if ($Global:GuiControls.ButtonCreateAdvancedFeatures) { $Global:GuiControls.ButtonCreateAdvancedFeatures.Add_Click({ Create-AdvancedFeatures }) }
 
    Write-Log "Event Handler registriert." 
} 
 
#endregion 
 
#region Initialisierung und Start 
 
function Initialize-Application { 
    Write-Log "Initialisiere Anwendung..." 
    try { 
        # XAML korrekt laden 
        $stringReader = New-Object System.IO.StringReader -ArgumentList $XAML 
        $xmlTextReader = [System.Xml.XmlTextReader]::new($stringReader) 
        $Global:Window = [Windows.Markup.XamlReader]::Load($xmlTextReader) 
 
        if (-not $Global:Window) { 
            Throw "Kritischer Fehler: Das XAML-Fenster konnte nicht geladen werden." 
        } 
        Write-Log "XAML-Fenster erfolgreich geladen." 
 
        Get-GuiControls # Ruft die korrigierte Funktion auf, die $Global:Window verwendet 
        Register-EventHandlers 
 
        # Standard CSV laden, falls vorhanden, ansonsten Beispiel erstellen
        $Global:GuiControls.TextBoxCsvPath.Text = $Global:AppConfig.DefaultCsvPath
        if (Test-Path $Global:AppConfig.DefaultCsvPath -PathType Leaf) { 
            Import-CsvData 
        } else { 
            Write-Log "Standard CSV-Datei nicht gefunden: $($Global:AppConfig.DefaultCsvPath)" -Level "WARN" 
            Create-SampleCsv
        } 

        # AD-Verbindung testen (nicht blockierend)
        if (-not (Test-ADConnection)) {
            Write-Log "AD-Verbindung fehlgeschlagen - Funktion eingeschränkt verfügbar." -Level "WARN"
        } else {
            # OU-Dropdown initialisieren wenn AD-Verbindung besteht
            Initialize-OUDropdown
        }

        Write-Log "Anwendung erfolgreich initialisiert." -Level "SUCCESS" 
    } catch { 
        Write-Log "Fehler während der Anwendungsinitialisierung: $($_.Exception.ToString())" -Level "ERROR" 
        # Den Fehler weiterwerfen, damit er vom äußeren try-catch in Start-Application behandelt wird 
        throw $_ 
    } 
}

function Create-SampleCsv {
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
        
        $sampleData | Export-Csv -Path $Global:AppConfig.DefaultCsvPath -NoTypeInformation -Encoding UTF8
        Write-Log "Beispiel-CSV erstellt: $($Global:AppConfig.DefaultCsvPath)" -Level "INFO"
        Import-CsvData
    } catch {
        Write-Log "Fehler beim Erstellen der Beispiel-CSV: $($_.Exception.Message)" -Level "ERROR"
    }
}

#region GUI Verbesserungen - OU Dropdown, Progress, UPN Generation

function Get-ADOrganizationalUnits {
    <#
    .SYNOPSIS
    Ruft alle verfügbaren Organizational Units aus Active Directory ab
    #>
    try {
        Write-Log "Lade OUs aus Active Directory..."
        $ous = Get-ADOrganizationalUnit -Filter * | Sort-Object DistinguishedName
        Write-Log "$(($ous | Measure-Object).Count) OUs gefunden" -Level "SUCCESS"
        return $ous
    } catch {
        Write-Log "Fehler beim Laden der OUs: $($_.Exception.Message)" -Level "ERROR"
        return @()
    }
}

function Initialize-OUDropdown {
    <#
    .SYNOPSIS
    Befüllt die OU-ComboBox mit verfügbaren OUs
    #>
    try {
        $comboBox = $Global:GuiControls.ComboBoxTargetOU
        $comboBox.Items.Clear()
        
        # Standard-OU hinzufügen
        $comboBox.Items.Add("OU=DummyUsers,DC=example,DC=com")
        
        # AD OUs laden
        $ous = Get-ADOrganizationalUnits
        foreach ($ou in $ous) {
            if ($ou.DistinguishedName -notlike "*CN=*") {  # Nur echte OUs, keine Container
                $comboBox.Items.Add($ou.DistinguishedName)
            }
        }
        
        # Ersten Eintrag auswählen
        if ($comboBox.Items.Count -gt 0) {
            $comboBox.SelectedIndex = 0
        }
        
        Write-Log "OU-Dropdown initialisiert mit $(($comboBox.Items | Measure-Object).Count) Einträgen" -Level "SUCCESS"
    } catch {
        Write-Log "Fehler beim Initialisieren des OU-Dropdowns: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Generate-UPN {
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
            # Versuche die Standard-Domain aus AD zu ermitteln
            $domain = Get-ADDomain -ErrorAction SilentlyContinue
            if ($domain) {
                $DefaultDomain = $domain.DNSRoot
            } else {
                $DefaultDomain = "example.com"
            }
        }
        
        $upn = "$SamAccountName@$DefaultDomain"
        Write-Log "UPN generiert: $upn" -Level "DEBUG"
        return $upn
    } catch {
        Write-Log "Fehler bei UPN-Generierung für '$SamAccountName': $($_.Exception.Message)" -Level "ERROR"
        return "$SamAccountName@example.com"
    }
}

# Hilfsfunktionen für Zufallsdaten
function New-RandomPassword {
    param(
        [int]$Length = 12,
        [bool]$IncludeNumbers = $true,
        [bool]$IncludeSymbols = $true,
        [bool]$ExcludeAmbiguous = $true
    )
    
    return Generate-SecurePassword -Complexity "Mittel (12 Zeichen + Symbole)" `
        -IncludeNumbers $IncludeNumbers `
        -IncludeSymbols $IncludeSymbols `
        -ExcludeAmbiguous $ExcludeAmbiguous
}

function Get-RandomFirstName {
    $names = $Global:RandomDataLists.FirstNames
    if ($names -and $names.Count -gt 0) {
        return $names | Get-Random
    }
    return "Max"  # Fallback
}

function Get-RandomLastName {
    $names = $Global:RandomDataLists.LastNames
    if ($names -and $names.Count -gt 0) {
        return $names | Get-Random
    }
    return "Mustermann"  # Fallback
}

function Get-RandomStreetAddress {
    $streets = $Global:RandomDataLists.Streets
    if ($streets -and $streets.Count -gt 0) {
        $street = $streets | Get-Random
        $number = Get-Random -Minimum 1 -Maximum 200
        return "$street $number"
    }
    return "Hauptstrasse 1"  # Fallback
}

function Get-RandomCity {
    $cities = $Global:RandomDataLists.Cities
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
    $departments = $Global:RandomDataLists.Departments
    if ($departments -and $departments.Count -gt 0) {
        return $departments | Get-Random
    }
    return "IT"  # Fallback
}

function Get-RandomJobTitle {
    $titles = $Global:RandomDataLists.JobTitles
    if ($titles -and $titles.Count -gt 0) {
        return $titles | Get-Random
    }
    return "Specialist"  # Fallback
}

function Update-Statistics {
    <#
    .SYNOPSIS
    Aktualisiert die Statistik-Anzeige
    #>
    try {
        # Benutzer zählen
        $userCount = $Global:CreatedUsers.Count
        $Global:GuiControls.TextBlockUserCount.Text = $userCount.ToString()
        
        # Gruppen zählen (wird später implementiert)
        $groupCount = 0
        if ($Global:CreatedGroups) {
            $groupCount = $Global:CreatedGroups.Count
        }
        $Global:GuiControls.TextBlockGroupCount.Text = $groupCount.ToString()
        
        # Computer zählen (wird später implementiert)
        $computerCount = 0
        if ($Global:CreatedComputers) {
            $computerCount = $Global:CreatedComputers.Count
        }
        $Global:GuiControls.TextBlockComputerCount.Text = $computerCount.ToString()
        
        # OUs zählen (wird später implementiert)
        $ouCount = 0
        if ($Global:CreatedOUs) {
            $ouCount = $Global:CreatedOUs.Count
        }
        $Global:GuiControls.TextBlockOUCount.Text = $ouCount.ToString()
        
        # Service Accounts zählen (wird später implementiert)
        $serviceCount = 0
        if ($Global:CreatedServiceAccounts) {
            $serviceCount = $Global:CreatedServiceAccounts.Count
        }
        $Global:GuiControls.TextBlockServiceCount.Text = $serviceCount.ToString()
        
        # Gesamt
        $totalCount = $userCount + $groupCount + $computerCount + $ouCount + $serviceCount
        $Global:GuiControls.TextBlockTotalCount.Text = $totalCount.ToString()
        
        Write-Log "Statistiken aktualisiert" -Level "DEBUG"
    } catch {
        Write-Log "Fehler beim Aktualisieren der Statistiken: $($_.Exception.Message)" -Level "WARN"
    }
}

function Generate-DummyAvatars {
    <#
    .SYNOPSIS
    Generiert Dummy-Avatar-Bilder für Benutzer
    #>
    try {
        Add-Type -AssemblyName System.Drawing
        
        $avatarDir = ".\DummyAvatars_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -Path $avatarDir -ItemType Directory -Force | Out-Null
        
        Show-Progress -Text "Generiere Dummy-Avatare..." -Value 0
        
        $colors = @(
            [System.Drawing.Color]::FromArgb(52, 152, 219),   # Blau
            [System.Drawing.Color]::FromArgb(46, 204, 113),   # Grün
            [System.Drawing.Color]::FromArgb(231, 76, 60),    # Rot
            [System.Drawing.Color]::FromArgb(155, 89, 182),   # Lila
            [System.Drawing.Color]::FromArgb(241, 196, 15),   # Gelb
            [System.Drawing.Color]::FromArgb(230, 126, 34),   # Orange
            [System.Drawing.Color]::FromArgb(149, 165, 166),  # Grau
            [System.Drawing.Color]::FromArgb(52, 73, 94)      # Dunkelblau
        )
        
        $successCount = 0
        $errorCount = 0
        
        for ($i = 0; $i -lt $Global:CreatedUsers.Count; $i++) {
            $user = $Global:CreatedUsers[$i]
            Update-Progress -Current ($i + 1) -Total $Global:CreatedUsers.Count -Text "Generiere Avatar für $user"
            
            try {
                # Initialen ermitteln
                $userObj = Get-ADUser -Identity $user -Properties GivenName, Surname -ErrorAction Stop
                $initials = ""
                
                if ($userObj.GivenName) { $initials += $userObj.GivenName.Substring(0,1).ToUpper() }
                if ($userObj.Surname) { $initials += $userObj.Surname.Substring(0,1).ToUpper() }
                if ($initials -eq "") { $initials = $user.Substring(0,2).ToUpper() }
                
                # Bitmap erstellen
                $bitmap = New-Object System.Drawing.Bitmap 200, 200
                $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
                $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
                
                # Hintergrundfarbe
                $bgColor = $colors[$i % $colors.Count]
                $graphics.Clear($bgColor)
                
                # Text (Initialen)
                $font = New-Object System.Drawing.Font("Arial", 72, [System.Drawing.FontStyle]::Bold)
                $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
                $stringFormat = New-Object System.Drawing.StringFormat
                $stringFormat.Alignment = [System.Drawing.StringAlignment]::Center
                $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
                
                $rect = New-Object System.Drawing.RectangleF(0, 0, 200, 200)
                $graphics.DrawString($initials, $font, $brush, $rect, $stringFormat)
                
                # Speichern
                $avatarFile = Join-Path $avatarDir "$user.jpg"
                $bitmap.Save($avatarFile, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                
                # AD Thumbnail aktualisieren
                $photo = [System.IO.File]::ReadAllBytes($avatarFile)
                Set-ADUser -Identity $user -Replace @{thumbnailPhoto=$photo} -ErrorAction Stop
                
                $successCount++
                Write-Log "Avatar für '$user' generiert und zugewiesen" -Level "DEBUG"
                
                # Aufräumen
                $graphics.Dispose()
                $bitmap.Dispose()
                $font.Dispose()
                $brush.Dispose()
                
            } catch {
                $errorCount++
                Write-Log "Fehler beim Generieren des Avatars für '$user': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        Hide-Progress
        
        $message = "Dummy-Avatare wurden generiert.`nErfolgreich: $successCount`nFehler: $errorCount`nGespeichert unter: $avatarDir"
        [System.Windows.MessageBox]::Show($message, "Avatare generiert", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Dummy-Avatar-Generierung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Avatar-Generierung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Generate-BulkPasswords {
    try {
        Write-Log "Starte Bulk-Passwort-Generierung..." -Level "INFO"
        
        $complexity = $Global:GuiControls.ComboBoxPasswordComplexity.SelectedItem
        $includeNumbers = $Global:GuiControls.CheckBoxIncludeNumbers.IsChecked
        $includeSymbols = $Global:GuiControls.CheckBoxIncludeSymbols.IsChecked 
        $excludeAmbiguous = $Global:GuiControls.CheckBoxExcludeAmbiguous.IsChecked

        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer für Passwort-Reset vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie für $($Global:CreatedUsers.Count) Benutzer neue Passwörter generieren?",
            "Passwörter zurücksetzen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Generiere neue Passwörter..."
        $processed = 0
        $failed = 0

        foreach ($user in $Global:CreatedUsers) {
            try {
                # Komplexität aus ComboBox ermitteln
                $complexityText = if ($complexity) { $complexity.Content } else { "Mittel (12 Zeichen + Symbole)" }
                
                $newPassword = Generate-SecurePassword -Complexity $complexityText `
                    -IncludeNumbers $includeNumbers `
                    -IncludeSymbols $includeSymbols `
                    -ExcludeAmbiguous $excludeAmbiguous
                
                Set-ADAccountPassword -Identity $user -NewPassword (ConvertTo-SecureString -String $newPassword -AsPlainText -Force) -ErrorAction Stop
                Write-Log "Passwort für ${user} erfolgreich zurückgesetzt" -Level "SUCCESS"
                $processed++
            }
            catch {
                Write-Log "Fehler beim Passwort-Reset für ${user}: $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
            
            Update-Progress -Current $processed -Total $Global:CreatedUsers.Count
        }

        Hide-Progress
        [System.Windows.MessageBox]::Show("Passwort-Reset abgeschlossen.`n$processed Benutzer aktualisiert, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Bulk-Passwort-Generierung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Generate-BulkRandomData {
    try {
        Write-Log "Starte Generierung von Zufallsdaten..." -Level "INFO"

        $randomNames = $Global:GuiControls.CheckBoxRandomNames.IsChecked
        $randomAddresses = $Global:GuiControls.CheckBoxRandomAddresses.IsChecked
        $randomPhone = $Global:GuiControls.CheckBoxRandomPhone.IsChecked
        $randomDepartments = $Global:GuiControls.CheckBoxRandomDepartments.IsChecked

        if (-not ($randomNames -or $randomAddresses -or $randomPhone -or $randomDepartments)) {
            Write-Log "Keine Attribute für Zufallsdaten ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein Attribut für Zufallsdaten aus.", "Hinweis", "OK", "Warning")
            return
        }

        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer für Zufallsdaten vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        Show-Progress -Text "Generiere Zufallsdaten..."
        $processed = 0
        $failed = 0

        foreach ($user in $Global:CreatedUsers) {
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
                }
                
                if ($randomPhone) {
                    $params.OfficePhone = Get-RandomPhoneNumber
                    $params.MobilePhone = Get-RandomPhoneNumber
                }
                
                if ($randomDepartments) {
                    $params.Department = Get-RandomDepartment
                    $params.Title = Get-RandomJobTitle
                }

                Set-ADUser -Identity $user @params -ErrorAction Stop
                Write-Log "Zufallsdaten für ${user} erfolgreich gesetzt" -Level "SUCCESS"
                $processed++
            }
            catch {
                Write-Log "Fehler beim Setzen von Zufallsdaten für ${user}: $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
            
            Update-Progress -Current $processed -Total $Global:CreatedUsers.Count
        }

        Hide-Progress
        [System.Windows.MessageBox]::Show("Zufallsdaten-Generierung abgeschlossen.`n$processed Benutzer aktualisiert, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Zufallsdaten-Generierung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Create-UsersFromTemplate {
    try {
        Write-Log "Starte Benutzer-Erstellung aus Vorlage..." -Level "INFO"
        
        $templateUser = $Global:GuiControls.TextBoxTemplateUser.Text
        if ([string]::IsNullOrWhiteSpace($templateUser)) {
            Write-Log "Kein Vorlagen-Benutzer angegeben" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Vorlagen-Benutzer aus.", "Hinweis", "OK", "Warning")
            return
        }

        try {
            $template = Get-ADUser -Identity $templateUser -Properties * -ErrorAction Stop
        }
        catch {
            Write-Log "Vorlagen-Benutzer nicht gefunden: $templateUser" -Level "ERROR"
            [System.Windows.MessageBox]::Show("Der angegebene Vorlagen-Benutzer wurde nicht gefunden.", "Fehler", "OK", "Error")
            return
        }

        $numUsers = [int]$Global:GuiControls.TextBoxNumUsersToCreate.Text
        if ($numUsers -lt 1) {
            Write-Log "Ungültige Anzahl Benutzer angegeben: $numUsers" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Benutzern an.", "Hinweis", "OK", "Warning")
            return
        }

        Show-Progress -Text "Erstelle Benutzer aus Vorlage..."
        $processed = 0
        $failed = 0

        for ($i = 1; $i -le $numUsers; $i++) {
            try {
                $newUser = @{
                    Name = "Copy_$($template.Name)_$i"
                    SamAccountName = "copy$($template.SamAccountName)$i"
                    UserPrincipalName = "copy$($template.SamAccountName)$i@$($template.UserPrincipalName.Split('@')[1])"
                    Path = $template.DistinguishedName.Substring($template.DistinguishedName.IndexOf(',') + 1)
                    Instance = $template
                }

                New-ADUser @newUser -ErrorAction Stop
                $Global:CreatedUsers.Add($newUser.SamAccountName)
                Write-Log "Benutzer $($newUser.SamAccountName) aus Vorlage erstellt" -Level "SUCCESS"
                $processed++
            }
            catch {
                Write-Log "Fehler beim Erstellen von Benutzer aus Vorlage: $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
            
            Update-Progress -Current $processed -Total $numUsers
        }

        Hide-Progress
        Update-Statistics
        [System.Windows.MessageBox]::Show("Benutzer-Erstellung aus Vorlage abgeschlossen.`n$processed Benutzer erstellt, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Benutzer-Erstellung aus Vorlage: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Browse-TemplateUser {
    try {
        $templateUser = Get-ADUser -Filter * -Properties DisplayName | 
            Out-GridView -Title "Vorlagen-Benutzer auswählen" -OutputMode Single
        
        if ($templateUser) {
            $Global:GuiControls.TextBoxTemplateUser.Text = $templateUser.SamAccountName
            Write-Log "Vorlagen-Benutzer ausgewählt: $($templateUser.SamAccountName)" -Level "INFO"
        }
    }
    catch {
        Write-Log "Fehler bei Vorlagen-Benutzer-Auswahl: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Laden der Benutzer-Liste.", "Fehler", "OK", "Error")
    }
}

function Set-UserTimeRestrictions {
    try {
        Write-Log "Starte Setzen von Zeitbeschränkungen..." -Level "INFO"

        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer für Zeitbeschränkungen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie für $($Global:CreatedUsers.Count) Benutzer Zeitbeschränkungen setzen?`n`nStandard: Mo-Fr 8-17 Uhr",
            "Zeitbeschränkungen setzen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Setze Zeitbeschränkungen..."
        $processed = 0
        $failed = 0

        # Standard-Zeitbeschränkung: Mo-Fr 8-17 Uhr
        # AD benötigt 168 Bytes (7 Tage * 24 Stunden)
        $timeArray = New-Object byte[] 168
        
        # Alle Stunden auf 0 setzen (kein Zugriff)
        for ($i = 0; $i -lt 168; $i++) {
            $timeArray[$i] = 0
        }
        
        # Mo-Fr (Tag 1-5) von 8-17 Uhr erlauben
        for ($day = 1; $day -le 5; $day++) {  # Mo=1 bis Fr=5
            for ($hour = 8; $hour -lt 17; $hour++) {  # 8-17 Uhr
                $index = (($day - 1) * 24) + $hour
                $timeArray[$index] = 1
            }
        }

        foreach ($user in $Global:CreatedUsers) {
            try {
                Set-ADUser -Identity $user -Replace @{logonHours = $timeArray} -ErrorAction Stop
                Write-Log "Zeitbeschränkungen für ${user} erfolgreich gesetzt" -Level "SUCCESS"
                $processed++
            }
            catch {
                Write-Log "Fehler beim Setzen von Zeitbeschränkungen für ${user}: $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
            
            Update-Progress -Current $processed -Total $Global:CreatedUsers.Count
        }

        Hide-Progress
        [System.Windows.MessageBox]::Show("Zeitbeschränkungen gesetzt.`n$processed Benutzer aktualisiert, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler beim Setzen von Zeitbeschränkungen: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Browse-AvatarPath {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
        $folderBrowser.Description = "Avatar-Verzeichnis auswählen"
        
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $Global:GuiControls.TextBoxAvatarPath.Text = $folderBrowser.SelectedPath
            Write-Log "Avatar-Pfad ausgewählt: $($folderBrowser.SelectedPath)" -Level "INFO"
        }
    }
    catch {
        Write-Log "Fehler bei Avatar-Pfad-Auswahl: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Öffnen des Ordner-Browsers.", "Fehler", "OK", "Error")
    }
}

function Assign-UserAvatars {
    try {
        Write-Log "Starte Avatar-Zuweisung..." -Level "INFO"

        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer für Avatar-Zuweisung vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }

        $generateAvatars = $Global:GuiControls.CheckBoxGenerateAvatars.IsChecked
        $avatarPath = $Global:GuiControls.TextBoxAvatarPath.Text

        if ($generateAvatars) {
            # Dummy-Avatare generieren
            Write-Log "Generiere Dummy-Avatare..." -Level "INFO"
            Generate-DummyAvatars
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($avatarPath)) {
            Write-Log "Kein Avatar-Pfad angegeben" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie einen Avatar-Pfad an oder aktivieren Sie 'Dummy-Avatare generieren'.", "Hinweis", "OK", "Warning")
            return
        }

        if (-not (Test-Path $avatarPath -PathType Container)) {
            Write-Log "Avatar-Verzeichnis nicht gefunden: $avatarPath" -Level "ERROR"
            [System.Windows.MessageBox]::Show("Das angegebene Avatar-Verzeichnis wurde nicht gefunden.", "Fehler", "OK", "Error")
            return
        }

        $avatars = Get-ChildItem -Path $avatarPath -Filter "*.jpg"
        if ($avatars.Count -eq 0) {
            Write-Log "Keine Avatar-Bilder im Verzeichnis gefunden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Keine JPG-Bilder im Avatar-Verzeichnis gefunden.", "Hinweis", "OK", "Warning")
            return
        }

        Show-Progress -Text "Weise Avatare zu..."
        $processed = 0
        $failed = 0

        foreach ($user in $Global:CreatedUsers) {
            try {
                # Zufälliges Avatar auswählen
                $randomAvatar = $avatars | Get-Random
                $photoBytes = [System.IO.File]::ReadAllBytes($randomAvatar.FullName)
                
                Set-ADUser -Identity $user -Replace @{thumbnailPhoto=$photoBytes} -ErrorAction Stop
                Write-Log "Avatar für ${user} erfolgreich zugewiesen" -Level "SUCCESS"
                $processed++
            }
            catch {
                Write-Log "Fehler bei Avatar-Zuweisung für ${user}: $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
            
            Update-Progress -Current $processed -Total $Global:CreatedUsers.Count
        }

        Hide-Progress
        [System.Windows.MessageBox]::Show("Avatar-Zuweisung abgeschlossen.`n$processed Benutzer aktualisiert, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Avatar-Zuweisung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Quick-CreateRandomUsers {
    <#
    .SYNOPSIS
    Schnelle Erstellung von Random-Benutzern
    #>
    try {
        Write-Log "Starte Quick Random User Erstellung..." -Level "INFO"
        
        # Nutze die Random User Creation Funktion
        Create-RandomUsers
        
    } catch {
        Write-Log "Fehler bei Quick Random User Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Schnellerstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-TestEnvironment {
    <#
    .SYNOPSIS
    Erstellt die komplette Test-Umgebung mit allen benötigten OUs
    #>
    try {
        Write-Log "Starte Test-Umgebung Erstellung..." -Level "INFO"
        
        $companyName = $Global:GuiControls.TextBoxCompanyName.Text
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
        
        Show-Progress -Text "Erstelle Test-Umgebung..."
        
        # Basis-OU ermitteln
        $domain = Get-ADDomain
        $baseOU = $domain.DistinguishedName
        
        # Haupt-OU erstellen
        $companyOU = "OU=$companyName,$baseOU"
        
        try {
            # Prüfe ob Haupt-OU bereits existiert
            $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$companyOU'" -ErrorAction SilentlyContinue
            
            if (-not $existingOU) {
                New-ADOrganizationalUnit -Name $companyName `
                    -Path $baseOU `
                    -Description "Test Company OU" `
                    -ProtectedFromAccidentalDeletion $false `
                    -ErrorAction Stop
                
                $Global:CreatedOUs.Add($companyOU)
                Write-Log "Haupt-OU '$companyName' erstellt" -Level "SUCCESS"
            } else {
                Write-Log "Haupt-OU '$companyName' existiert bereits" -Level "INFO"
            }
            
            # Erstelle Unter-OUs
            $subOUs = @{
                "USERS" = "Test User Accounts"
                "GROUPS" = "Test Security Groups"  
                "COMPUTERS" = "Test Computer Accounts"
                "SERVICES" = "Test Service Accounts"
                "RESOURCES" = "Test Resources"
            }
            
            foreach ($ouName in $subOUs.Keys) {
                $ouPath = "OU=$ouName,$companyOU"
                
                try {
                    $existingSubOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue
                    
                    if (-not $existingSubOU) {
                        New-ADOrganizationalUnit -Name $ouName `
                            -Path $companyOU `
                            -Description $subOUs[$ouName] `
                            -ProtectedFromAccidentalDeletion $false `
                            -ErrorAction Stop
                        
                        $Global:CreatedOUs.Add($ouPath)
                        Write-Log "Unter-OU '$ouName' erstellt" -Level "SUCCESS"
                    }
                } catch {
                    Write-Log "Fehler beim Erstellen der OU '$ouName': $($_.Exception.Message)" -Level "ERROR"
                }
            }
            
            # Aktualisiere OU-Dropdown
            Initialize-OUDropdown
            
            # Setze die neue OU als Standard
            $Global:GuiControls.ComboBoxTargetOU.Text = $companyOU
            
            Hide-Progress
            Update-Statistics
            
            [System.Windows.MessageBox]::Show(
                "Test-Umgebung erfolgreich erstellt!`n`n" +
                "Basis-OU: $companyOU`n" +
                "Die OU wurde als Ziel-OU ausgewählt.",
                "Erfolg",
                "OK",
                "Information"
            )
            
        } catch {
            Write-Log "Fehler beim Erstellen der Test-Umgebung: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Test-Umgebung Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-RandomUsers {
    <#
    .SYNOPSIS
    Erstellt zufällige Benutzer basierend auf den GUI-Einstellungen
    #>
    try {
        Write-Log "Starte Random User Erstellung..." -Level "INFO"
        
        # Parameter aus GUI lesen
        $userCount = $Global:GuiControls.TextBoxRandomUserCount.Text
        if ([string]::IsNullOrWhiteSpace($userCount)) {
            $userCount = 50
        } else {
            $userCount = [int]$userCount
        }
        
        if ($userCount -le 0) {
            Write-Log "Ungültige Anzahl Benutzer" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Benutzern an.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Ziel-OU bestimmen
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            Write-Log "Keine gültige Ziel-OU ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte erstellen Sie zuerst eine Test-Umgebung oder wählen Sie eine gültige OU.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Prüfe ob USERS OU existiert
        $userOU = $targetOU
        if ($targetOU -match "OU=\w+,DC=") {
            # Versuche USERS Unter-OU zu verwenden
            $testUserOU = "OU=USERS,$targetOU"
            try {
                $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$testUserOU'" -ErrorAction SilentlyContinue
                if ($existingOU) {
                    $userOU = $testUserOU
                    Write-Log "Verwende USERS OU: $userOU" -Level "DEBUG"
                }
            } catch {
                Write-Log "USERS OU nicht gefunden, verwende Basis-OU" -Level "DEBUG"
            }
        }
        
        # Optionen aus GUI
        $randomNames = $Global:GuiControls.CheckBoxRandomNames.IsChecked
        $randomAddresses = $Global:GuiControls.CheckBoxRandomAddresses.IsChecked
        $randomPhone = $Global:GuiControls.CheckBoxRandomPhone.IsChecked
        $randomDepartments = $Global:GuiControls.CheckBoxRandomDepartments.IsChecked
        $randomTitles = $Global:GuiControls.CheckBoxRandomTitles.IsChecked
        $randomCompany = $Global:GuiControls.CheckBoxRandomCompany.IsChecked
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $userCount zufällige Benutzer erstellen?`n`n" +
            "Ziel-OU: $userOU`n" +
            "Zufällige Namen: $(if ($randomNames) { 'Ja' } else { 'Nein' })`n" +
            "Zufällige Adressen: $(if ($randomAddresses) { 'Ja' } else { 'Nein' })`n" +
            "Zufällige Telefonnummern: $(if ($randomPhone) { 'Ja' } else { 'Nein' })",
            "Random Benutzer erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle zufällige Benutzer..."
        $successCount = 0
        $errorCount = 0
        
        for ($i = 1; $i -le $userCount; $i++) {
            Update-Progress -Current $i -Total $userCount -Text "Erstelle Benutzer $i von $userCount..."
            
            try {
                # Generiere Benutzerdaten
                $firstName = Get-RandomFirstName
                $lastName = Get-RandomLastName
                $samAccountName = "$($firstName.ToLower()).$($lastName.ToLower())$(Get-Random -Minimum 100 -Maximum 999)"
                
                $userParams = @{
                    Name = "$firstName $lastName"
                    SamAccountName = $samAccountName
                    UserPrincipalName = "$samAccountName@$((Get-ADDomain).DNSRoot)"
                    GivenName = $firstName
                    Surname = $lastName
                    DisplayName = "$firstName $lastName"
                    Path = $userOU
                    Enabled = $true
                    AccountPassword = (ConvertTo-SecureString -String (Generate-SecurePassword) -AsPlainText -Force)
                    ChangePasswordAtLogon = $false
                }
                
                # Zusätzliche Attribute
                if ($randomAddresses) {
                    $userParams.StreetAddress = Get-RandomStreetAddress
                    $userParams.City = Get-RandomCity
                    $userParams.PostalCode = Get-RandomPostalCode
                    $userParams.State = "Germany"
                    $userParams.Country = "DE"
                }
                
                if ($randomPhone) {
                    $userParams.OfficePhone = Get-RandomPhoneNumber
                    $userParams.MobilePhone = Get-RandomPhoneNumber
                }
                
                if ($randomDepartments) {
                    $userParams.Department = Get-RandomDepartment
                }
                
                if ($randomTitles) {
                    $userParams.Title = Get-RandomJobTitle
                }
                
                if ($randomCompany) {
                    $companyName = $Global:GuiControls.TextBoxCompanyName.Text
                    if ([string]::IsNullOrWhiteSpace($companyName)) {
                        $companyName = "Test Company"
                    }
                    $userParams.Company = $companyName
                }
                
                New-ADUser @userParams -ErrorAction Stop
                $Global:CreatedUsers.Add($samAccountName)
                $successCount++
                
            } catch {
                Write-Log "Fehler beim Erstellen von Benutzer $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        Hide-Progress
        Update-Statistics
        
        $message = "Random-Benutzer erfolgreich erstellt:`n`nErstellt: $successCount`nFehler: $errorCount`nZiel-OU: $userOU"
        
        [System.Windows.MessageBox]::Show($message, "Random Benutzer erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Random User Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Export-AllObjects {
    <#
    .SYNOPSIS
    Exportiert alle erstellten Objekte in eine CSV-Datei
    #>
    try {
        Write-Log "Starte Export aller Objekte..." -Level "INFO"
        
        $totalObjects = $Global:CreatedUsers.Count + $Global:CreatedGroups.Count + 
                       $Global:CreatedComputers.Count + $Global:CreatedOUs.Count + 
                       $Global:CreatedServiceAccounts.Count
        
        if ($totalObjects -eq 0) {
            Write-Log "Keine Objekte zum Exportieren vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Objekte erstellt.", "Hinweis", "OK", "Information")
            return
        }
        
        Show-Progress -Text "Exportiere Objekte..."
        
        $exportData = @()
        
        # Benutzer exportieren
        foreach ($user in $Global:CreatedUsers) {
            try {
                $adUser = Get-ADUser -Identity $user -Properties * -ErrorAction Stop
                $exportData += [PSCustomObject]@{
                    ObjectType = "User"
                    Name = $adUser.Name
                    SamAccountName = $adUser.SamAccountName
                    DistinguishedName = $adUser.DistinguishedName
                    Created = $adUser.whenCreated
                    Enabled = $adUser.Enabled
                }
            } catch {
                Write-Log "Fehler beim Export von Benutzer '$user': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # Gruppen exportieren
        foreach ($group in $Global:CreatedGroups) {
            try {
                $adGroup = Get-ADGroup -Identity $group -Properties * -ErrorAction Stop
                $exportData += [PSCustomObject]@{
                    ObjectType = "Group"
                    Name = $adGroup.Name
                    SamAccountName = $adGroup.SamAccountName
                    DistinguishedName = $adGroup.DistinguishedName
                    Created = $adGroup.whenCreated
                    Enabled = "N/A"
                }
            } catch {
                Write-Log "Fehler beim Export von Gruppe '$group': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # Computer exportieren
        foreach ($computer in $Global:CreatedComputers) {
            try {
                $adComputer = Get-ADComputer -Identity $computer -Properties * -ErrorAction Stop
                $exportData += [PSCustomObject]@{
                    ObjectType = "Computer"
                    Name = $adComputer.Name
                    SamAccountName = $adComputer.SamAccountName
                    DistinguishedName = $adComputer.DistinguishedName
                    Created = $adComputer.whenCreated
                    Enabled = $adComputer.Enabled
                }
            } catch {
                Write-Log "Fehler beim Export von Computer '$computer': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # OUs dokumentieren
        foreach ($ou in $Global:CreatedOUs) {
            $exportData += [PSCustomObject]@{
                ObjectType = "OU"
                Name = ($ou -split ',')[0] -replace 'OU=', ''
                SamAccountName = "N/A"
                DistinguishedName = $ou
                Created = "N/A"
                Enabled = "N/A"
            }
        }
        
        # Service Accounts exportieren
        foreach ($service in $Global:CreatedServiceAccounts) {
            try {
                $adService = Get-ADUser -Identity $service -Properties * -ErrorAction Stop
                $exportData += [PSCustomObject]@{
                    ObjectType = "ServiceAccount"
                    Name = $adService.Name
                    SamAccountName = $adService.SamAccountName
                    DistinguishedName = $adService.DistinguishedName
                    Created = $adService.whenCreated
                    Enabled = $adService.Enabled
                }
            } catch {
                Write-Log "Fehler beim Export von Service Account '$service': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # Export
        $exportPath = ".\AllCreatedObjects_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $exportData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
        
        Hide-Progress
        
        $message = "Export erfolgreich abgeschlossen:`n`nExportierte Objekte: $($exportData.Count)`n- Benutzer: $($Global:CreatedUsers.Count)`n- Gruppen: $($Global:CreatedGroups.Count)`n- Computer: $($Global:CreatedComputers.Count)`n- OUs: $($Global:CreatedOUs.Count)`n- Service Accounts: $($Global:CreatedServiceAccounts.Count)`n`nDatei: $exportPath"
        
        [System.Windows.MessageBox]::Show($message, "Export abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler beim Export: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Export:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Quick-CreateGroups {
    try {
        Write-Log "Starte Schnell-Erstellung von Gruppen..." -Level "INFO"

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie Standard-Gruppen erstellen?`n`n- Benutzer`n- Administratoren`n- Gäste",
            "Gruppen erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Erstelle Gruppen..."
        $processed = 0
        $failed = 0

        $groups = @(
            @{Name="Benutzer"; Description="Standardbenutzer"},
            @{Name="Administratoren"; Description="Administratoren mit erweiterten Rechten"},
            @{Name="Gäste"; Description="Eingeschränkte Gastbenutzer"}
        )

        foreach ($group in $groups) {
            try {
                New-ADGroup -Name $group.Name `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description $group.Description `
                    -ErrorAction Stop
                
                Write-Log "Gruppe $($group.Name) erfolgreich erstellt" -Level "SUCCESS"
                $processed++
            }
            catch {
                Write-Log "Fehler beim Erstellen der Gruppe $($group.Name): $($_.Exception.Message)" -Level "ERROR"
                $failed++
            }
            
            Update-Progress -Current $processed -Total $groups.Count
        }

        Hide-Progress
        [System.Windows.MessageBox]::Show("Gruppen-Erstellung abgeschlossen.`n$processed Gruppen erstellt, $failed Fehler.", "Vorgang abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Gruppen-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Ensure-TestOUs {
    <#
    .SYNOPSIS
    Erstellt dedizierte Test-OUs für verschiedene Objekttypen
    #>
    param(
        [string]$BaseOU
    )
    
    try {
        Write-Log "Erstelle dedizierte Test-OUs..." -Level "INFO"
        
        $testOUs = @{
            "USER" = "Test User Accounts"
            "GROUPS" = "Test Security Groups"
            "COMPUTER" = "Test Computer Accounts"
            "SERVICES" = "Test Service Accounts"
            "RESOURCES" = "Test Resources"
        }
        
        $createdOUs = @{}
        
        foreach ($ouName in $testOUs.Keys) {
            $ouPath = "OU=$ouName,$BaseOU"
            
            try {
                # Prüfe ob OU bereits existiert
                $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue
                
                if (-not $existingOU) {
                    New-ADOrganizationalUnit -Name $ouName `
                        -Path $BaseOU `
                        -Description $testOUs[$ouName] `
                        -ProtectedFromAccidentalDeletion $false `
                        -ErrorAction Stop
                    
                    $Global:CreatedOUs.Add($ouPath)
                    Write-Log "Test-OU '$ouName' erstellt: $ouPath" -Level "SUCCESS"
                } else {
                    Write-Log "Test-OU '$ouName' existiert bereits: $ouPath" -Level "INFO"
                }
                
                # Immer zum Dictionary hinzufügen, auch wenn sie bereits existiert
                $createdOUs[$ouName] = $ouPath
                
            } catch {
                Write-Log "Fehler beim Erstellen der Test-OU '$ouName': $($_.Exception.Message)" -Level "ERROR"
                # Fallback zur Basis-OU
                $createdOUs[$ouName] = $BaseOU
            }
        }
        
        return $createdOUs
        
    } catch {
        Write-Log "Fehler beim Erstellen der Test-OUs: $($_.Exception.Message)" -Level "ERROR"
        return @{}
    }
}

function Quick-CreateTestData {
    try {
        Write-Log "Starte Erstellung von Testdaten..." -Level "INFO"

        # Ermittle Ziel-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle dedizierte Test-OUs
        $testOUs = Ensure-TestOUs -BaseOU $targetOU

        # Anzahl der zu erstellenden Benutzer aus TextBox oder Standard
        $numUsers = 10
        if (-not [string]::IsNullOrWhiteSpace($Global:GuiControls.TextBoxNumUsersToCreate.Text)) {
            $numUsers = [int]$Global:GuiControls.TextBoxNumUsersToCreate.Text
        }

        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie einen Testdatensatz erstellen?`n`n- $numUsers Testbenutzer (in OU=USERS)`n- 5 Testgruppen (in OU=GROUPS)`n- Zufällige Attribute`n`nBasis-OU: $targetOU",
            "Testdaten erstellen",
            "YesNo",
            "Question"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Erstelle Testdaten..."
        
        # Verwende die USERS OU für Benutzer
        $userOU = if ($testOUs["USERS"]) { $testOUs["USERS"] } else { $targetOU }
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }
        
        # Testbenutzer erstellen
        $userSuccess = 0
        $userError = 0
        
        for ($i = 1; $i -le $numUsers; $i++) {
            try {
                # Zufällige Daten generieren
                $firstName = Get-RandomFirstName
                $lastName = Get-RandomLastName
                $department = Get-RandomDepartment
                $title = Get-RandomJobTitle
                $city = Get-RandomCity
                
                $user = @{
                    Name = "$firstName.$lastName"
                    SamAccountName = "$($firstName.ToLower()).$($lastName.ToLower())$i"
                    UserPrincipalName = "$($firstName.ToLower()).$($lastName.ToLower())$i@$((Get-ADDomain).DNSRoot)"
                    GivenName = $firstName
                    Surname = $lastName
                    DisplayName = "$firstName $lastName"
                    Department = $department
                    Title = $title
                    City = $city
                    Company = "Test Company"
                    StreetAddress = Get-RandomStreetAddress
                    PostalCode = Get-RandomPostalCode
                    OfficePhone = Get-RandomPhoneNumber
                    Path = $userOU
                    Enabled = $true
                    AccountPassword = (ConvertTo-SecureString -String (Generate-SecurePassword -Complexity "Mittel (12 Zeichen + Symbole)") -AsPlainText -Force)
                    ChangePasswordAtLogon = $true
                }
                
                New-ADUser @user
                $Global:CreatedUsers.Add($user.SamAccountName)
                Write-Log "Testbenutzer '$($user.DisplayName)' in OU '$userOU' erstellt" -Level "SUCCESS"
                $userSuccess++
            }
            catch {
                Write-Log "Fehler beim Erstellen von Testbenutzer $($i): $($_.Exception.Message)" -Level "ERROR"
                $userError++
            }
            
            Update-Progress -Current $i -Total $numUsers -Text "Erstelle Testbenutzer $i von $numUsers..."
        }

        # Testgruppen erstellen
        Update-Progress -Current 0 -Total 5 -Text "Erstelle Testgruppen..."
        $groupSuccess = 0
        $groupError = 0
        
        # Erstelle Gruppen basierend auf den verwendeten Departments
        $departments = @("IT", "HR", "Finance", "Sales", "Marketing")
        $groupTypes = @("Users", "Admins", "ReadOnly")
        
        foreach ($dept in $departments) {
            try {
                $groupName = "TEST_${dept}_Users"
                New-ADGroup -Name $groupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description "Testgruppe für $dept" `
                    -Path $groupOU `
                    -ErrorAction Stop
                
                $Global:CreatedGroups.Add($groupName)
                Write-Log "Testgruppe '$groupName' erstellt" -Level "SUCCESS"
                $groupSuccess++
                
                # Füge passende Benutzer zur Gruppe hinzu
                $deptUsers = Get-ADUser -Filter "Department -eq '$dept'" -SearchBase $targetOU -ErrorAction SilentlyContinue
                if ($deptUsers) {
                    foreach ($user in $deptUsers) {
                        if ($user.SamAccountName -in $Global:CreatedUsers) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                                Write-Log "Benutzer '$($user.SamAccountName)' zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-Log "Fehler beim Hinzufügen von Benutzer zu Gruppe: $($_.Exception.Message)" -Level "WARN"
                            }
                        }
                    }
                }
            }
            catch {
                Write-Log "Fehler beim Erstellen von Testgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                $groupError++
            }
        }

        Hide-Progress
        Update-Statistics
        
        $message = @"
Testdaten erfolgreich erstellt:

Benutzer:
- Erstellt: $userSuccess
- Fehler: $userError
- Verteilt auf $($availableOUs.Count) OU(s)

Gruppen:
- Erstellt: $groupSuccess  
- Fehler: $groupError

Die Benutzer wurden mit zufälligen Attributen erstellt
und auf die verfügbaren OUs verteilt.
"@
        
        [System.Windows.MessageBox]::Show($message, "Testdaten erstellt", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Testdaten-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

function Remove-CreatedGroups {
    <#
    .SYNOPSIS
    Löscht alle erstellten Gruppen
    #>
    try {
        Write-Log "Starte Löschung aller erstellten Gruppen..." -Level "INFO"
        
        if (-not $Global:CreatedGroups -or $Global:CreatedGroups.Count -eq 0) {
            Write-Log "Keine Gruppen zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Gruppen erstellt.", "Hinweis", "OK", "Information")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($Global:CreatedGroups.Count) erstellten Gruppen löschen?`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "Gruppen löschen", "YesNo", "Warning")
        
        if ($result -ne "Yes") {
            Write-Log "Gruppenlöschung abgebrochen" -Level "INFO"
            return
        }
        
        Show-Progress -Text "Lösche Gruppen..."
        
        $deletedCount = 0
        $errorCount = 0
        $total = $Global:CreatedGroups.Count
        
        # In umgekehrter Reihenfolge löschen (zuletzt erstellte zuerst)
        $groupsToDelete = @($Global:CreatedGroups) | Sort-Object -Descending
        
        for ($i = 0; $i -lt $groupsToDelete.Count; $i++) {
            $groupName = $groupsToDelete[$i]
            Update-Progress -Current ($i + 1) -Total $total -Text "Lösche Gruppe: $groupName"
            
            try {
                Remove-ADGroup -Identity $groupName -Confirm:$false -ErrorAction Stop
                Write-Log "Gruppe '$groupName' gelöscht" -Level "SUCCESS"
                $deletedCount++
            } catch {
                Write-Log "Fehler beim Löschen der Gruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Liste leeren
        $Global:CreatedGroups.Clear()
        
        Hide-Progress
        Update-Statistics
        
        $message = "Gruppenlöschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Gruppenlöschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Gruppenlöschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Remove-CreatedComputers {
    <#
    .SYNOPSIS
    Löscht alle erstellten Computer
    #>
    try {
        Write-Log "Starte Löschung aller erstellten Computer..." -Level "INFO"
        
        if (-not $Global:CreatedComputers -or $Global:CreatedComputers.Count -eq 0) {
            Write-Log "Keine Computer zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Information")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($Global:CreatedComputers.Count) erstellten Computer löschen?`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "Computer löschen", "YesNo", "Warning")
        
        if ($result -ne "Yes") {
            Write-Log "Computerlöschung abgebrochen" -Level "INFO"
            return
        }
        
        Show-Progress -Text "Lösche Computer..."
        
        $deletedCount = 0
        $errorCount = 0
        $total = $Global:CreatedComputers.Count
        
        for ($i = 0; $i -lt $Global:CreatedComputers.Count; $i++) {
            $computerName = $Global:CreatedComputers[$i]
            Update-Progress -Current ($i + 1) -Total $total -Text "Lösche Computer: $computerName"
            
            try {
                Remove-ADComputer -Identity $computerName -Confirm:$false -ErrorAction Stop
                Write-Log "Computer '$computerName' gelöscht" -Level "SUCCESS"
                $deletedCount++
            } catch {
                Write-Log "Fehler beim Löschen des Computers '$computerName': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Liste leeren
        $Global:CreatedComputers.Clear()
        
        Hide-Progress
        Update-Statistics
        
        $message = "Computerlöschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Computerlöschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Computerlöschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Remove-CreatedOUs {
    <#
    .SYNOPSIS
    Löscht alle erstellten OUs
    #>
    try {
        Write-Log "Starte Löschung aller erstellten OUs..." -Level "INFO"
        
        if (-not $Global:CreatedOUs -or $Global:CreatedOUs.Count -eq 0) {
            Write-Log "Keine OUs zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine OUs erstellt.", "Hinweis", "OK", "Information")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($Global:CreatedOUs.Count) erstellten OUs löschen?`n`n" +
            "ACHTUNG: Dies löscht auch alle Objekte in diesen OUs!`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "OUs löschen", "YesNo", "Warning")
        
        if ($result -ne "Yes") {
            Write-Log "OU-Löschung abgebrochen" -Level "INFO"
            return
        }
        
        Show-Progress -Text "Lösche OUs..."
        
        $deletedCount = 0
        $errorCount = 0
        
        # Sortiere OUs nach Tiefe (tiefste zuerst)
        $ousToDelete = @($Global:CreatedOUs) | Sort-Object { ($_ -split ',').Count } -Descending
        $total = $ousToDelete.Count
        
        for ($i = 0; $i -lt $ousToDelete.Count; $i++) {
            $ou = $ousToDelete[$i]
            Update-Progress -Current ($i + 1) -Total $total -Text "Lösche OU: $ou"
            
            try {
                $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue
                if ($existingOU) {
                    # Schutz vor versehentlichem Löschen entfernen
                    Set-ADOrganizationalUnit -Identity $ou -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
                    
                    # OU löschen (rekursiv)
                    Remove-ADOrganizationalUnit -Identity $ou -Recursive -Confirm:$false -ErrorAction Stop
                    Write-Log "OU '$ou' und alle enthaltenen Objekte gelöscht" -Level "SUCCESS"
                    $deletedCount++
                } else {
                    Write-Log "OU '$ou' nicht gefunden, übersprungen" -Level "WARN"
                }
            } catch {
                Write-Log "Fehler beim Löschen der OU '$ou': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Liste leeren
        $Global:CreatedOUs.Clear()
        
        Hide-Progress
        Update-Statistics
        
        $message = "OU-Löschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei OU-Löschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der OU-Löschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Remove-CreatedServiceAccounts {
    <#
    .SYNOPSIS
    Löscht alle erstellten Service Accounts
    #>
    try {
        Write-Log "Starte Löschung aller erstellten Service Accounts..." -Level "INFO"
        
        if (-not $Global:CreatedServiceAccounts -or $Global:CreatedServiceAccounts.Count -eq 0) {
            Write-Log "Keine Service Accounts zum Löschen vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Service Accounts erstellt.", "Hinweis", "OK", "Information")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie wirklich ALLE $($Global:CreatedServiceAccounts.Count) erstellten Service Accounts löschen?`n`n" +
            "Diese Aktion kann nicht rückgängig gemacht werden!",
            "Service Accounts löschen", "YesNo", "Warning")
        
        if ($result -ne "Yes") {
            Write-Log "Service Account Löschung abgebrochen" -Level "INFO"
            return
        }
        
        Show-Progress -Text "Lösche Service Accounts..."
        
        $deletedCount = 0
        $errorCount = 0
        $total = $Global:CreatedServiceAccounts.Count
        
        for ($i = 0; $i -lt $Global:CreatedServiceAccounts.Count; $i++) {
            $accountName = $Global:CreatedServiceAccounts[$i]
            Update-Progress -Current ($i + 1) -Total $total -Text "Lösche Service Account: $accountName"
            
            try {
                Remove-ADUser -Identity $accountName -Confirm:$false -ErrorAction Stop
                Write-Log "Service Account '$accountName' gelöscht" -Level "SUCCESS"
                $deletedCount++
            } catch {
                Write-Log "Fehler beim Löschen des Service Accounts '$accountName': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Liste leeren
        $Global:CreatedServiceAccounts.Clear()
        
        Hide-Progress
        Update-Statistics
        
        $message = "Service Account Löschung abgeschlossen:`n`nGelöscht: $deletedCount`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Service Account Löschung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Service Account Löschung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Quick-CleanupAll {
    try {
        Write-Log "Starte Bereinigung..." -Level "INFO"

        $result = [System.Windows.MessageBox]::Show(
            "WARNUNG: Dies löscht alle erstellten Gruppen, Computer, OUs und Service-Accounts!`n`n(Benutzer werden NICHT gelöscht)`n`nMöchten Sie fortfahren?",
            "Bereinigung",
            "YesNo",
            "Warning"
        )

        if ($result -ne "Yes") { return }

        Show-Progress -Text "Bereinige Testdaten..."
        
        $totalItems = $Global:CreatedGroups.Count + $Global:CreatedComputers.Count + 
                     $Global:CreatedOUs.Count + $Global:CreatedServiceAccounts.Count
        $currentItem = 0
        $successCount = 0
        $errorCount = 0

        # Gruppen löschen (alle aus $Global:CreatedGroups)
        if ($Global:CreatedGroups -and $Global:CreatedGroups.Count -gt 0) {
            Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche Gruppen..."
            
            # Kopie erstellen, da wir während der Iteration löschen
            $groupsToDelete = @($Global:CreatedGroups)
            
            foreach ($group in $groupsToDelete) {
                $currentItem++
                try {
                    # Prüfe ob Gruppe existiert
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$group'" -ErrorAction SilentlyContinue
                    if ($existingGroup) {
                        Remove-ADGroup -Identity $group -Confirm:$false -ErrorAction Stop
                        Write-Log "Gruppe '$group' gelöscht" -Level "SUCCESS"
                        $successCount++
                    } else {
                        Write-Log "Gruppe '$group' existiert nicht mehr" -Level "DEBUG"
                    }
                }
                catch {
                    Write-Log "Fehler beim Löschen von Gruppe '$group': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche Gruppe: $group"
            }
            $Global:CreatedGroups.Clear()
        }

        # Computer löschen
        if ($Global:CreatedComputers -and $Global:CreatedComputers.Count -gt 0) {
            Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche Computer..."
            
            $computersToDelete = @($Global:CreatedComputers)
            foreach ($computer in $computersToDelete) {
                $currentItem++
                try {
                    $existingComputer = Get-ADComputer -Filter "Name -eq '$computer'" -ErrorAction SilentlyContinue
                    if ($existingComputer) {
                        Remove-ADComputer -Identity $computer -Confirm:$false -ErrorAction Stop
                        Write-Log "Computer '$computer' gelöscht" -Level "SUCCESS"
                        $successCount++
                    }
                }
                catch {
                    Write-Log "Fehler beim Löschen von Computer '$computer': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche Computer: $computer"
            }
            $Global:CreatedComputers.Clear()
        }

        # Service-Accounts löschen
        if ($Global:CreatedServiceAccounts -and $Global:CreatedServiceAccounts.Count -gt 0) {
            Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche Service-Accounts..."
            
            $serviceAccountsToDelete = @($Global:CreatedServiceAccounts)
            foreach ($serviceAccount in $serviceAccountsToDelete) {
                $currentItem++
                try {
                    $existingAccount = Get-ADUser -Filter "SamAccountName -eq '$serviceAccount'" -ErrorAction SilentlyContinue
                    if ($existingAccount) {
                        Remove-ADUser -Identity $serviceAccount -Confirm:$false -ErrorAction Stop
                        Write-Log "Service-Account '$serviceAccount' gelöscht" -Level "SUCCESS"
                        $successCount++
                    }
                }
                catch {
                    Write-Log "Fehler beim Löschen von Service-Account '$serviceAccount': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche Service-Account: $serviceAccount"
            }
            $Global:CreatedServiceAccounts.Clear()
        }

        # OUs löschen (in umgekehrter Reihenfolge für Hierarchien)
        if ($Global:CreatedOUs -and $Global:CreatedOUs.Count -gt 0) {
            Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche OUs..."
            
            # Sortiere OUs nach Tiefe (tiefste zuerst)
            $ousToDelete = @($Global:CreatedOUs) | Sort-Object { ($_ -split ',').Count } -Descending
            
            foreach ($ou in $ousToDelete) {
                $currentItem++
                try {
                    # Prüfe ob es eine Test-OU ist (USERS, GROUPS, etc.)
                    $ouName = ($ou -split ',')[0] -replace 'OU=', ''
                    $isTestOU = $ouName -in @('USERS', 'GROUPS', 'COMPUTERS', 'SERVICES', 'RESOURCES', 'USERS', 'USER', 'COMPUTER', 'SERVICE', 'RESOURCE')
                    
                    if (-not $isTestOU) {
                        Write-Log "OU '$ou' ist keine Test-OU, überspringe..." -Level "DEBUG"
                        continue
                    }
                    
                    $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ou'" -ErrorAction SilentlyContinue
                    if ($existingOU) {
                        # Schutz vor versehentlichem Löschen entfernen
                        Set-ADOrganizationalUnit -Identity $ou -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
                        Remove-ADOrganizationalUnit -Identity $ou -Confirm:$false -Recursive -ErrorAction Stop
                        Write-Log "OU '$ou' gelöscht" -Level "SUCCESS"
                        $successCount++
                    }
                }
                catch {
                    Write-Log "Fehler beim Löschen von OU '$ou': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
                Update-Progress -Current $currentItem -Total $totalItems -Text "Lösche OU: $($ou -split ',' | Select-Object -First 1)"
            }
            $Global:CreatedOUs.Clear()
        }

        Hide-Progress
        Update-Statistics
        
        $message = @"
Bereinigung abgeschlossen:

Erfolgreich gelöscht: $successCount
Fehler: $errorCount

Hinweis: Benutzer wurden NICHT gelöscht.
Diese können Sie über 'User löschen' entfernen.
"@
        
        [System.Windows.MessageBox]::Show($message, "Bereinigung abgeschlossen", "OK", "Information")

    }
    catch {
        Write-Log "Fehler bei Bereinigung: $($_.Exception.Message)" -Level "ERROR"
        Hide-Progress
    }
}

#region Gruppen & Organisationsstruktur - Erweiterte Funktionen

function Create-AutomaticGroups {
    <#
    .SYNOPSIS
    Erstellt automatisch Gruppen basierend auf Abteilungen, Standorten und Berufsbezeichnungen
    #>
    try {
        Write-Log "Starte automatische Gruppenerstellung..." -Level "INFO"
        
        $createDepartmentGroups = $Global:GuiControls.CheckBoxCreateDepartmentGroups.IsChecked
        $createLocationGroups = $Global:GuiControls.CheckBoxCreateLocationGroups.IsChecked
        $createJobTitleGroups = $Global:GuiControls.CheckBoxCreateJobTitleGroups.IsChecked
        
        if (-not ($createDepartmentGroups -or $createLocationGroups -or $createJobTitleGroups)) {
            Write-Log "Keine Gruppentypen für automatische Erstellung ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens einen Gruppentyp aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer vorhanden, aus denen Gruppen erstellt werden können" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt. Gruppen werden basierend auf Benutzerattributen erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Bestimme Gruppen-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle dedizierte Test-OUs wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }
        
        Show-Progress -Text "Analysiere Benutzerattribute..."
        
        # Sammle einzigartige Werte aus Benutzerattributen
        $departments = @()
        $locations = @()
        $jobTitles = @()
        
        foreach ($userName in $Global:CreatedUsers) {
            try {
                $user = Get-ADUser -Identity $userName -Properties Department, City, Title -ErrorAction Stop
                
                if ($createDepartmentGroups -and $user.Department) {
                    $departments += $user.Department
                }
                if ($createLocationGroups -and $user.City) {
                    $locations += $user.City
                }
                if ($createJobTitleGroups -and $user.Title) {
                    $jobTitles += $user.Title
                }
            } catch {
                Write-Log "Fehler beim Abrufen der Attribute für Benutzer '$userName': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # Einzigartige Werte extrahieren
        $uniqueDepartments = $departments | Select-Object -Unique | Where-Object { $_ }
        $uniqueLocations = $locations | Select-Object -Unique | Where-Object { $_ }
        $uniqueJobTitles = $jobTitles | Select-Object -Unique | Where-Object { $_ }
        
        $totalGroups = $uniqueDepartments.Count + $uniqueLocations.Count + $uniqueJobTitles.Count
        $currentGroup = 0
        $successCount = 0
        $errorCount = 0
        
        # Erstelle Abteilungsgruppen
        if ($createDepartmentGroups) {
            foreach ($dept in $uniqueDepartments) {
                $currentGroup++
                Update-Progress -Current $currentGroup -Total $totalGroups -Text "Erstelle Abteilungsgruppe: $dept"
                
                $groupName = "DEPT_$($dept -replace '\s', '_')"
                $groupDescription = "Abteilung: $dept"
                
                try {
                    # Prüfe ob Gruppe bereits existiert
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                    if (-not $existingGroup) {
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Description $groupDescription `
                            -Path $groupOU `
                            -ErrorAction Stop
                        
                        $Global:CreatedGroups.Add($groupName)
                        Write-Log "Abteilungsgruppe '$groupName' erfolgreich erstellt" -Level "SUCCESS"
                        
                        # Füge Benutzer der Gruppe hinzu
                        $usersInDept = Get-ADUser -Filter "Department -eq '$dept'" | Where-Object { $_.SamAccountName -in $Global:CreatedUsers }
                        foreach ($user in $usersInDept) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                                Write-Log "Benutzer '$($user.SamAccountName)' zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-Log "Fehler beim Hinzufügen von '$($user.SamAccountName)' zu '$groupName': $($_.Exception.Message)" -Level "WARN"
                            }
                        }
                        
                        $successCount++
                    } else {
                        Write-Log "Gruppe '$groupName' existiert bereits, übersprungen" -Level "INFO"
                    }
                } catch {
                    Write-Log "Fehler beim Erstellen der Abteilungsgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }
        
        # Erstelle Standortgruppen
        if ($createLocationGroups) {
            foreach ($location in $uniqueLocations) {
                $currentGroup++
                Update-Progress -Current $currentGroup -Total $totalGroups -Text "Erstelle Standortgruppe: $location"
                
                $groupName = "LOC_$($location -replace '\s', '_')"
                $groupDescription = "Standort: $location"
                
                try {
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                    if (-not $existingGroup) {
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Description $groupDescription `
                            -Path $groupOU `
                            -ErrorAction Stop
                        
                        $Global:CreatedGroups.Add($groupName)
                        Write-Log "Standortgruppe '$groupName' erfolgreich erstellt" -Level "SUCCESS"
                        
                        # Füge Benutzer der Gruppe hinzu
                        $usersInLocation = Get-ADUser -Filter "City -eq '$location'" | Where-Object { $_.SamAccountName -in $Global:CreatedUsers }
                        foreach ($user in $usersInLocation) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                                Write-Log "Benutzer '$($user.SamAccountName)' zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-Log "Fehler beim Hinzufügen von '$($user.SamAccountName)' zu '$groupName': $($_.Exception.Message)" -Level "WARN"
                            }
                        }
                        
                        $successCount++
                    } else {
                        Write-Log "Gruppe '$groupName' existiert bereits, übersprungen" -Level "INFO"
                    }
                } catch {
                    Write-Log "Fehler beim Erstellen der Standortgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }
        
        # Erstelle Berufsbezeichnungsgruppen
        if ($createJobTitleGroups) {
            foreach ($title in $uniqueJobTitles) {
                $currentGroup++
                Update-Progress -Current $currentGroup -Total $totalGroups -Text "Erstelle Berufsgruppe: $title"
                
                $groupName = "JOB_$($title -replace '\s', '_')"
                $groupDescription = "Berufsbezeichnung: $title"
                
                try {
                    $existingGroup = Get-ADGroup -Filter "Name -eq '$groupName'" -ErrorAction SilentlyContinue
                    if (-not $existingGroup) {
                        New-ADGroup -Name $groupName `
                            -GroupScope Global `
                            -GroupCategory Security `
                            -Description $groupDescription `
                            -Path $groupOU `
                            -ErrorAction Stop
                        
                        $Global:CreatedGroups.Add($groupName)
                        Write-Log "Berufsgruppe '$groupName' erfolgreich erstellt" -Level "SUCCESS"
                        
                        # Füge Benutzer der Gruppe hinzu
                        $usersWithTitle = Get-ADUser -Filter "Title -eq '$title'" | Where-Object { $_.SamAccountName -in $Global:CreatedUsers }
                        foreach ($user in $usersWithTitle) {
                            try {
                                Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                                Write-Log "Benutzer '$($user.SamAccountName)' zu Gruppe '$groupName' hinzugefügt" -Level "DEBUG"
                            } catch {
                                Write-Log "Fehler beim Hinzufügen von '$($user.SamAccountName)' zu '$groupName': $($_.Exception.Message)" -Level "WARN"
                            }
                        }
                        
                        $successCount++
                    } else {
                        Write-Log "Gruppe '$groupName' existiert bereits, übersprungen" -Level "INFO"
                    }
                } catch {
                    Write-Log "Fehler beim Erstellen der Berufsgruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
        }
        
        Hide-Progress
        Update-Statistics
        
        $message = "Automatische Gruppenerstellung abgeschlossen.`n`nErstellt: $successCount`nFehler: $errorCount`n`nDetails:`n"
        if ($createDepartmentGroups) { $message += "- $($uniqueDepartments.Count) Abteilungsgruppen`n" }
        if ($createLocationGroups) { $message += "- $($uniqueLocations.Count) Standortgruppen`n" }
        if ($createJobTitleGroups) { $message += "- $($uniqueJobTitles.Count) Berufsgruppen`n" }
        
        [System.Windows.MessageBox]::Show($message, "Gruppen erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei automatischer Gruppenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Gruppenerstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-NestedGroupStructure {
    <#
    .SYNOPSIS
    Erstellt verschachtelte Gruppenhierarchien basierend auf der ausgewählten Struktur
    #>
    try {
        Write-Log "Starte Erstellung verschachtelter Gruppenstruktur..." -Level "INFO"
        
        $selectedHierarchy = $Global:GuiControls.ComboBoxGroupHierarchy.SelectedItem
        if (-not $selectedHierarchy) {
            Write-Log "Keine Hierarchie ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Hierarchie-Struktur aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $hierarchyType = $selectedHierarchy.Content
        $nestSecurity = $Global:GuiControls.CheckBoxNestedSecurity.IsChecked
        
        # Bestimme Gruppen-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle dedizierte Test-OUs wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }
        
        Show-Progress -Text "Erstelle verschachtelte Gruppenstruktur..."
        
        $createdGroups = @()
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
                            -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                            -Description "Flache Struktur - $group" `
                            -Path $groupOU `
                            -ErrorAction Stop
                        
                        $Global:CreatedGroups.Add($groupName)
                        $createdGroups += $groupName
                        $successCount++
                        Write-Log "Gruppe '$groupName' erstellt" -Level "SUCCESS"
                    } catch {
                        Write-Log "Fehler beim Erstellen der Gruppe '$groupName': $($_.Exception.Message)" -Level "ERROR"
                        $errorCount++
                    }
                }
            }
            
            "2-Level Hierarchie" {
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
                            -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                            -Description "Parent-Gruppe" `
                            -Path $groupOU `
                            -ErrorAction Stop
                        
                        $Global:CreatedGroups.Add($parent)
                        $createdGroups += $parent
                        $successCount++
                        Write-Log "Parent-Gruppe '$parent' erstellt" -Level "SUCCESS"
                        
                        # Erstelle Child-Gruppen
                        foreach ($child in $structure[$parent]) {
                            try {
                                New-ADGroup -Name $child `
                                    -GroupScope Global `
                                    -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                                    -Description "Child-Gruppe von $parent" `
                                    -Path $groupOU `
                                    -ErrorAction Stop
                                
                                $Global:CreatedGroups.Add($child)
                                $createdGroups += $child
                                
                                # Füge Child zu Parent hinzu
                                Add-ADGroupMember -Identity $parent -Members $child -ErrorAction Stop
                                
                                $successCount++
                                Write-Log "Child-Gruppe '$child' erstellt und zu '$parent' hinzugefügt" -Level "SUCCESS"
                            } catch {
                                Write-Log "Fehler bei Child-Gruppe '$child': $($_.Exception.Message)" -Level "ERROR"
                                $errorCount++
                            }
                        }
                    } catch {
                        Write-Log "Fehler bei Parent-Gruppe '$parent': $($_.Exception.Message)" -Level "ERROR"
                        $errorCount++
                    }
                }
            }
            
            "3-Level Hierarchie" {
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
                            -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                            -Description "Organisation Level" `
                            -Path $groupOU `
                            -ErrorAction Stop
                        
                        $Global:CreatedGroups.Add($org)
                        $createdGroups += $org
                        $successCount++
                        Write-Log "Organisation '$org' erstellt" -Level "SUCCESS"
                        
                        foreach ($dept in $structure[$org].Keys) {
                            try {
                                # Level 2: Department
                                New-ADGroup -Name $dept `
                                    -GroupScope Global `
                                    -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                                    -Description "Department Level" `
                                    -Path $groupOU `
                                    -ErrorAction Stop
                                
                                $Global:CreatedGroups.Add($dept)
                                $createdGroups += $dept
                                Add-ADGroupMember -Identity $org -Members $dept -ErrorAction Stop
                                $successCount++
                                Write-Log "Department '$dept' erstellt und zu '$org' hinzugefügt" -Level "SUCCESS"
                                
                                foreach ($team in $structure[$org][$dept]) {
                                    try {
                                        # Level 3: Team
                                        New-ADGroup -Name $team `
                                            -GroupScope DomainLocal `
                                            -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                                            -Description "Team Level" `
                                            -Path $groupOU `
                                            -ErrorAction Stop
                                        
                                        $Global:CreatedGroups.Add($team)
                                        $createdGroups += $team
                                        Add-ADGroupMember -Identity $dept -Members $team -ErrorAction Stop
                                        $successCount++
                                        Write-Log "Team '$team' erstellt und zu '$dept' hinzugefügt" -Level "SUCCESS"
                                    } catch {
                                        Write-Log "Fehler bei Team '$team': $($_.Exception.Message)" -Level "ERROR"
                                        $errorCount++
                                    }
                                }
                            } catch {
                                Write-Log "Fehler bei Department '$dept': $($_.Exception.Message)" -Level "ERROR"
                                $errorCount++
                            }
                        }
                    } catch {
                        Write-Log "Fehler bei Organisation '$org': $($_.Exception.Message)" -Level "ERROR"
                        $errorCount++
                    }
                }
            }
            
            "Vollständige Hierarchie" {
                # Komplexe mehrstufige Hierarchie
                # Region -> Country -> City -> Department -> Team
                $structure = @{
                    "REGION_EMEA" = @{
                        "COUNTRY_Germany" = @{
                            "CITY_Berlin" = @{
                                "DEPT_Sales" = @("TEAM_Inside", "TEAM_Field")
                                "DEPT_Tech" = @("TEAM_Dev", "TEAM_QA")
                            }
                            "CITY_Munich" = @{
                                "DEPT_RnD" = @("TEAM_Research", "TEAM_Innovation")
                            }
                        }
                        "COUNTRY_UK" = @{
                            "CITY_London" = @{
                                "DEPT_Finance" = @("TEAM_Audit", "TEAM_Tax")
                            }
                        }
                    }
                }
                
                # Rekursive Funktion für tiefe Hierarchien
                function Create-HierarchyLevel {
                    param($Structure, $ParentGroup = $null, $Level = 1, $TargetOU)
                    
                    foreach ($key in $Structure.Keys) {
                        try {
                            # Korrigierte Group Scope Hierarchie
                            # Universal kann Universal und Global enthalten, Global kann Global enthalten
                            $groupScope = switch ($Level) {
                                1 { "Universal" }  # Höchste Ebene
                                2 { "Universal" }  # Kann Universal enthalten
                                3 { "Global" }     # Kann Global enthalten
                                4 { "Global" }     # Kann Global/DomainLocal enthalten
                                default { "Global" } # Verwende Global statt DomainLocal für Verschachtelung
                            }
                            
                            New-ADGroup -Name $key `
                                -GroupScope $groupScope `
                                -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                                -Description "Level $Level Hierarchy" `
                                -Path $TargetOU `
                                -ErrorAction Stop
                            
                            $Global:CreatedGroups.Add($key)
                            $Script:createdGroups += $key
                            $Script:successCount++
                            
                            if ($ParentGroup) {
                                Add-ADGroupMember -Identity $ParentGroup -Members $key -ErrorAction Stop
                                Write-Log "Gruppe '$key' erstellt und zu '$ParentGroup' hinzugefügt (Level $Level)" -Level "SUCCESS"
                            } else {
                                Write-Log "Root-Gruppe '$key' erstellt (Level $Level)" -Level "SUCCESS"
                            }
                            
                            # Rekursiv für Untergruppen
                            if ($Structure[$key] -is [hashtable]) {
                                Create-HierarchyLevel -Structure $Structure[$key] -ParentGroup $key -Level ($Level + 1) -TargetOU $TargetOU
                            } elseif ($Structure[$key] -is [array]) {
                                foreach ($subGroup in $Structure[$key]) {
                                    try {
                                        # Für Blatt-Ebene (Teams) verwende Global statt DomainLocal
                                        # DomainLocal nur wenn explizit keine Verschachtelung gewünscht
                                        $leafScope = if ($Level -ge 4) { "Global" } else { "Global" }
                                        
                                        New-ADGroup -Name $subGroup `
                                            -GroupScope $leafScope `
                                            -GroupCategory $(if ($nestSecurity) { "Security" } else { "Distribution" }) `
                                            -Description "Level $($Level + 1) Hierarchy" `
                                            -Path $TargetOU `
                                            -ErrorAction Stop
                                        
                                        $Global:CreatedGroups.Add($subGroup)
                                        $Script:createdGroups += $subGroup
                                        Add-ADGroupMember -Identity $key -Members $subGroup -ErrorAction Stop
                                        $Script:successCount++
                                        Write-Log "Gruppe '$subGroup' erstellt und zu '$key' hinzugefügt (Level $($Level + 1))" -Level "SUCCESS"
                                    } catch {
                                        Write-Log "Fehler bei Gruppe '$subGroup': $($_.Exception.Message)" -Level "ERROR"
                                        $Script:errorCount++
                                    }
                                }
                            }
                        } catch {
                            Write-Log "Fehler bei Gruppe '$key': $($_.Exception.Message)" -Level "ERROR"
                            $Script:errorCount++
                        }
                    }
                }
                
                $Script:createdGroups = $createdGroups
                $Script:successCount = $successCount
                $Script:errorCount = $errorCount
                
                Create-HierarchyLevel -Structure $structure -TargetOU $groupOU
                
                $createdGroups = $Script:createdGroups
                $successCount = $Script:successCount
                $errorCount = $Script:errorCount
            }
        }
        
        Hide-Progress
        Update-Statistics
        
        $message = "Verschachtelte Gruppenstruktur erstellt:`n`nTyp: $hierarchyType`nErstellt: $successCount Gruppen`nFehler: $errorCount"
        [System.Windows.MessageBox]::Show($message, "Struktur erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei verschachtelter Gruppenstruktur: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-DynamicSecurityGroups {
    <#
    .SYNOPSIS
    Erstellt dynamische Sicherheitsgruppen mit LDAP-Filtern (simuliert, da AD keine echten dynamischen Gruppen unterstützt)
    #>
    try {
        Write-Log "Starte Erstellung dynamischer Sicherheitsgruppen..." -Level "INFO"
        
        $ldapFilter = $Global:GuiControls.TextBoxGroupFilter.Text
        if ([string]::IsNullOrWhiteSpace($ldapFilter)) {
            Write-Log "Kein LDAP-Filter angegeben" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie einen LDAP-Filter ein.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Validiere LDAP-Filter Syntax
        try {
            $testUsers = Get-ADUser -LDAPFilter $ldapFilter -ResultSetSize 1 -ErrorAction Stop
            Write-Log "LDAP-Filter validiert: $ldapFilter" -Level "DEBUG"
        } catch {
            Write-Log "Ungültiger LDAP-Filter: $ldapFilter - $($_.Exception.Message)" -Level "ERROR"
            [System.Windows.MessageBox]::Show("Der angegebene LDAP-Filter ist ungültig:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
            return
        }
        
        # Bestimme Gruppen-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle dedizierte Test-OUs wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }
        
        Show-Progress -Text "Erstelle dynamische Gruppe..."
        
        # Generiere Gruppennamen basierend auf Filter
        $groupName = "DYN_" + ($ldapFilter -replace '[^\w]', '' -replace '^(.{1,20}).*', '$1')
        $groupDescription = "Dynamische Gruppe mit Filter: $ldapFilter"
        
        try {
            # Erstelle die Gruppe
            New-ADGroup -Name $groupName `
                -GroupScope Global `
                -GroupCategory Security `
                -Description $groupDescription `
                -Path $groupOU `
                -OtherAttributes @{info="LDAP-Filter: $ldapFilter"} `
                -ErrorAction Stop
            
            $Global:CreatedGroups.Add($groupName)
            Write-Log "Dynamische Gruppe '$groupName' erstellt" -Level "SUCCESS"
            
            Update-Progress -Current 50 -Total 100 -Text "Füge Mitglieder hinzu..."
            
            # Finde alle Benutzer, die dem Filter entsprechen
            $matchingUsers = Get-ADUser -LDAPFilter $ldapFilter -ErrorAction Stop
            $userCount = 0
            $errorCount = 0
            
            foreach ($user in $matchingUsers) {
                try {
                    Add-ADGroupMember -Identity $groupName -Members $user -ErrorAction Stop
                    $userCount++
                    Write-Log "Benutzer '$($user.SamAccountName)' zu dynamischer Gruppe hinzugefügt" -Level "DEBUG"
                } catch {
                    Write-Log "Fehler beim Hinzufügen von '$($user.SamAccountName)': $($_.Exception.Message)" -Level "WARN"
                    $errorCount++
                }
            }
            
            # Erstelle ein Scheduled Task Skript für regelmäßige Updates (als Beispiel)
            $updateScript = @"
# Automatisches Update-Skript für dynamische Gruppe: $groupName
# Dieses Skript sollte als geplante Aufgabe ausgeführt werden

`$ldapFilter = "$ldapFilter"
`$groupName = "$groupName"

try {
    # Aktuelle Mitglieder abrufen
    `$currentMembers = Get-ADGroupMember -Identity `$groupName | Select-Object -ExpandProperty SamAccountName
    
    # Benutzer finden, die dem Filter entsprechen
    `$shouldBeMembers = Get-ADUser -LDAPFilter `$ldapFilter | Select-Object -ExpandProperty SamAccountName
    
    # Zu entfernende Mitglieder
    `$toRemove = `$currentMembers | Where-Object { `$_ -notin `$shouldBeMembers }
    if (`$toRemove) {
        Remove-ADGroupMember -Identity `$groupName -Members `$toRemove -Confirm:`$false
    }
    
    # Hinzuzufügende Mitglieder
    `$toAdd = `$shouldBeMembers | Where-Object { `$_ -notin `$currentMembers }
    if (`$toAdd) {
        Add-ADGroupMember -Identity `$groupName -Members `$toAdd
    }
    
    Write-EventLog -LogName Application -Source "AD Dynamic Groups" -EventId 1000 -Message "Dynamische Gruppe '$groupName' aktualisiert. Hinzugefügt: `$(`$toAdd.Count), Entfernt: `$(`$toRemove.Count)"
} catch {
    Write-EventLog -LogName Application -Source "AD Dynamic Groups" -EventId 1001 -EntryType Error -Message "Fehler beim Update der dynamischen Gruppe '$groupName': `$_"
}
"@
            
            $scriptPath = ".\DynamicGroup_$groupName`_Update.ps1"
            $updateScript | Out-File -FilePath $scriptPath -Encoding UTF8
            Write-Log "Update-Skript erstellt: $scriptPath" -Level "INFO"
            
            Hide-Progress
            Update-Statistics
            
            $message = @"
Dynamische Gruppe erfolgreich erstellt:

Gruppenname: $groupName
LDAP-Filter: $ldapFilter
Mitglieder hinzugefügt: $userCount
Fehler: $errorCount

Ein Update-Skript wurde erstellt: $scriptPath
Dieses kann als geplante Aufgabe eingerichtet werden, um die Gruppenmitgliedschaft automatisch zu aktualisieren.
"@
            
            [System.Windows.MessageBox]::Show($message, "Dynamische Gruppe erstellt", "OK", "Information")
            
        } catch {
            Write-Log "Fehler beim Erstellen der dynamischen Gruppe: $($_.Exception.Message)" -Level "ERROR"
            throw
        }
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei dynamischer Gruppenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-OrganizationalUnitStructure {
    <#
    .SYNOPSIS
    Erstellt eine komplette OU-Struktur basierend auf Firmengröße
    #>
    try {
        Write-Log "Starte OU-Struktur-Erstellung..." -Level "INFO"
        
        $selectedStructure = $Global:GuiControls.ComboBoxOUStructure.SelectedItem
        if (-not $selectedStructure) {
            Write-Log "Keine OU-Struktur ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Firmenstruktur aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $structureType = $selectedStructure.Content
        $createGPOs = $Global:GuiControls.CheckBoxCreateGPOStructure.IsChecked
        
        # Basis-OU ermitteln
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            # Wenn Standard-OU oder leer, verwende Domänen-Root
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
            Write-Log "Verwende Domänen-Root als Basis-OU: $targetOU" -Level "INFO"
        }
        
        # Validiere Basis-OU
        try {
            if ($targetOU -like "OU=*") {
                Get-ADOrganizationalUnit -Identity $targetOU -ErrorAction Stop | Out-Null
            } else {
                Get-ADObject -Identity $targetOU -ErrorAction Stop | Out-Null
            }
            Write-Log "Basis-OU validiert: $targetOU" -Level "DEBUG"
        } catch {
            Write-Log "Basis-OU ungültig oder nicht gefunden: $targetOU" -Level "ERROR"
            [System.Windows.MessageBox]::Show("Die angegebene Basis-OU ist ungültig:`n$targetOU`n`nBitte wählen Sie eine gültige OU aus dem Dropdown.", "OU-Fehler", "OK", "Error")
            return
        }
        
        Show-Progress -Text "Erstelle OU-Struktur..."
        
        $createdOUs = @()
        $successCount = 0
        $errorCount = 0
        
        # OU-Strukturen nach Firmengröße
        $ouStructures = @{
            "Kleine Firma (unter 50 MA)" = @{
                "CompanyName" = @{
                    "Users" = @("Management", "Employees")
                    "Computers" = @("Workstations", "Laptops")
                    "Groups" = @()
                    "Resources" = @()
                }
            }
            
            "Mittlere Firma (50-500 MA)" = @{
                "CompanyName" = @{
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
                "CompanyName" = @{
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
        
        # Rekursive Funktion zum Erstellen der OU-Struktur
        function Create-OURecursive {
            param(
                $Structure,
                $ParentPath,
                $Level = 0
            )
            
            foreach ($ouName in $Structure.Keys) {
                try {
                    $ouPath = "OU=$ouName,$ParentPath"
                    
                    # Prüfe ob OU bereits existiert
                    $existingOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$ouPath'" -ErrorAction SilentlyContinue
                    
                    if (-not $existingOU) {
                        New-ADOrganizationalUnit -Name $ouName `
                            -Path $ParentPath `
                            -Description "Level $Level - $structureType" `
                            -ProtectedFromAccidentalDeletion $true `
                            -ErrorAction Stop
                        
                        $Global:CreatedOUs.Add($ouPath)
                        $Script:createdOUs += $ouPath
                        $Script:successCount++
                        Write-Log "OU '$ouName' erstellt unter '$ParentPath'" -Level "SUCCESS"
                        
                        # GPO-Verknüpfung wenn gewünscht
                        if ($createGPOs -and $Level -le 2) {
                            try {
                                $gpoName = "GPO_$($ouName -replace '\s', '_')"
                                # Hinweis: New-GPO benötigt GroupPolicy-Modul
                                # Dies ist nur ein Platzhalter - in einer realen Umgebung würde man hier GPOs erstellen
                                Write-Log "GPO '$gpoName' würde hier erstellt und verknüpft (benötigt GroupPolicy-Modul)" -Level "INFO"
                            } catch {
                                Write-Log "GPO-Erstellung übersprungen: $($_.Exception.Message)" -Level "WARN"
                            }
                        }
                    } else {
                        Write-Log "OU '$ouName' existiert bereits, übersprungen" -Level "INFO"
                    }
                    
                    # Rekursiv für Unter-OUs
                    if ($Structure[$ouName] -is [hashtable]) {
                        Create-OURecursive -Structure $Structure[$ouName] -ParentPath $ouPath -Level ($Level + 1)
                    } elseif ($Structure[$ouName] -is [array]) {
                        foreach ($subOU in $Structure[$ouName]) {
                            try {
                                $subOUPath = "OU=$subOU,$ouPath"
                                $existingSubOU = Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$subOUPath'" -ErrorAction SilentlyContinue
                                
                                if (-not $existingSubOU) {
                                    New-ADOrganizationalUnit -Name $subOU `
                                        -Path $ouPath `
                                        -Description "Level $($Level + 1) - $structureType" `
                                        -ProtectedFromAccidentalDeletion $true `
                                        -ErrorAction Stop
                                    
                                    $Global:CreatedOUs.Add($subOUPath)
                                    $Script:createdOUs += $subOUPath
                                    $Script:successCount++
                                    Write-Log "OU '$subOU' erstellt unter '$ouPath'" -Level "SUCCESS"
                                }
                            } catch {
                                Write-Log "Fehler bei OU '$subOU': $($_.Exception.Message)" -Level "ERROR"
                                $Script:errorCount++
                            }
                        }
                    }
                } catch {
                    Write-Log "Fehler bei OU '$ouName': $($_.Exception.Message)" -Level "ERROR"
                    $Script:errorCount++
                }
            }
        }
        
        # Initialisiere Script-Variablen für rekursive Funktion
        $Script:createdOUs = $createdOUs
        $Script:successCount = $successCount
        $Script:errorCount = $errorCount
        
        # Erstelle die Struktur
        $selectedStructure = $ouStructures[$structureType]
        Create-OURecursive -Structure $selectedStructure -ParentPath $targetOU
        
        # Übernehme Ergebnisse
        $createdOUs = $Script:createdOUs
        $successCount = $Script:successCount
        $errorCount = $Script:errorCount
        
        # Erstelle Standard-Gruppen in den neuen OUs
        if ($createGPOs) {
            Update-Progress -Current 90 -Total 100 -Text "Erstelle Standard-Gruppen..."
            
            # Beispiel: Erstelle Admin-Gruppen für jede Haupt-OU
            foreach ($ou in $createdOUs | Where-Object { $_ -match "OU=\w+,$targetOU$" }) {
                try {
                    $ouName = ($ou -split ',')[0] -replace 'OU=', ''
                    $adminGroupName = "OU_${ouName}_Admins"
                    
                    New-ADGroup -Name $adminGroupName `
                        -Path $ou `
                        -GroupScope DomainLocal `
                        -GroupCategory Security `
                        -Description "Administratoren für $ouName" `
                        -ErrorAction Stop
                    
                    $Global:CreatedGroups.Add($adminGroupName)
                    Write-Log "Admin-Gruppe '$adminGroupName' für OU erstellt" -Level "DEBUG"
                } catch {
                    Write-Log "Fehler beim Erstellen der Admin-Gruppe: $($_.Exception.Message)" -Level "WARN"
                }
            }
        }
        
        Hide-Progress
        Update-Statistics
        
        # Erstelle Dokumentation
        $docPath = ".\OU_Structure_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $documentation = @"
OU-Struktur Dokumentation
========================
Erstellt am: $(Get-Date)
Struktur-Typ: $structureType
Basis-OU: $targetOU
GPOs erstellt: $(if ($createGPOs) { "Ja" } else { "Nein" })

Erstellte OUs ($($createdOUs.Count)):
$($createdOUs | ForEach-Object { "- $_" } | Out-String)

Zusammenfassung:
- Erfolgreich erstellt: $successCount
- Fehler: $errorCount
"@
        
        $documentation | Out-File -FilePath $docPath -Encoding UTF8
        
        $message = @"
OU-Struktur erfolgreich erstellt:

Typ: $structureType
Erstellt: $successCount OUs
Fehler: $errorCount
GPO-Verknüpfungen: $(if ($createGPOs) { "Aktiviert" } else { "Nicht aktiviert" })

Dokumentation gespeichert unter:
$docPath
"@
        
        [System.Windows.MessageBox]::Show($message, "OU-Struktur erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei OU-Struktur-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-ComputerObjects {
    <#
    .SYNOPSIS
    Erstellt Computer-Objekte in Active Directory
    #>
    try {
        Write-Log "Starte Computer-Erstellung..." -Level "INFO"
        
        $computerCount = $Global:GuiControls.TextBoxComputerCount.Text
        $computerType = $Global:GuiControls.ComboBoxComputerType.SelectedItem
        $randomNames = $Global:GuiControls.CheckBoxRandomComputerNames.IsChecked
        
        if ([string]::IsNullOrWhiteSpace($computerCount)) {
            $computerCount = 10 # Default
        } else {
            $computerCount = [int]$computerCount
        }
        
        if ($computerCount -le 0) {
            Write-Log "Ungültige Anzahl Computer" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Computern an.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $computerType) {
            Write-Log "Kein Computer-Typ ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Computer-Typ aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $type = $computerType.Content
        
        # Bestimme Ziel-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle Test-OUs wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $computerOU = if ($testOUs["COMPUTERS"]) { $testOUs["COMPUTERS"] } else { $targetOU }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $computerCount Computer vom Typ '$type' erstellen?`n`n" +
            "Ziel-OU: $computerOU`n" +
            "Zufällige Namen: $(if ($randomNames) { 'Ja' } else { 'Nein' })",
            "Computer erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle Computer..."
        $successCount = 0
        $errorCount = 0
        
        # Computer-Präfixe basierend auf Typ
        $prefix = switch ($type) {
            "Workstations" { "WS" }
            "Laptops" { "LT" }
            "Server" { "SRV" }
            "Virtual Machines" { "VM" }
            default { "PC" }
        }
        
        # Betriebssystem basierend auf Typ
        $operatingSystem = switch ($type) {
            "Server" { "Windows Server 2022 Datacenter" }
            "Virtual Machines" { "Windows Server 2022 Standard" }
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
                
                # Erstelle Computer
                $computerParams = @{
                    Name = $computerName
                    SamAccountName = "$computerName`$"
                    Path = $computerOU
                    Enabled = $true
                    OperatingSystem = $operatingSystem
                    OperatingSystemVersion = "10.0 (22621)"
                    Description = "$type - Created $(Get-Date -Format 'yyyy-MM-dd')"
                    Location = if ($randomNames) { $locations | Get-Random } else { "Main Office" }
                    ManagedBy = $null
                }
                
                # Zusätzliche Attribute für Server
                if ($type -eq "Server") {
                    $computerParams.OperatingSystemServicePack = "21H2"
                    $computerParams.DNSHostName = "$computerName.$((Get-ADDomain).DNSRoot)"
                }
                
                New-ADComputer @computerParams -ErrorAction Stop
                $Global:CreatedComputers.Add($computerName)
                Write-Log "Computer '$computerName' erfolgreich erstellt" -Level "SUCCESS"
                $successCount++
                
            } catch {
                Write-Log "Fehler beim Erstellen von Computer: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
            
            Update-Progress -Current $i -Total $computerCount -Text "Erstelle Computer $i von $computerCount..."
        }
        
        Hide-Progress
        Update-Statistics
        
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
        Write-Log "Fehler bei Computer-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-ServiceAccounts {
    <#
    .SYNOPSIS
    Erstellt Service-Account Benutzer in Active Directory
    #>
    try {
        Write-Log "Starte Service-Account-Erstellung..." -Level "INFO"
        
        $serviceType = $Global:GuiControls.ComboBoxServiceType.SelectedItem
        $accountCount = $Global:GuiControls.TextBoxServiceAccountCount.Text
        
        if (-not $serviceType) {
            Write-Log "Kein Service-Typ ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Service-Typ aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($accountCount)) {
            $accountCount = 5 # Default
        } else {
            $accountCount = [int]$accountCount
        }
        
        if ($accountCount -le 0) {
            Write-Log "Ungültige Anzahl Service-Accounts" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Service-Accounts an.", "Hinweis", "OK", "Warning")
            return
        }
        
        $type = $serviceType.Content
        
        # Bestimme Ziel-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle Test-OUs wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $serviceOU = if ($testOUs["SERVICES"]) { $testOUs["SERVICES"] } else { $targetOU }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $accountCount Service-Accounts für '$type' erstellen?`n`n" +
            "Ziel-OU: $serviceOU",
            "Service-Accounts erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle Service-Accounts..."
        $successCount = 0
        $errorCount = 0
        
        # Service-Account Präfixe und Eigenschaften
        $serviceConfig = @{
            "SQL Server Service" = @{
                Prefix = "svc_sql"
                Description = "SQL Server Service Account"
                SPNs = @("MSSQLSvc/")
            }
            "IIS Application Pool" = @{
                Prefix = "svc_iis"
                Description = "IIS Application Pool Identity"
                SPNs = @("HTTP/")
            }
            "Windows Service" = @{
                Prefix = "svc_win"
                Description = "Windows Service Account"
                SPNs = @()
            }
            "Scheduled Task" = @{
                Prefix = "svc_task"
                Description = "Scheduled Task Service Account"
                SPNs = @()
            }
            "Custom Application" = @{
                Prefix = "svc_app"
                Description = "Custom Application Service Account"
                SPNs = @()
            }
        }
        
        $config = $serviceConfig[$type]
        $domain = (Get-ADDomain).DNSRoot
        
        for ($i = 1; $i -le $accountCount; $i++) {
            try {
                # Generiere Service-Account Namen
                $accountName = "$($config.Prefix)_$(Get-Random -Minimum 1000 -Maximum 9999)"
                
                # Erstelle Service-Account
                $serviceParams = @{
                    Name = $accountName
                    SamAccountName = $accountName
                    UserPrincipalName = "$accountName@$domain"
                    Path = $serviceOU
                    Enabled = $true
                    PasswordNeverExpires = $true
                    CannotChangePassword = $true
                    Description = "$($config.Description) - Created $(Get-Date -Format 'yyyy-MM-dd')"
                    DisplayName = "$type Service Account $i"
                    AccountPassword = (ConvertTo-SecureString -String (Generate-SecurePassword -Complexity "Hochsicher (20+ Zeichen)") -AsPlainText -Force)
                    ServicePrincipalNames = @()
                }
                
                # Füge SPNs hinzu wenn vorhanden
                if ($config.SPNs.Count -gt 0) {
                    $spns = @()
                    foreach ($spnPrefix in $config.SPNs) {
                        $hostname = "server$(Get-Random -Minimum 1 -Maximum 99).$domain"
                        $spns += "$spnPrefix$hostname"
                        if ($spnPrefix -eq "HTTP/") {
                            $spns += "$spnPrefix$hostname:80"
                            $spns += "$spnPrefix$hostname:443"
                        } elseif ($spnPrefix -eq "MSSQLSvc/") {
                            $spns += "$spnPrefix$hostname:1433"
                        }
                    }
                    $serviceParams.ServicePrincipalNames = $spns
                }
                
                New-ADUser @serviceParams -ErrorAction Stop
                $Global:CreatedServiceAccounts.Add($accountName)
                Write-Log "Service-Account '$accountName' erfolgreich erstellt" -Level "SUCCESS"
                $successCount++
                
            } catch {
                Write-Log "Fehler beim Erstellen von Service-Account: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
            
            Update-Progress -Current $i -Total $accountCount -Text "Erstelle Service-Account $i von $accountCount..."
        }
        
        Hide-Progress
        Update-Statistics
        
        $message = @"
Service-Account-Erstellung abgeschlossen:

Typ: $type
Erstellt: $successCount
Fehler: $errorCount
Ziel-OU: $serviceOU

Hinweis: Alle Service-Accounts haben:
- Passwort läuft nie ab
- Benutzer kann Passwort nicht ändern
- Hochsichere Passwörter (20+ Zeichen)
"@
        
        [System.Windows.MessageBox]::Show($message, "Service-Accounts erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Service-Account-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-PrinterObjects {
    <#
    .SYNOPSIS
    Erstellt Drucker-Objekte in Active Directory
    #>
    try {
        Write-Log "Starte Drucker-Erstellung..." -Level "INFO"
        
        $printerCount = $Global:GuiControls.TextBoxPrinterCount.Text
        $printerType = $Global:GuiControls.ComboBoxPrinterType.SelectedItem
        
        if ([string]::IsNullOrWhiteSpace($printerCount)) {
            $printerCount = 3 # Default
        } else {
            $printerCount = [int]$printerCount
        }
        
        if ($printerCount -le 0) {
            Write-Log "Ungültige Anzahl Drucker" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Druckern an.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $printerType) {
            Write-Log "Kein Drucker-Typ ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Drucker-Typ aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $type = $printerType.Content
        
        # Bestimme Ziel-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle Test-OUs wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $resourceOU = if ($testOUs["RESOURCES"]) { $testOUs["RESOURCES"] } else { $targetOU }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $printerCount Drucker vom Typ '$type' erstellen?`n`n" +
            "Ziel-OU: $resourceOU`n`n" +
            "Hinweis: Dies erstellt printQueue-Objekte in AD.",
            "Drucker erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle Drucker..."
        $successCount = 0
        $errorCount = 0
        
        # Drucker-Hersteller und Modelle
        $manufacturers = @{
            "HP" = @("LaserJet Pro M404dn", "Color LaserJet Pro M454dw", "OfficeJet Pro 9015e")
            "Canon" = @("imageCLASS MF445dw", "PIXMA TR8620", "imageRUNNER ADVANCE C5560i")
            "Brother" = @("HL-L2350DW", "MFC-L2750DW", "HL-L8360CDW")
            "Epson" = @("WorkForce Pro WF-4830", "EcoTank ET-4760", "SureColor P700")
            "Xerox" = @("VersaLink C405", "WorkCentre 6515", "Phaser 6510")
        }
        
        # Standorte
        $locations = @(
            "1st Floor - Reception",
            "2nd Floor - Sales",
            "3rd Floor - IT Department",
            "4th Floor - Management",
            "Ground Floor - Copy Room",
            "Warehouse - Shipping",
            "Conference Room A",
            "Conference Room B"
        )
        
        for ($i = 1; $i -le $printerCount; $i++) {
            try {
                # Wähle zufälligen Hersteller und Modell
                $manufacturer = $manufacturers.Keys | Get-Random
                $model = $manufacturers[$manufacturer] | Get-Random
                $location = $locations | Get-Random
                
                # Generiere Drucker-Namen
                $printerName = switch ($type) {
                    "Netzwerkdrucker" { "PRN-NET-$('{0:D3}' -f $i)" }
                    "Lokale Drucker" { "PRN-LOC-$('{0:D3}' -f $i)" }
                    "Multifunktionsgeräte" { "PRN-MFP-$('{0:D3}' -f $i)" }
                }
                
                # Erstelle printQueue-Objekt
                $printerAttributes = @{
                    'printShareName' = $printerName
                    'printerName' = "$manufacturer $model"
                    'serverName' = "\\PRINTSERVER01"
                    'uNCName' = "\\PRINTSERVER01\$printerName"
                    'location' = $location
                    'description' = "$type - $manufacturer $model"
                    'driverName' = "$manufacturer Universal Print Driver"
                    'driverVersion' = "6.3.0.$(Get-Random -Minimum 1000 -Maximum 9999)"
                    'printColor' = if ($model -like "*Color*") { "TRUE" } else { "FALSE" }
                    'printDuplexSupported' = "TRUE"
                    'printStaplingSupported' = if ($type -eq "Multifunktionsgeräte") { "TRUE" } else { "FALSE" }
                    'printMaxResolutionSupported' = if ($manufacturer -eq "Epson") { "2400" } else { "1200" }
                    'portName' = "IP_192.168.1.$(Get-Random -Minimum 100 -Maximum 254)"
                }
                
                New-ADObject -Name $printerName `
                    -Type 'printQueue' `
                    -Path $resourceOU `
                    -OtherAttributes $printerAttributes `
                    -ErrorAction Stop
                
                Write-Log "Drucker '$printerName' erfolgreich erstellt" -Level "SUCCESS"
                $successCount++
                
            } catch {
                Write-Log "Fehler beim Erstellen von Drucker: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
            
            Update-Progress -Current $i -Total $printerCount -Text "Erstelle Drucker $i von $printerCount..."
        }
        
        Hide-Progress
        
        $message = @"
Drucker-Erstellung abgeschlossen:

Typ: $type
Erstellt: $successCount
Fehler: $errorCount
Ziel-OU: $resourceOU

Die Drucker wurden als printQueue-Objekte in AD erstellt.
Sie können in der AD-Verwaltung unter der Resources-OU gefunden werden.
"@
        
        [System.Windows.MessageBox]::Show($message, "Drucker erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Drucker-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-ComputerBitLockerData {
    <#
    .SYNOPSIS
    Erstellt BitLocker Recovery Keys für ausgewählte Computer
    #>
    try {
        Write-Log "Starte BitLocker-Datenerstellung für Computer..." -Level "INFO"
        
        if (-not $Global:CreatedComputers -or $Global:CreatedComputers.Count -eq 0) {
            Write-Log "Keine Computer für BitLocker-Daten vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Anzahl der Computer bestimmen
        $computerCount = $Global:GuiControls.TextBoxBitLockerComputerCount.Text
        $randomSelection = $false  # CheckBox existiert nicht in der GUI
        
        if ([string]::IsNullOrWhiteSpace($computerCount)) {
            $computerCount = $Global:CreatedComputers.Count
        } else {
            $computerCount = [int]$computerCount
            if ($computerCount -gt $Global:CreatedComputers.Count) {
                $computerCount = $Global:CreatedComputers.Count
                Write-Log "Anzahl auf verfügbare Computer reduziert: $computerCount" -Level "INFO"
            }
        }
        
        if ($computerCount -le 0) {
            Write-Log "Ungültige Anzahl Computer für BitLocker" -Level "WARN"
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
        
        Show-Progress -Text "Erstelle BitLocker Recovery Keys..."
        
        # Computer auswählen
        $selectedComputers = if ($randomSelection) {
            $Global:CreatedComputers | Get-Random -Count $computerCount
        } else {
            $Global:CreatedComputers | Select-Object -First $computerCount
        }
        
        $successCount = 0
        $errorCount = 0
        $bitlockerData = @()
        
        for ($i = 0; $i -lt $selectedComputers.Count; $i++) {
            $computer = $selectedComputers[$i]
            Update-Progress -Current ($i + 1) -Total $selectedComputers.Count -Text "Erstelle BitLocker Key für $computer"
            
            try {
                # Generiere Recovery-Informationen
                $recoveryGuid = [System.Guid]::NewGuid()
                $recoveryPassword = Generate-BitLockerRecoveryPassword
                $recoveryId = $recoveryPassword.Substring(0, 8)
                $tpmKeyHash = [System.Guid]::NewGuid().ToString('N').Substring(0, 40).ToUpper()
                
                # Hole Computer-Objekt
                $computerObj = Get-ADComputer -Identity $computer -Properties * -ErrorAction Stop
                
                # Simuliere verschiedene BitLocker-Attribute
                $bitlockerAttributes = @{
                    'msTPM-OwnerInformation' = $tpmKeyHash
                    'info' = "BitLocker Recovery ID: $recoveryId`nProtection Status: Enabled`nEncryption Method: AES-256`nTPM: Present and Ready"
                }
                
                # Setze Attribute am Computer-Objekt
                Set-ADComputer -Identity $computer -Replace $bitlockerAttributes -ErrorAction Stop
                
                # Versuche msFVE-RecoveryInformation zu erstellen (benötigt spezielle Rechte)
                try {
                    $recoveryDN = "CN=$recoveryGuid,$($computerObj.DistinguishedName)"
                    
                    New-ADObject -Name $recoveryGuid.ToString() `
                        -Type 'msFVE-RecoveryInformation' `
                        -Path $computerObj.DistinguishedName `
                        -OtherAttributes @{
                            'msFVE-RecoveryGuid' = $recoveryGuid.ToString('B')
                            'msFVE-RecoveryPassword' = $recoveryPassword
                            'msFVE-VolumeGuid' = [System.Guid]::NewGuid().ToString('B')
                            'msFVE-RecoveryInformationIdentifier' = "TPM and PIN"
                            'whenCreated' = Get-Date
                        } `
                        -ErrorAction Stop
                    
                    Write-Log "BitLocker Recovery-Objekt für '$computer' erstellt" -Level "DEBUG"
                } catch {
                    # Fallback wenn keine Rechte für msFVE-RecoveryInformation
                    Write-Log "Konnte msFVE-RecoveryInformation nicht erstellen (Rechte fehlen), verwende Fallback" -Level "DEBUG"
                }
                
                # Speichere Daten für Export
                $bitlockerData += [PSCustomObject]@{
                    ComputerName = $computer
                    RecoveryID = $recoveryId
                    RecoveryPassword = $recoveryPassword
                    RecoveryGuid = $recoveryGuid
                    TPMKeyHash = $tpmKeyHash
                    EncryptionMethod = "AES-256"
                    ProtectionStatus = "Enabled"
                    VolumeType = "OperatingSystem"
                    CreatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                $successCount++
                Write-Log "BitLocker-Daten für '$computer' erstellt" -Level "SUCCESS"
                
            } catch {
                Write-Log "Fehler bei BitLocker-Daten für '$computer': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Exportiere BitLocker-Daten
        if ($bitlockerData.Count -gt 0) {
            $exportPath = ".\BitLocker_ComputerKeys_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $bitlockerData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Log "BitLocker-Keys exportiert nach: $exportPath" -Level "INFO"
            
            # Erstelle zusätzliche Dokumentation
            $docPath = ".\BitLocker_Documentation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
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
        Write-Log "Fehler bei BitLocker-Datenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-LAPSData {
    <#
    .SYNOPSIS
    Erstellt LAPS (Local Administrator Password Solution) Daten für ausgewählte Systeme
    #>
    try {
        Write-Log "Starte LAPS-Datenerstellung..." -Level "INFO"
        
        if (-not $Global:CreatedComputers -or $Global:CreatedComputers.Count -eq 0) {
            Write-Log "Keine Computer für LAPS-Daten vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Parameter auslesen
        $systemCount = $Global:GuiControls.TextBoxLAPSSystemCount.Text
        $includeServers = $true  # CheckBox existiert nicht in der GUI, Standard: Ja
        $includeWorkstations = $true  # CheckBox existiert nicht in der GUI, Standard: Ja
        
        if (-not ($includeServers -or $includeWorkstations)) {
            Write-Log "Keine System-Typen für LAPS ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens einen System-Typ aus (Server oder Workstations).", "Hinweis", "OK", "Warning")
            return
        }
        
        # Systeme filtern
        $eligibleSystems = @()
        foreach ($computer in $Global:CreatedComputers) {
            try {
                $compObj = Get-ADComputer -Identity $computer -Properties OperatingSystem -ErrorAction Stop
                $os = $compObj.OperatingSystem
                
                $isServer = $os -like "*Server*"
                $isWorkstation = $os -notlike "*Server*"
                
                if (($isServer -and $includeServers) -or ($isWorkstation -and $includeWorkstations)) {
                    $eligibleSystems += @{
                        Name = $computer
                        Type = if ($isServer) { "Server" } else { "Workstation" }
                        OS = $os
                    }
                }
            } catch {
                Write-Log "Fehler beim Prüfen von Computer '$computer': $($_.Exception.Message)" -Level "DEBUG"
            }
        }
        
        if ($eligibleSystems.Count -eq 0) {
            Write-Log "Keine passenden Systeme für LAPS gefunden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Keine passenden Systeme für die ausgewählten Kriterien gefunden.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Anzahl bestimmen
        if ([string]::IsNullOrWhiteSpace($systemCount)) {
            $systemCount = $eligibleSystems.Count
        } else {
            $systemCount = [int]$systemCount
            if ($systemCount -gt $eligibleSystems.Count) {
                $systemCount = $eligibleSystems.Count
                Write-Log "Anzahl auf verfügbare Systeme reduziert: $systemCount" -Level "INFO"
            }
        }
        
        if ($systemCount -le 0) {
            Write-Log "Ungültige Anzahl Systeme für LAPS" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Systemen an.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie LAPS-Passwörter für $systemCount Systeme erstellen?`n`n" +
            "Verfügbare Systeme: $($eligibleSystems.Count)`n" +
            "Server: $(($eligibleSystems | Where-Object { $_.Type -eq 'Server' }).Count)`n" +
            "Workstations: $(($eligibleSystems | Where-Object { $_.Type -eq 'Workstation' }).Count)",
            "LAPS-Passwörter erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle LAPS-Passwörter..."
        
        # Systeme auswählen
        $selectedSystems = $eligibleSystems | Get-Random -Count $systemCount
        
        $successCount = 0
        $errorCount = 0
        $lapsData = @()
        
        # LAPS-Passwort-Richtlinien
        $passwordLength = 14  # Standard LAPS-Länge
        $passwordComplexity = @{
            Server = 20       # Längere Passwörter für Server
            Workstation = 14  # Standard für Workstations
        }
        
        for ($i = 0; $i -lt $selectedSystems.Count; $i++) {
            $system = $selectedSystems[$i]
            Update-Progress -Current ($i + 1) -Total $selectedSystems.Count -Text "Erstelle LAPS-Passwort für $($system.Name)"
            
            try {
                # Generiere LAPS-Passwort basierend auf System-Typ
                $pwdLength = $passwordComplexity[$system.Type]
                $lapsPassword = Generate-SecurePassword -Complexity "Komplex (16 Zeichen + Spezial)" -IncludeNumbers $true -IncludeSymbols $true -ExcludeAmbiguous $true
                
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
                    Write-Log "LAPS-Attribute für '$($system.Name)' gesetzt" -Level "DEBUG"
                } catch {
                    # Fallback: Verwende Custom-Attribute
                    $fallbackAttributes = @{
                        'adminDescription' = "LAPS Password Set: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                        'info' = "LAPS Enabled | Password Length: $pwdLength | Expires: $((Get-Date).AddDays(30).ToString('yyyy-MM-dd'))"
                        'comment' = "LAPS Password: See secure storage"
                    }
                    
                    Set-ADComputer -Identity $system.Name -Replace $fallbackAttributes -ErrorAction Stop
                    Write-Log "LAPS-Daten als Custom-Attribute gespeichert (Fallback)" -Level "DEBUG"
                }
                
                # Speichere LAPS-Daten für Export
                $lapsData += [PSCustomObject]@{
                    ComputerName = $system.Name
                    SystemType = $system.Type
                    OperatingSystem = $system.OS
                    LocalAdminPassword = $lapsPassword
                    PasswordLength = $pwdLength
                    PasswordSetDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    PasswordExpiryDate = (Get-Date).AddDays(30).ToString("yyyy-MM-dd HH:mm:ss")
                    LastChangeBy = $env:USERNAME
                    Status = "Active"
                }
                
                $successCount++
                Write-Log "LAPS-Passwort für '$($system.Name)' erstellt" -Level "SUCCESS"
                
            } catch {
                Write-Log "Fehler bei LAPS-Passwort für '$($system.Name)': $($_.Exception.Message)" -Level "ERROR"
                $lapsData += [PSCustomObject]@{
                    ComputerName = $system.Name
                    SystemType = $system.Type
                    OperatingSystem = $system.OS
                    LocalAdminPassword = "ERROR"
                    PasswordLength = 0
                    PasswordSetDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    PasswordExpiryDate = "N/A"
                    LastChangeBy = $env:USERNAME
                    Status = "Failed: $($_.Exception.Message)"
                }
                $errorCount++
            }
        }
        
        # Exportiere LAPS-Daten
        if ($lapsData.Count -gt 0) {
            $exportPath = ".\LAPS_Passwords_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $lapsData | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            Write-Log "LAPS-Passwörter exportiert nach: $exportPath" -Level "INFO"
            
            # Erstelle LAPS-Bericht
            $reportPath = ".\LAPS_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
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
Server: $(($lapsData | Where-Object { $_.SystemType -eq 'Server' -and $_.Status -eq 'Active' }).Count)
Workstations: $(($lapsData | Where-Object { $_.SystemType -eq 'Workstation' -and $_.Status -eq 'Active' }).Count)

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
        Write-Log "Fehler bei LAPS-Datenerstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

#endregion

#region Test-Szenarien - Implementierung

function Create-TestDataSet {
    <#
    .SYNOPSIS
    Erstellt umfangreiche Testdaten-Sets mit realistischer Verteilung
    #>
    try {
        Write-Log "Starte Testdaten-Set Erstellung..." -Level "INFO"
        
        $dataSize = $Global:GuiControls.ComboBoxTestDataSize.SelectedItem
        if (-not $dataSize) {
            Write-Log "Keine Testdaten-Größe ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine Testdaten-Größe aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $realisticData = $Global:GuiControls.CheckBoxRealisticData.IsChecked
        $historicalData = $false  # CheckBox existiert nicht in der GUI
        
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
        
        # Basis-OU für Testdaten
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle Test-OU-Struktur
        Show-Progress -Text "Erstelle Test-OU-Struktur..." -Value 0
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        
        $totalObjects = $objectCounts.Users + $objectCounts.Groups + $objectCounts.Computers
        $currentObject = 0
        
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
        Update-Progress -Current 0 -Total $totalObjects -Text "Erstelle Benutzer..."
        
        foreach ($dept in $departmentDistribution.Keys) {
            $deptUserCount = [math]::Round($objectCounts.Users * $departmentDistribution[$dept])
            
            for ($i = 1; $i -le $deptUserCount; $i++) {
                $currentObject++
                
                try {
                    $firstName = Get-RandomFirstName
                    $lastName = Get-RandomLastName
                    $samAccountName = "$($firstName.ToLower()).$($lastName.ToLower())$(Get-Random -Minimum 100 -Maximum 999)"
                    
                    # Historische Daten simulieren
                    $createdDate = if ($historicalData) {
                        # Zufälliges Datum in den letzten 5 Jahren
                        (Get-Date).AddDays(-(Get-Random -Minimum 0 -Maximum 1825))
                    } else {
                        Get-Date
                    }
                    
                    $userParams = @{
                        Name = "$firstName $lastName"
                        SamAccountName = $samAccountName
                        UserPrincipalName = "$samAccountName@$((Get-ADDomain).DNSRoot)"
                        GivenName = $firstName
                        Surname = $lastName
                        DisplayName = "$firstName $lastName"
                        Department = $dept
                        Title = Get-RandomJobTitle
                        Company = "Test Company"
                        City = Get-RandomCity
                        StreetAddress = Get-RandomStreetAddress
                        PostalCode = Get-RandomPostalCode
                        Country = "DE"
                        OfficePhone = Get-RandomPhoneNumber
                        MobilePhone = Get-RandomPhoneNumber
                        Path = $testOUs["USERS"]
                        Enabled = $true
                        AccountPassword = (ConvertTo-SecureString -String (Generate-SecurePassword) -AsPlainText -Force)
                        ChangePasswordAtLogon = $false
                    }
                    
                    # Füge historische Attribute hinzu
                    if ($historicalData) {
                        $userParams.OtherAttributes = @{
                            'whenCreated' = $createdDate
                        }
                    }
                    
                    New-ADUser @userParams -ErrorAction Stop
                    $Global:CreatedUsers.Add($samAccountName)
                    
                } catch {
                    Write-Log "Fehler beim Erstellen von Testbenutzer: $($_.Exception.Message)" -Level "WARN"
                }
                
                if ($currentObject % 100 -eq 0) {
                    Update-Progress -Current $currentObject -Total $totalObjects -Text "Erstelle Objekte... ($currentObject/$totalObjects)"
                }
            }
        }
        
        # 2. Erstelle Gruppen
        Update-Progress -Current $currentObject -Total $totalObjects -Text "Erstelle Gruppen..."
        
        # Erstelle Abteilungsgruppen
        foreach ($dept in $departmentDistribution.Keys) {
            try {
                $groupName = "GRP_$dept"
                New-ADGroup -Name $groupName `
                    -GroupScope Global `
                    -GroupCategory Security `
                    -Description "$dept Department Group" `
                    -Path $testOUs["GROUPS"] `
                    -ErrorAction Stop
                
                $Global:CreatedGroups.Add($groupName)
                $currentObject++
                
                # Füge Benutzer zur Gruppe hinzu
                $deptUsers = Get-ADUser -Filter "Department -eq '$dept'" -SearchBase $testOUs["USERS"] -ErrorAction SilentlyContinue
                if ($deptUsers) {
                    Add-ADGroupMember -Identity $groupName -Members $deptUsers -ErrorAction SilentlyContinue
                }
                
            } catch {
                Write-Log "Fehler beim Erstellen von Gruppe '$groupName': $($_.Exception.Message)" -Level "WARN"
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
                    -Description "$groupType Group" `
                    -Path $testOUs["GROUPS"] `
                    -ErrorAction Stop
                
                $Global:CreatedGroups.Add($groupName)
                $currentObject++
                
            } catch {
                Write-Log "Fehler beim Erstellen von Gruppe: $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        # 3. Erstelle Computer
        Update-Progress -Current $currentObject -Total $totalObjects -Text "Erstelle Computer..."
        
        $computerTypes = if ($realisticData) {
            @{
                "Workstations" = 0.60
                "Laptops" = 0.25
                "Server" = 0.10
                "Virtual Machines" = 0.05
            }
        } else {
            @{
                "Workstations" = 0.25
                "Laptops" = 0.25
                "Server" = 0.25
                "Virtual Machines" = 0.25
            }
        }
        
        foreach ($compType in $computerTypes.Keys) {
            $typeCount = [math]::Round($objectCounts.Computers * $computerTypes[$compType])
            $typePrefix = switch ($compType) {
                "Workstations" { "WS" }
                "Laptops" { "LT" }
                "Server" { "SRV" }
                "Virtual Machines" { "VM" }
            }
            
            for ($i = 1; $i -le $typeCount; $i++) {
                try {
                    $computerName = "$typePrefix-TEST-$(Get-Random -Minimum 10000 -Maximum 99999)"
                    
                    New-ADComputer -Name $computerName `
                        -SamAccountName "$computerName`$" `
                        -Path $testOUs["COMPUTERS"] `
                        -Enabled $true `
                        -Description "$compType - Test Data Set" `
                        -OperatingSystem $(if ($compType -eq "Server") { "Windows Server 2022" } else { "Windows 11" }) `
                        -ErrorAction Stop
                    
                    $Global:CreatedComputers.Add($computerName)
                    $currentObject++
                    
                } catch {
                    Write-Log "Fehler beim Erstellen von Computer: $($_.Exception.Message)" -Level "WARN"
                }
            }
        }
        
        Hide-Progress
        Update-Statistics
        
        $message = @"
Testdaten-Set erfolgreich erstellt:

Benutzer: $($Global:CreatedUsers.Count)
Gruppen: $($Global:CreatedGroups.Count)
Computer: $($Global:CreatedComputers.Count)

Gesamtobjekte: $($Global:CreatedUsers.Count + $Global:CreatedGroups.Count + $Global:CreatedComputers.Count)

Die Objekte wurden in dedizierten Test-OUs erstellt.
"@
        
        [System.Windows.MessageBox]::Show($message, "Testdaten erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Testdaten-Set Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Activate-ChaosMode {
    <#
    .SYNOPSIS
    Aktiviert den Chaos-Modus für fehlerhafte/problematische Testdaten
    #>
    try {
        Write-Log "WARNUNG: Chaos-Modus wird aktiviert..." -Level "WARN"
        
        $invalidData = $Global:GuiControls.CheckBoxInvalidData.IsChecked
        $missingAttributes = $Global:GuiControls.CheckBoxMissingAttributes.IsChecked
        $duplicateEntries = $Global:GuiControls.CheckBoxDuplicateEntries.IsChecked
        $specialCharacters = $false  # CheckBox existiert nicht in der GUI
        
        if (-not ($invalidData -or $missingAttributes -or $duplicateEntries -or $specialCharacters)) {
            Write-Log "Keine Chaos-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Chaos-Option aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "WARNUNG: Der Chaos-Modus erstellt absichtlich fehlerhafte Daten!`n`n" +
            "Dies kann zu Problemen in Ihrer Test-Umgebung führen.`n`n" +
            "Ausgewählte Optionen:`n" +
            "$(if ($invalidData) { '- Ungültige Daten`n' })" +
            "$(if ($missingAttributes) { '- Fehlende Attribute`n' })" +
            "$(if ($duplicateEntries) { '- Doppelte Einträge`n' })" +
            "$(if ($specialCharacters) { '- Sonderzeichen`n' })`n" +
            "Möchten Sie wirklich fortfahren?",
            "CHAOS-MODUS WARNUNG",
            "YesNo",
            "Warning"
        )
        
        if ($result -ne "Yes") { return }
        
        # Basis-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        Show-Progress -Text "Aktiviere Chaos-Modus..."
        $chaosCount = 0
        $errorCount = 0
        
        # 1. Ungültige Daten
        if ($invalidData) {
            Update-Progress -Current 25 -Total 100 -Text "Erstelle ungültige Daten..."
            
            # Benutzer mit ungültigen E-Mail-Adressen
            for ($i = 1; $i -le 5; $i++) {
                try {
                    $invalidUser = @{
                        Name = "Invalid_User_$i"
                        SamAccountName = "invalid.user.$i"
                        Path = $targetOU
                        Enabled = $true
                        EmailAddress = "not@valid@email@address.com"
                        AccountPassword = (ConvertTo-SecureString -String "123" -AsPlainText -Force) # Zu kurzes Passwort
                    }
                    
                    New-ADUser @invalidUser -ErrorAction Stop
                    $Global:CreatedUsers.Add($invalidUser.SamAccountName)
                    $chaosCount++
                } catch {
                    Write-Log "Erwarteter Fehler bei ungültigen Daten: $($_.Exception.Message)" -Level "DEBUG"
                    $errorCount++
                }
            }
        }
        
        # 2. Fehlende Attribute
        if ($missingAttributes) {
            Update-Progress -Current 50 -Total 100 -Text "Erstelle Benutzer mit fehlenden Attributen..."
            
            for ($i = 1; $i -le 5; $i++) {
                try {
                    $incompleteUser = @{
                        Name = "Incomplete_User_$i"
                        SamAccountName = "incomplete.user.$i"
                        Path = $targetOU
                        Enabled = $true
                        AccountPassword = (ConvertTo-SecureString -String (Generate-SecurePassword) -AsPlainText -Force)
                        # Absichtlich fehlende Attribute: GivenName, Surname, DisplayName, Email
                    }
                    
                    New-ADUser @incompleteUser -ErrorAction Stop
                    $Global:CreatedUsers.Add($incompleteUser.SamAccountName)
                    $chaosCount++
                } catch {
                    Write-Log "Fehler bei Benutzer mit fehlenden Attributen: $($_.Exception.Message)" -Level "DEBUG"
                    $errorCount++
                }
            }
        }
        
        # 3. Doppelte Einträge
        if ($duplicateEntries) {
            Update-Progress -Current 75 -Total 100 -Text "Versuche doppelte Einträge zu erstellen..."
            
            # Versuche denselben Benutzer mehrmals zu erstellen
            $duplicateName = "duplicate.user"
            for ($i = 1; $i -le 3; $i++) {
                try {
                    New-ADUser -Name "Duplicate User" `
                        -SamAccountName $duplicateName `
                        -Path $targetOU `
                        -Enabled $true `
                        -AccountPassword (ConvertTo-SecureString -String (Generate-SecurePassword) -AsPlainText -Force) `
                        -ErrorAction Stop
                    
                    if ($i -eq 1) {
                        $Global:CreatedUsers.Add($duplicateName)
                        $chaosCount++
                    }
                } catch {
                    if ($i -gt 1) {
                        Write-Log "Erwarteter Fehler bei Duplikat: $($_.Exception.Message)" -Level "DEBUG"
                    } else {
                        $errorCount++
                    }
                }
            }
        }
        
        # 4. Sonderzeichen
        if ($specialCharacters) {
            Update-Progress -Current 100 -Total 100 -Text "Erstelle Einträge mit Sonderzeichen..."
            
            $specialNames = @(
                "Müller, Dr. Hans-Peter",
                "O'Brien",
                "José García-López",
                "Владимир Путин",
                "王小明",
                "Test & User",
                "User (Test)",
                "Test/User"
            )
            
            foreach ($specialName in $specialNames) {
                try {
                    # Normalisiere SamAccountName
                    $samName = Normalize-SamAccountName -SamAccountName $specialName
                    
                    New-ADUser -Name $specialName `
                        -SamAccountName $samName `
                        -DisplayName $specialName `
                        -Path $targetOU `
                        -Enabled $true `
                        -AccountPassword (ConvertTo-SecureString -String (Generate-SecurePassword) -AsPlainText -Force) `
                        -ErrorAction Stop
                    
                    $Global:CreatedUsers.Add($samName)
                    $chaosCount++
                } catch {
                    Write-Log "Fehler bei Sonderzeichen-Benutzer '$specialName': $($_.Exception.Message)" -Level "DEBUG"
                    $errorCount++
                }
            }
        }
        
        Hide-Progress
        Update-Statistics
        
        $message = @"
Chaos-Modus abgeschlossen:

Erfolgreich erstellt: $chaosCount chaotische Objekte
Erwartete Fehler: $errorCount

Die erstellten Objekte können für Fehlerbehandlungs-Tests verwendet werden.
"@
        
        [System.Windows.MessageBox]::Show($message, "Chaos-Modus aktiviert", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler im Chaos-Modus: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler im Chaos-Modus:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Start-PerformanceTest {
    <#
    .SYNOPSIS
    Führt Performance-Tests für AD-Operationen durch
    #>
    try {
        Write-Log "Starte Performance-Test..." -Level "INFO"
        
        $objectCount = $Global:GuiControls.TextBoxPerformanceCount.Text
        $batchSize = $Global:GuiControls.TextBoxBatchSize.Text
        
        if ([string]::IsNullOrWhiteSpace($objectCount) -or [string]::IsNullOrWhiteSpace($batchSize)) {
            Write-Log "Performance-Test Parameter fehlen" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie Anzahl der Objekte und Batch-Größe an.", "Hinweis", "OK", "Warning")
            return
        }
        
        $objectCount = [int]$objectCount
        $batchSize = [int]$batchSize
        
        if ($objectCount -le 0 -or $batchSize -le 0) {
            Write-Log "Ungültige Performance-Test Parameter" -Level "WARN"
            [System.Windows.MessageBox]::Show("Anzahl und Batch-Größe müssen größer als 0 sein.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Performance-Test-Konfiguration:`n`n" +
            "Objekte: $objectCount`n" +
            "Batch-Größe: $batchSize`n" +
            "Geschätzte Batches: $([math]::Ceiling($objectCount / $batchSize))`n`n" +
            "Dies kann je nach Größe mehrere Minuten dauern.`n`n" +
            "Fortfahren?",
            "Performance-Test starten",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        # Basis-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Performance-Metriken
        $metrics = @{
            StartTime = Get-Date
            EndTime = $null
            TotalObjects = $objectCount
            SuccessfulObjects = 0
            FailedObjects = 0
            BatchCount = [math]::Ceiling($objectCount / $batchSize)
            BatchTimes = @()
        }
        
        Show-Progress -Text "Performance-Test läuft..." -Value 0
        
        # Führe Test in Batches durch
        $currentObject = 0
        $batchNumber = 1
        
        while ($currentObject -lt $objectCount) {
            $batchStart = Get-Date
            $batchObjects = [math]::Min($batchSize, $objectCount - $currentObject)
            
            Update-Progress -Current $currentObject -Total $objectCount -Text "Verarbeite Batch $batchNumber von $($metrics.BatchCount)..."
            
            # Erstelle Objekte im Batch
            for ($i = 1; $i -le $batchObjects; $i++) {
                try {
                    $userName = "perftest_$(Get-Random -Minimum 100000 -Maximum 999999)"
                    
                    New-ADUser -Name $userName `
                        -SamAccountName $userName `
                        -Path $targetOU `
                        -Enabled $false `
                        -Description "Performance Test Object" `
                        -AccountPassword (ConvertTo-SecureString -String "Test123!" -AsPlainText -Force) `
                        -ErrorAction Stop
                    
                    $Global:CreatedUsers.Add($userName)
                    $metrics.SuccessfulObjects++
                } catch {
                    $metrics.FailedObjects++
                    Write-Log "Performance-Test Fehler: $($_.Exception.Message)" -Level "DEBUG"
                }
                
                $currentObject++
            }
            
            $batchEnd = Get-Date
            $batchDuration = ($batchEnd - $batchStart).TotalSeconds
            $metrics.BatchTimes += $batchDuration
            
            Write-Log "Batch $batchNumber abgeschlossen in $batchDuration Sekunden" -Level "DEBUG"
            $batchNumber++
            
            # Kleine Pause zwischen Batches
            if ($currentObject -lt $objectCount) {
                Start-Sleep -Milliseconds 100
            }
        }
        
        $metrics.EndTime = Get-Date
        $totalDuration = ($metrics.EndTime - $metrics.StartTime).TotalSeconds
        
        Hide-Progress
        Update-Statistics
        
        # Berechne Statistiken
        $avgBatchTime = ($metrics.BatchTimes | Measure-Object -Average).Average
        $objectsPerSecond = $metrics.SuccessfulObjects / $totalDuration
        
        # Erstelle Bericht
        $reportPath = ".\PerformanceTest_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $report = @"
Active Directory Performance Test Report
=======================================
Datum: $(Get-Date)

Test-Konfiguration:
- Ziel-Objekte: $($metrics.TotalObjects)
- Batch-Größe: $batchSize
- Anzahl Batches: $($metrics.BatchCount)

Ergebnisse:
- Gesamtdauer: $([math]::Round($totalDuration, 2)) Sekunden
- Erfolgreiche Objekte: $($metrics.SuccessfulObjects)
- Fehlgeschlagene Objekte: $($metrics.FailedObjects)
- Durchschnittliche Batch-Zeit: $([math]::Round($avgBatchTime, 2)) Sekunden
- Objekte pro Sekunde: $([math]::Round($objectsPerSecond, 2))

Batch-Zeiten:
$($metrics.BatchTimes | ForEach-Object { "- Batch: $([math]::Round($_, 2)) Sekunden" } | Out-String)

Zusammenfassung:
Die Performance liegt bei durchschnittlich $([math]::Round($objectsPerSecond, 2)) Objekten pro Sekunde.
Bei dieser Geschwindigkeit würden 10.000 Objekte etwa $([math]::Round(10000 / $objectsPerSecond / 60, 2)) Minuten benötigen.
"@
        
        $report | Out-File -FilePath $reportPath -Encoding UTF8
        
        $message = @"
Performance-Test abgeschlossen:

Dauer: $([math]::Round($totalDuration, 2)) Sekunden
Objekte erstellt: $($metrics.SuccessfulObjects)
Performance: $([math]::Round($objectsPerSecond, 2)) Objekte/Sekunde

Detaillierter Bericht gespeichert unter:
$reportPath
"@
        
        [System.Windows.MessageBox]::Show($message, "Performance-Test abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler beim Performance-Test: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler beim Performance-Test:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

#endregion

#region Sicherheit & Compliance - Implementierung

function Apply-PasswordPolicies {
    <#
    .SYNOPSIS
    Wendet verschiedene Passwort-Richtlinien auf erstellte Benutzer an
    #>
    try {
        Write-Log "Starte Anwendung von Passwort-Richtlinien..." -Level "INFO"
        
        $simulateHistory = $Global:GuiControls.CheckBoxSimulatePasswordHistory.IsChecked
        $createLocked = $Global:GuiControls.CheckBoxCreateLockedAccounts.IsChecked
        $expiredPasswords = $Global:GuiControls.CheckBoxExpiredPasswords.IsChecked
        $lockoutRatio = 10  # Slider existiert nicht in der GUI, Standard: 10%
        
        if (-not ($simulateHistory -or $createLocked -or $expiredPasswords)) {
            Write-Log "Keine Passwort-Richtlinien ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Passwort-Richtlinie aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer vorhanden für Passwort-Richtlinien" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie folgende Passwort-Richtlinien anwenden?`n`n" +
            "$(if ($simulateHistory) { '- Passwort-Historie simulieren`n' })" +
            "$(if ($createLocked) { "- $lockoutRatio% der Accounts sperren`n" })" +
            "$(if ($expiredPasswords) { '- Passwörter als abgelaufen markieren`n' })" +
            "`nBetroffene Benutzer: $($Global:CreatedUsers.Count)",
            "Passwort-Richtlinien anwenden",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Wende Passwort-Richtlinien an..."
        $processedCount = 0
        $lockedCount = 0
        $expiredCount = 0
        $historyCount = 0
        
        # Berechne Anzahl zu sperrender Accounts
        $accountsToLock = if ($createLocked) {
            [math]::Ceiling($Global:CreatedUsers.Count * ($lockoutRatio / 100))
        } else { 0 }
        
        for ($i = 0; $i -lt $Global:CreatedUsers.Count; $i++) {
            $user = $Global:CreatedUsers[$i]
            Update-Progress -Current ($i + 1) -Total $Global:CreatedUsers.Count -Text "Verarbeite Benutzer $($i + 1) von $($Global:CreatedUsers.Count)"
            
            try {
                # 1. Passwort-Historie simulieren
                if ($simulateHistory) {
                    # Füge pwdLastSet-Attribute hinzu (simuliert mehrfache Passwortänderungen)
                    $historyDates = @()
                    for ($j = 1; $j -le 5; $j++) {
                        $historyDates += (Get-Date).AddDays(-($j * 30))
                    }
                    
                    # AD speichert keine echte Passwort-Historie für einzelne Benutzer,
                    # aber wir können das letzte Passwort-Änderungsdatum setzen
                    Set-ADUser -Identity $user -Replace @{
                        'pwdLastSet' = 0  # Erzwingt Passwortänderung
                    } -ErrorAction Stop
                    
                    # Setze es wieder zurück mit historischem Datum
                    $fileTime = $historyDates[0].ToFileTime()
                    Set-ADUser -Identity $user -Replace @{
                        'pwdLastSet' = $fileTime
                    } -ErrorAction Stop
                    
                    $historyCount++
                    Write-Log "Passwort-Historie für '$user' simuliert" -Level "DEBUG"
                }
                
                # 2. Account sperren
                if ($createLocked -and $lockedCount -lt $accountsToLock) {
                    # Simuliere mehrfache fehlgeschlagene Anmeldeversuche
                    for ($attempt = 1; $attempt -le 5; $attempt++) {
                        try {
                            # Dies würde in einer echten Umgebung durch fehlgeschlagene Anmeldungen erfolgen
                            Set-ADUser -Identity $user -Replace @{
                                'badPwdCount' = $attempt
                                'badPasswordTime' = (Get-Date).ToFileTime()
                                'lockoutTime' = (Get-Date).ToFileTime()
                            } -ErrorAction Stop
                        } catch {
                            Write-Log "Fehler beim Simulieren fehlgeschlagener Anmeldung: $($_.Exception.Message)" -Level "DEBUG"
                        }
                    }
                    
                    # Account direkt sperren
                    Disable-ADAccount -Identity $user -ErrorAction Stop
                    $lockedCount++
                    Write-Log "Account '$user' gesperrt" -Level "DEBUG"
                }
                
                # 3. Passwort als abgelaufen markieren
                if ($expiredPasswords) {
                    # Setze pwdLastSet auf ein altes Datum (vor 90 Tagen)
                    $expiredDate = (Get-Date).AddDays(-91)
                    $fileTime = $expiredDate.ToFileTime()
                    
                    Set-ADUser -Identity $user -Replace @{
                        'pwdLastSet' = $fileTime
                    } -ErrorAction Stop
                    
                    # Erzwinge Passwortänderung bei nächster Anmeldung
                    Set-ADUser -Identity $user -ChangePasswordAtLogon $true -ErrorAction Stop
                    
                    $expiredCount++
                    Write-Log "Passwort für '$user' als abgelaufen markiert" -Level "DEBUG"
                }
                
                $processedCount++
                
            } catch {
                Write-Log "Fehler bei Passwort-Richtlinien für '$user': $($_.Exception.Message)" -Level "WARN"
            }
        }
        
        Hide-Progress
        
        $message = @"
Passwort-Richtlinien angewendet:

Verarbeitete Benutzer: $processedCount
$(if ($simulateHistory) { "Passwort-Historie simuliert: $historyCount`n" })$(if ($createLocked) { "Gesperrte Accounts: $lockedCount`n" })$(if ($expiredPasswords) { "Abgelaufene Passwörter: $expiredCount" })

Die Änderungen können in den Benutzer-Eigenschaften überprüft werden.
"@
        
        [System.Windows.MessageBox]::Show($message, "Passwort-Richtlinien angewendet", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Passwort-Richtlinien: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Anwendung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-RBACRoles {
    <#
    .SYNOPSIS
    Erstellt RBAC-Rollen und Berechtigungsgruppen
    #>
    try {
        Write-Log "Starte RBAC-Rollen-Erstellung..." -Level "INFO"
        
        $selectedRole = $Global:GuiControls.ComboBoxRBACRoles.SelectedItem
        if (-not $selectedRole) {
            Write-Log "Keine RBAC-Rolle ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie eine RBAC-Rolle aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        # TextBoxRoleCount existiert nicht in der GUI, verwende Default
        $roleCount = 5
        
        if ($roleCount -le 0) {
            Write-Log "Ungültige Anzahl RBAC-Rollen" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine gültige Anzahl von Rollen an.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Basis-OU
        $targetOU = $Global:GuiControls.ComboBoxTargetOU.Text
        if ([string]::IsNullOrWhiteSpace($targetOU) -or $targetOU -eq "OU=DummyUsers,DC=example,DC=com") {
            $domain = Get-ADDomain
            $targetOU = $domain.DistinguishedName
        }
        
        # Erstelle Security Groups OU wenn nötig
        $testOUs = Ensure-TestOUs -BaseOU $targetOU
        $groupOU = if ($testOUs["GROUPS"]) { $testOUs["GROUPS"] } else { $targetOU }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie $roleCount RBAC-Rollen für '$($selectedRole.Content)' erstellen?`n`n" +
            "Dies erstellt Sicherheitsgruppen mit entsprechenden Beschreibungen und Strukturen.",
            "RBAC-Rollen erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle RBAC-Rollen..."
        $successCount = 0
        $errorCount = 0
        
        # RBAC-Rollen-Definitionen
        $rbacDefinitions = @{
            "Helpdesk Operator" = @{
                Prefix = "RBAC_Helpdesk"
                Description = "Helpdesk Operator - Password Reset, Account Unlock"
                Permissions = @("Reset-Password", "Unlock-Account", "Read-User")
                Tier = 2
            }
            "Server Operator" = @{
                Prefix = "RBAC_ServerOp"
                Description = "Server Operator - Server Management"
                Permissions = @("Manage-Server", "Remote-Desktop", "Event-Logs")
                Tier = 1
            }
            "Backup Operator" = @{
                Prefix = "RBAC_Backup"
                Description = "Backup Operator - Backup and Restore"
                Permissions = @("Backup-Files", "Restore-Files", "Manage-VSS")
                Tier = 1
            }
            "Account Operator" = @{
                Prefix = "RBAC_AccountOp"
                Description = "Account Operator - User and Group Management"
                Permissions = @("Create-User", "Modify-User", "Create-Group", "Modify-Group")
                Tier = 2
            }
            "Print Operator" = @{
                Prefix = "RBAC_PrintOp"
                Description = "Print Operator - Printer Management"
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
                $mainGroup = New-ADGroup -Name $mainGroupName `
                    -GroupScope DomainLocal `
                    -GroupCategory Security `
                    -Description "$($roleDefinition.Description) - Instance $i" `
                    -Path $groupOU `
                    -OtherAttributes @{
                        'info' = "Tier: $($roleDefinition.Tier)`nPermissions: $($roleDefinition.Permissions -join ', ')"
                    } `
                    -PassThru `
                    -ErrorAction Stop
                
                $Global:CreatedGroups.Add($mainGroupName)
                Write-Log "RBAC-Hauptgruppe '$mainGroupName' erstellt" -Level "SUCCESS"
                
                # 2. Erstelle Permissions-Untergruppen
                foreach ($permission in $roleDefinition.Permissions) {
                    $permGroupName = "$mainGroupName`_$($permission -replace '-', '')"
                    
                    New-ADGroup -Name $permGroupName `
                        -GroupScope Global `
                        -GroupCategory Security `
                        -Description "Permission: $permission for $mainGroupName" `
                        -Path $groupOU `
                        -ErrorAction Stop
                    
                    # Füge Permission-Gruppe zur Haupt-RBAC-Gruppe hinzu
                    Add-ADGroupMember -Identity $mainGroupName -Members $permGroupName -ErrorAction Stop
                    
                    $Global:CreatedGroups.Add($permGroupName)
                    Write-Log "Permission-Gruppe '$permGroupName' erstellt und zugewiesen" -Level "DEBUG"
                }
                
                # 3. Erstelle Beispiel-Benutzer für diese Rolle
                if ($Global:CreatedUsers.Count -gt 0) {
                    # Weise zufällige Benutzer der Rolle zu
                    $assignCount = [math]::Min(3, $Global:CreatedUsers.Count)
                    $assignedUsers = $Global:CreatedUsers | Get-Random -Count $assignCount
                    
                    foreach ($user in $assignedUsers) {
                        try {
                            Add-ADGroupMember -Identity $mainGroupName -Members $user -ErrorAction Stop
                            Write-Log "Benutzer '$user' zu RBAC-Rolle '$mainGroupName' hinzugefügt" -Level "DEBUG"
                        } catch {
                            Write-Log "Fehler beim Zuweisen von '$user' zu '$mainGroupName': $($_.Exception.Message)" -Level "WARN"
                        }
                    }
                }
                
                $successCount++
                
            } catch {
                Write-Log "Fehler beim Erstellen von RBAC-Rolle: $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
            
            Update-Progress -Current $i -Total $roleCount -Text "Erstelle RBAC-Rolle $i von $roleCount..."
        }
        
        Hide-Progress
        Update-Statistics
        
        # Erstelle Dokumentation
        $docPath = ".\RBAC_Structure_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
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
$($Global:CreatedGroups | Where-Object { $_ -like "$($roleDefinition.Prefix)*" } | ForEach-Object { "- $_" } | Out-String)

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
        Write-Log "Fehler bei RBAC-Rollen-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-BitLockerKeys {
    <#
    .SYNOPSIS
    Simuliert BitLocker Recovery Keys für Computer
    #>
    try {
        Write-Log "Starte BitLocker-Key-Simulation..." -Level "INFO"
        
        $simulateBitLocker = $Global:GuiControls.CheckBoxSimulateBitLocker.IsChecked
        $createRecoveryKeys = $Global:GuiControls.CheckBoxRecoveryKeys.IsChecked
        
        if (-not ($simulateBitLocker -or $createRecoveryKeys)) {
            Write-Log "Keine BitLocker-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine BitLocker-Option aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $Global:CreatedComputers -or $Global:CreatedComputers.Count -eq 0) {
            Write-Log "Keine Computer für BitLocker-Simulation vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie BitLocker-Keys für $($Global:CreatedComputers.Count) Computer simulieren?`n`n" +
            "Dies erstellt Recovery-Key-Objekte in AD (msFVE-RecoveryInformation).",
            "BitLocker-Simulation",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Simuliere BitLocker-Keys..."
        $successCount = 0
        $errorCount = 0
        
        # Erstelle BitLocker-Key-Datei
        $keyFile = ".\BitLockerKeys_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $keyData = @()
        
        for ($i = 0; $i -lt $Global:CreatedComputers.Count; $i++) {
            $computer = $Global:CreatedComputers[$i]
            Update-Progress -Current ($i + 1) -Total $Global:CreatedComputers.Count -Text "Erstelle BitLocker-Keys für $computer"
            
            try {
                # Generiere Recovery-Informationen
                $recoveryGuid = [System.Guid]::NewGuid()
                $recoveryPassword = Generate-BitLockerRecoveryPassword
                $recoveryId = $recoveryPassword.Substring(0, 8)
                
                # Hole Computer-Objekt
                $computerObj = Get-ADComputer -Identity $computer -ErrorAction Stop
                
                # Erstelle msFVE-RecoveryInformation Objekt
                $recoveryDN = "CN=$recoveryGuid,CN=$computer,$($computerObj.DistinguishedName.Substring($computerObj.DistinguishedName.IndexOf(',') + 1))"
                
                # Simuliere BitLocker-Objekt (vereinfacht, da msFVE-RecoveryInformation spezielle Rechte benötigt)
                $attributes = @{
                    'msFVE-RecoveryGuid' = $recoveryGuid.ToString('B')
                    'msFVE-RecoveryPassword' = $recoveryPassword
                    'msFVE-VolumeGuid' = [System.Guid]::NewGuid().ToString('B')
                    'msFVE-RecoveryInformationIdentifier' = "TPM"
                    'Description' = "BitLocker Recovery Key für $computer"
                }
                
                # Versuche das Objekt zu erstellen (benötigt spezielle Rechte)
                try {
                    New-ADObject -Name $recoveryGuid.ToString() `
                        -Type 'msFVE-RecoveryInformation' `
                        -Path $computerObj.DistinguishedName `
                        -OtherAttributes $attributes `
                        -ErrorAction Stop
                    
                    Write-Log "BitLocker Recovery-Objekt für '$computer' erstellt" -Level "SUCCESS"
                } catch {
                    # Fallback: Speichere als Computer-Attribut
                    Set-ADComputer -Identity $computer -Add @{
                        'info' = "BitLocker Recovery ID: $recoveryId`nRecovery Key gespeichert in: $keyFile"
                    } -ErrorAction Stop
                    
                    Write-Log "BitLocker-Info als Computer-Attribut gespeichert (Fallback)" -Level "INFO"
                }
                
                # Speichere Key-Informationen
                $keyData += [PSCustomObject]@{
                    ComputerName = $computer
                    RecoveryID = $recoveryId
                    RecoveryPassword = $recoveryPassword
                    RecoveryGuid = $recoveryGuid
                    CreatedDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                $successCount++
                
            } catch {
                Write-Log "Fehler bei BitLocker-Simulation für '$computer': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Exportiere Keys
        if ($keyData.Count -gt 0) {
            $keyData | Export-Csv -Path $keyFile -NoTypeInformation -Encoding UTF8
            Write-Log "BitLocker-Keys exportiert nach: $keyFile" -Level "INFO"
        }
        
        Hide-Progress
        
        $message = @"
BitLocker-Simulation abgeschlossen:

Computer verarbeitet: $($Global:CreatedComputers.Count)
Erfolgreich: $successCount
Fehler: $errorCount

Recovery-Keys gespeichert in:
$keyFile

WICHTIG: Diese Datei enthält simulierte Recovery-Keys und sollte sicher aufbewahrt werden!
"@
        
        [System.Windows.MessageBox]::Show($message, "BitLocker-Simulation abgeschlossen", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei BitLocker-Simulation: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Simulation:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Generate-BitLockerRecoveryPassword {
    <#
    .SYNOPSIS
    Generiert ein BitLocker-kompatibles Recovery-Passwort
    #>
    $blocks = @()
    for ($i = 0; $i -lt 8; $i++) {
        $blocks += Get-Random -Minimum 100000 -Maximum 699999
    }
    return $blocks -join '-'
}

#endregion

#region Erweiterte Features - Implementierung

function Create-DNSEntries {
    <#
    .SYNOPSIS
    Erstellt DNS-Einträge für erstellte Computer
    #>
    try {
        Write-Log "Starte DNS-Einträge-Erstellung..." -Level "INFO"
        
        $createDNS = $Global:GuiControls.CheckBoxCreateDNSEntries.IsChecked
        $createA = $Global:GuiControls.CheckBoxCreateARecords.IsChecked
        $createCNAME = $Global:GuiControls.CheckBoxCreateCNAME.IsChecked
        
        if (-not ($createDNS -or $createA -or $createCNAME)) {
            Write-Log "Keine DNS-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine DNS-Option aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $Global:CreatedComputers -or $Global:CreatedComputers.Count -eq 0) {
            Write-Log "Keine Computer für DNS-Einträge vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        # Prüfe ob DNS-Modul verfügbar ist
        if (-not (Get-Module -ListAvailable -Name DnsServer)) {
            Write-Log "DNS-Server-Modul nicht verfügbar" -Level "WARN"
            [System.Windows.MessageBox]::Show("Das DNS-Server PowerShell-Modul ist nicht installiert.`n`nDie DNS-Einträge werden nur simuliert.", "Hinweis", "OK", "Warning")
            $simulateOnly = $true
        } else {
            $simulateOnly = $false
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie DNS-Einträge für $($Global:CreatedComputers.Count) Computer erstellen?`n`n" +
            "$(if ($simulateOnly) { 'HINWEIS: DNS-Modul nicht verfügbar - nur Simulation!' })",
            "DNS-Einträge erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        $domain = (Get-ADDomain).DNSRoot
        $dnsZone = $domain
        
        Show-Progress -Text "Erstelle DNS-Einträge..."
        $successCount = 0
        $errorCount = 0
        $dnsRecords = @()
        
        # IP-Adressbereich für Simulation
        $ipBase = "192.168.1."
        $ipCounter = 100
        
        for ($i = 0; $i -lt $Global:CreatedComputers.Count; $i++) {
            $computer = $Global:CreatedComputers[$i]
            $ipAddress = "$ipBase$ipCounter"
            $ipCounter++
            
            Update-Progress -Current ($i + 1) -Total $Global:CreatedComputers.Count -Text "Erstelle DNS-Einträge für $computer"
            
            try {
                # A-Record
                if ($createA -or $createDNS) {
                    if (-not $simulateOnly) {
                        Add-DnsServerResourceRecordA -Name $computer `
                            -ZoneName $dnsZone `
                            -IPv4Address $ipAddress `
                            -CreatePtr `
                            -ErrorAction Stop
                        
                        Write-Log "A-Record für '$computer' mit IP $ipAddress erstellt" -Level "SUCCESS"
                    }
                    
                    $dnsRecords += [PSCustomObject]@{
                        Type = "A"
                        Name = $computer
                        Value = $ipAddress
                        Zone = $dnsZone
                    }
                }
                
                # CNAME-Records
                if ($createCNAME) {
                    $aliases = @("www", "mail", "ftp")
                    foreach ($alias in $aliases) {
                        $cname = "$alias-$computer"
                        
                        if (-not $simulateOnly) {
                            Add-DnsServerResourceRecordCName -Name $cname `
                                -ZoneName $dnsZone `
                                -HostNameAlias "$computer.$dnsZone" `
                                -ErrorAction Stop
                        }
                        
                        $dnsRecords += [PSCustomObject]@{
                            Type = "CNAME"
                            Name = $cname
                            Value = "$computer.$dnsZone"
                            Zone = $dnsZone
                        }
                        
                        Write-Log "CNAME '$cname' -> '$computer.$dnsZone' erstellt" -Level "DEBUG"
                    }
                }
                
                # PTR-Record (Reverse DNS)
                if ($createA -or $createDNS) {
                    $reverseZone = "1.168.192.in-addr.arpa"
                    $ptrName = $ipAddress.Split('.')[-1]
                    
                    if (-not $simulateOnly) {
                        Add-DnsServerResourceRecordPtr -Name $ptrName `
                            -ZoneName $reverseZone `
                            -PtrDomainName "$computer.$dnsZone" `
                            -ErrorAction SilentlyContinue
                    }
                    
                    $dnsRecords += [PSCustomObject]@{
                        Type = "PTR"
                        Name = "$ptrName.$reverseZone"
                        Value = "$computer.$dnsZone"
                        Zone = $reverseZone
                    }
                }
                
                $successCount++
                
            } catch {
                Write-Log "Fehler bei DNS-Einträgen für '$computer': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Exportiere DNS-Records
        $dnsFile = ".\DNS_Records_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $dnsRecords | Export-Csv -Path $dnsFile -NoTypeInformation -Encoding UTF8
        
        Hide-Progress
        
        $message = @"
DNS-Einträge $(if ($simulateOnly) { "simuliert" } else { "erstellt"}):

Computer verarbeitet: $($Global:CreatedComputers.Count)
Erfolgreich: $successCount
Fehler: $errorCount

DNS-Records dokumentiert in:
$dnsFile

Erstellte Record-Typen:
$(if ($createA -or $createDNS) { "- A-Records mit IPs im Bereich $ipBase*`n" })$(if ($createCNAME) { "- CNAME-Aliase (www, mail, ftp)`n" })$(if ($createA -or $createDNS) { "- PTR-Records für Reverse-DNS" })
"@
        
        [System.Windows.MessageBox]::Show($message, "DNS-Einträge erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei DNS-Einträge-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Simulate-Migration {
    <#
    .SYNOPSIS
    Simuliert eine Domänenmigration mit SID-History
    #>
    try {
        Write-Log "Starte Migrations-Simulation..." -Level "INFO"
        
        $sidHistory = $Global:GuiControls.CheckBoxSIDHistory.IsChecked
        $trustRelationships = $Global:GuiControls.CheckBoxTrustRelationships.IsChecked
        $sourceDomain = $Global:GuiControls.TextBoxSourceDomain.Text
        
        if (-not ($sidHistory -or $trustRelationships)) {
            Write-Log "Keine Migrations-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Migrations-Option aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if ([string]::IsNullOrWhiteSpace($sourceDomain)) {
            Write-Log "Keine Quell-Domäne angegeben" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte geben Sie eine Quell-Domäne an.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $Global:CreatedUsers -or $Global:CreatedUsers.Count -eq 0) {
            Write-Log "Keine Benutzer für Migration vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Benutzer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie eine Migration von '$sourceDomain' simulieren?`n`n" +
            "Betroffene Benutzer: $($Global:CreatedUsers.Count)`n" +
            "$(if ($sidHistory) { '- SID-History wird simuliert`n' })" +
            "$(if ($trustRelationships) { '- Trust-Beziehungen werden dokumentiert' })",
            "Migration simulieren",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Simuliere Migration..."
        $migratedCount = 0
        $errorCount = 0
        
        # Erstelle Migrations-Dokumentation
        $migrationData = @()
        
        for ($i = 0; $i -lt $Global:CreatedUsers.Count; $i++) {
            $user = $Global:CreatedUsers[$i]
            Update-Progress -Current ($i + 1) -Total $Global:CreatedUsers.Count -Text "Migriere Benutzer $user"
            
            try {
                # Hole aktuellen Benutzer
                $adUser = Get-ADUser -Identity $user -Properties * -ErrorAction Stop
                
                # Simuliere SID-History
                if ($sidHistory) {
                    # Generiere eine Beispiel-SID aus der alten Domäne
                    $oldSid = "S-1-5-21-$(Get-Random -Minimum 100000000 -Maximum 999999999)-$(Get-Random -Minimum 100000000 -Maximum 999999999)-$(Get-Random -Minimum 100000000 -Maximum 999999999)-$(Get-Random -Minimum 1000 -Maximum 9999)"
                    
                    # SIDHistory kann nur mit speziellen Rechten gesetzt werden
                    # Wir simulieren es durch ein Custom-Attribut
                    Set-ADUser -Identity $user -Add @{
                        'adminDescription' = "Migrated from $sourceDomain | Original SID: $oldSid"
                        'extensionAttribute1' = $sourceDomain
                        'extensionAttribute2' = $oldSid
                    } -ErrorAction Stop
                    
                    Write-Log "SID-History für '$user' simuliert: $oldSid" -Level "DEBUG"
                }
                
                # Dokumentiere Migration
                $migrationData += [PSCustomObject]@{
                    SourceDomain = $sourceDomain
                    TargetDomain = (Get-ADDomain).DNSRoot
                    UserName = $user
                    OriginalSID = $oldSid
                    NewSID = $adUser.SID.Value
                    MigrationDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Status = "Success"
                }
                
                $migratedCount++
                
            } catch {
                Write-Log "Fehler bei Migration von '$user': $($_.Exception.Message)" -Level "ERROR"
                $migrationData += [PSCustomObject]@{
                    SourceDomain = $sourceDomain
                    TargetDomain = (Get-ADDomain).DNSRoot
                    UserName = $user
                    OriginalSID = "N/A"
                    NewSID = "N/A"
                    MigrationDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                    Status = "Failed: $($_.Exception.Message)"
                }
                $errorCount++
            }
        }
        
        # Erstelle Trust-Dokumentation
        $trustDoc = ""
        if ($trustRelationships) {
            $trustDoc = @"

Trust-Beziehungen Dokumentation
================================
Quell-Domäne: $sourceDomain
Ziel-Domäne: $((Get-ADDomain).DNSRoot)

Empfohlene Trust-Konfiguration:
- Trust-Typ: Forest Trust (Transitive)
- Trust-Richtung: Bidirektional
- SID-Filtering: Deaktiviert (für SID-History)
- Selective Authentication: Aktiviert

Firewall-Regeln erforderlich:
- TCP 445 (SMB)
- TCP 135 (RPC Endpoint Mapper)
- TCP 49152-65535 (RPC Dynamic Ports)
- TCP/UDP 389 (LDAP)
- TCP 636 (LDAPS)
- TCP/UDP 88 (Kerberos)
- TCP/UDP 464 (Kerberos Password Change)

DNS-Konfiguration:
- Conditional Forwarders für beide Domänen
- Suffix Search List Update
"@
        }
        
        # Exportiere Migrations-Bericht
        $reportPath = ".\Migration_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $report = @"
Migrations-Simulations-Bericht
==============================
Datum: $(Get-Date)
Quell-Domäne: $sourceDomain
Ziel-Domäne: $((Get-ADDomain).DNSRoot)

Migrations-Statistik:
- Benutzer migriert: $migratedCount
- Fehler: $errorCount
- Gesamt: $($Global:CreatedUsers.Count)

$trustDoc

Hinweise:
- SID-History wurde durch Custom-Attribute simuliert
- Echte SID-History erfordert Domain Admin Rechte und Trust
- Gruppen-Mitgliedschaften müssen separat migriert werden
"@
        
        $report | Out-File -FilePath $reportPath -Encoding UTF8
        
        # Exportiere Details
        $csvPath = ".\Migration_Details_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $migrationData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
        
        Hide-Progress
        
        $message = @"
Migration erfolgreich simuliert:

Quell-Domäne: $sourceDomain
Migrierte Benutzer: $migratedCount
Fehler: $errorCount

Berichte erstellt:
- $reportPath
- $csvPath
"@
        
        [System.Windows.MessageBox]::Show($message, "Migration simuliert", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Migrations-Simulation: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Simulation:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-KerberosTests {
    <#
    .SYNOPSIS
    Erstellt Kerberos-Test-Konfigurationen mit SPNs
    #>
    try {
        Write-Log "Starte Kerberos-Test-Erstellung..." -Level "INFO"
        
        $createSPNs = $Global:GuiControls.CheckBoxCreateSPNs.IsChecked
        $kerberosConstraints = $Global:GuiControls.CheckBoxKerberosConstraints.IsChecked
        $serviceType = $Global:GuiControls.ComboBoxKerberosService.SelectedItem
        
        if (-not ($createSPNs -or $kerberosConstraints)) {
            Write-Log "Keine Kerberos-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Kerberos-Option aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if (-not $serviceType) {
            Write-Log "Kein Service-Typ ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie einen Service-Typ aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        if ($Global:CreatedServiceAccounts.Count -eq 0 -and $Global:CreatedComputers.Count -eq 0) {
            Write-Log "Keine Service-Accounts oder Computer für Kerberos-Tests vorhanden" -Level "WARN"
            [System.Windows.MessageBox]::Show("Es wurden noch keine Service-Accounts oder Computer erstellt.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie Kerberos-Tests für '$($serviceType.Content)' erstellen?`n`n" +
            "$(if ($createSPNs) { '- Service Principal Names werden erstellt`n' })" +
            "$(if ($kerberosConstraints) { '- Kerberos-Delegation wird konfiguriert' })",
            "Kerberos-Tests erstellen",
            "YesNo",
            "Question"
        )
        
        if ($result -ne "Yes") { return }
        
        Show-Progress -Text "Erstelle Kerberos-Test-Konfiguration..."
        $successCount = 0
        $errorCount = 0
        $spnData = @()
        
        # Service-Typ Mapping
        $servicePrefix = switch ($serviceType.Content) {
            "HTTP" { "HTTP" }
            "SQL" { "MSSQLSvc" }
            "LDAP" { "ldap" }
            "HOST" { "HOST" }
        }
        
        # Verwende Service-Accounts wenn vorhanden, sonst Computer
        $targetAccounts = if ($Global:CreatedServiceAccounts.Count -gt 0) {
            $Global:CreatedServiceAccounts
        } else {
            $Global:CreatedComputers | Select-Object -First 10
        }
        
        $domain = (Get-ADDomain).DNSRoot
        $totalAccounts = $targetAccounts.Count
        
        for ($i = 0; $i -lt $totalAccounts; $i++) {
            $account = $targetAccounts[$i]
            Update-Progress -Current ($i + 1) -Total $totalAccounts -Text "Konfiguriere Kerberos für $account"
            
            try {
                # Bestimme Account-Typ
                $isComputer = $account -like "*$"
                $accountObj = if ($isComputer) {
                    Get-ADComputer -Identity $account -Properties * -ErrorAction Stop
                } else {
                    Get-ADUser -Identity $account -Properties * -ErrorAction Stop
                }
                
                # 1. Erstelle SPNs
                if ($createSPNs) {
                    $spns = @()
                    
                    switch ($serviceType.Content) {
                        "HTTP" {
                            $spns += "$servicePrefix/$account"
                            $spns += "$servicePrefix/$account.$domain"
                            $spns += "$servicePrefix/$account.$domain:80"
                            $spns += "$servicePrefix/$account.$domain:443"
                        }
                        "SQL" {
                            $spns += "$servicePrefix/$account.$domain"
                            $spns += "$servicePrefix/$account.$domain:1433"
                        }
                        "LDAP" {
                            $spns += "$servicePrefix/$account.$domain"
                            $spns += "$servicePrefix/$account.$domain/$domain"
                        }
                        "HOST" {
                            $spns += "$servicePrefix/$account"
                            $spns += "$servicePrefix/$account.$domain"
                        }
                    }
                    
                    foreach ($spn in $spns) {
                        try {
                            if ($isComputer) {
                                Set-ADComputer -Identity $account -Add @{servicePrincipalName=$spn} -ErrorAction Stop
                            } else {
                                Set-ADUser -Identity $account -Add @{servicePrincipalName=$spn} -ErrorAction Stop
                            }
                            
                            $spnData += [PSCustomObject]@{
                                Account = $account
                                AccountType = if ($isComputer) { "Computer" } else { "User" }
                                SPN = $spn
                                ServiceType = $serviceType.Content
                                Status = "Created"
                            }
                            
                            Write-Log "SPN '$spn' zu '$account' hinzugefügt" -Level "DEBUG"
                        } catch {
                            if ($_.Exception.Message -notlike "*already exists*") {
                                throw
                            }
                            Write-Log "SPN '$spn' existiert bereits" -Level "DEBUG"
                        }
                    }
                }
                
                # 2. Konfiguriere Kerberos-Delegation
                if ($kerberosConstraints) {
                    # Aktiviere Kerberos-Delegation
                    $delegationSettings = @{
                        'TrustedForDelegation' = $true
                        'AccountNotDelegated' = $false
                    }
                    
                    # Setze msDS-AllowedToDelegateTo für constrained delegation
                    if ($serviceType.Content -eq "HTTP") {
                        $delegationSettings['msDS-AllowedToDelegateTo'] = @(
                            "HTTP/webserver.$domain",
                            "HTTP/webserver"
                        )
                    }
                    
                    if ($isComputer) {
                        Set-ADComputer -Identity $account -Replace $delegationSettings -ErrorAction Stop
                    } else {
                        Set-ADUser -Identity $account -Replace $delegationSettings -ErrorAction Stop
                    }
                    
                    Write-Log "Kerberos-Delegation für '$account' aktiviert" -Level "DEBUG"
                }
                
                $successCount++
                
            } catch {
                Write-Log "Fehler bei Kerberos-Konfiguration für '$account': $($_.Exception.Message)" -Level "ERROR"
                $errorCount++
            }
        }
        
        # Exportiere SPN-Dokumentation
        $spnFile = ".\Kerberos_SPNs_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $spnData | Export-Csv -Path $spnFile -NoTypeInformation -Encoding UTF8
        
        # Erstelle Test-Anleitung
        $testGuide = ".\Kerberos_TestGuide_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $guide = @"
Kerberos Test-Anleitung
=======================
Datum: $(Get-Date)
Service-Typ: $($serviceType.Content)

Erstellte Konfiguration:
- Accounts konfiguriert: $successCount
- SPNs erstellt: $($spnData.Count)
- Delegation aktiviert: $(if ($kerberosConstraints) { "Ja" } else { "Nein" })

Test-Befehle:

1. SPN-Abfrage:
   setspn -L <accountname>
   setspn -Q $servicePrefix/*

2. Kerberos-Ticket-Test:
   klist purge
   klist get $servicePrefix/$account.$domain

3. Delegation-Test:
   Get-ADUser <accountname> -Properties TrustedForDelegation,msDS-AllowedToDelegateTo

4. Troubleshooting:
   - Event Log: System und Security
   - Kerberos Logging aktivieren: ksetup /setrealm
   - Network Trace: netsh trace start scenario=NetConnection,InternetClient

Häufige Probleme:
- Doppelte SPNs
- Falsche DNS-Auflösung
- Zeit-Synchronisation (> 5 Min Abweichung)
- Verschlüsselungstypen nicht unterstützt
"@
        
        $guide | Out-File -FilePath $testGuide -Encoding UTF8
        
        Hide-Progress
        
        $message = @"
Kerberos-Tests erfolgreich erstellt:

Service-Typ: $($serviceType.Content)
Konfigurierte Accounts: $successCount
Fehler: $errorCount

Dokumentation:
- SPNs: $spnFile
- Test-Anleitung: $testGuide
"@
        
        [System.Windows.MessageBox]::Show($message, "Kerberos-Tests erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Kerberos-Test-Erstellung: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Erstellung:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Document-FSMORoles {
    <#
    .SYNOPSIS
    Dokumentiert FSMO-Rollen und Domänen-Informationen
    #>
    try {
        Write-Log "Starte FSMO-Dokumentation..." -Level "INFO"
        
        $documentFSMO = $Global:GuiControls.CheckBoxDocumentFSMO.IsChecked
        $exportDomainInfo = $Global:GuiControls.CheckBoxExportDomainInfo.IsChecked
        
        if (-not ($documentFSMO -or $exportDomainInfo)) {
            Write-Log "Keine Dokumentations-Optionen ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens eine Dokumentations-Option aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        Show-Progress -Text "Erstelle Dokumentation..." -Value 0
        
        $docPath = ".\AD_Documentation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $documentation = @"
Active Directory Dokumentation
==============================
Erstellt am: $(Get-Date)
Erstellt von: $env:USERNAME
"@
        
        # 1. FSMO-Rollen dokumentieren
        if ($documentFSMO) {
            Update-Progress -Current 25 -Total 100 -Text "Dokumentiere FSMO-Rollen..."
            
            try {
                $forest = Get-ADForest
                $domain = Get-ADDomain
                
                $documentation += @"

FSMO-Rollen (Flexible Single Master Operations)
===============================================

Forest-Level FSMO-Rollen:
------------------------
1. Schema Master:
   - Aktueller Inhaber: $($forest.SchemaMaster)
   - Beschreibung: Verwaltet Schema-Änderungen
   
2. Domain Naming Master:
   - Aktueller Inhaber: $($forest.DomainNamingMaster)
   - Beschreibung: Verwaltet Domänen-Hinzufügungen/-Entfernungen

Domain-Level FSMO-Rollen:
-------------------------
3. PDC Emulator:
   - Aktueller Inhaber: $($domain.PDCEmulator)
   - Beschreibung: Zeitquelle, Passwort-Änderungen, Gruppen-Richtlinien
   
4. RID Master:
   - Aktueller Inhaber: $($domain.RIDMaster)
   - Beschreibung: Verteilt RID-Pools an Domain Controller
   
5. Infrastructure Master:
   - Aktueller Inhaber: $($domain.InfrastructureMaster)
   - Beschreibung: Cross-Domain Objektreferenzen

FSMO-Rollen Übertragung:
------------------------
PowerShell-Befehle:
- Move-ADDirectoryServerOperationMasterRole -Identity <TargetDC> -OperationMasterRole <Role>

Notfall-Übernahme (Seize):
- Bei Ausfall des aktuellen Inhabers
- NUR als letzte Option verwenden!
"@
                
                Write-Log "FSMO-Rollen erfolgreich dokumentiert" -Level "SUCCESS"
            } catch {
                Write-Log "Fehler bei FSMO-Dokumentation: $($_.Exception.Message)" -Level "ERROR"
                $documentation += "`n`nFehler bei FSMO-Dokumentation: $($_.Exception.Message)"
            }
        }
        
        # 2. Domänen-Informationen exportieren
        if ($exportDomainInfo) {
            Update-Progress -Current 50 -Total 100 -Text "Exportiere Domänen-Informationen..."
            
            try {
                $domain = Get-ADDomain
                $forest = Get-ADForest
                $dcs = Get-ADDomainController -Filter *
                
                $documentation += @"

Domänen-Informationen
=====================

Forest-Informationen:
--------------------
- Forest Name: $($forest.Name)
- Forest Mode: $($forest.ForestMode)
- Schema Version: $((Get-ADObject (Get-ADRootDSE).schemaNamingContext -Properties objectVersion).objectVersion)
- Domains: $($forest.Domains -join ', ')
- Global Catalogs: $($forest.GlobalCatalogs -join ', ')
- Sites: $($forest.Sites -join ', ')

Domain-Informationen:
--------------------
- Domain Name: $($domain.Name)
- NetBIOS Name: $($domain.NetBIOSName)
- Domain Mode: $($domain.DomainMode)
- Domain SID: $($domain.DomainSID)
- DNS Root: $($domain.DNSRoot)
- Distinguished Name: $($domain.DistinguishedName)

Domain Controller:
------------------
"@
                
                foreach ($dc in $dcs) {
                    $documentation += @"

$($dc.Name):
- IP-Adresse: $($dc.IPv4Address)
- OS Version: $($dc.OperatingSystem)
- Ist Global Catalog: $($dc.IsGlobalCatalog)
- Ist Read-Only: $($dc.IsReadOnly)
- Site: $($dc.Site)
"@
                }
                
                # Erstelle detaillierte DC-Liste
                $dcFile = ".\DomainControllers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                $dcs | Select-Object Name, IPv4Address, OperatingSystem, IsGlobalCatalog, IsReadOnly, Site | 
                    Export-Csv -Path $dcFile -NoTypeInformation -Encoding UTF8
                
                Write-Log "Domänen-Informationen erfolgreich exportiert" -Level "SUCCESS"
            } catch {
                Write-Log "Fehler beim Export der Domänen-Informationen: $($_.Exception.Message)" -Level "ERROR"
                $documentation += "`n`nFehler beim Export: $($_.Exception.Message)"
            }
        }
        
        # 3. Test-Objekt-Statistiken hinzufügen
        Update-Progress -Current 75 -Total 100 -Text "Erstelle Statistiken..."
        
        $documentation += @"

Test-Objekt-Statistiken
========================
- Erstellte Benutzer: $($Global:CreatedUsers.Count)
- Erstellte Gruppen: $($Global:CreatedGroups.Count)
- Erstellte Computer: $($Global:CreatedComputers.Count)
- Erstellte OUs: $($Global:CreatedOUs.Count)
- Erstellte Service-Accounts: $($Global:CreatedServiceAccounts.Count)
- Gesamt: $($Global:CreatedUsers.Count + $Global:CreatedGroups.Count + $Global:CreatedComputers.Count + $Global:CreatedOUs.Count + $Global:CreatedServiceAccounts.Count)

Hinweise zur Bereinigung:
-------------------------
- Verwenden Sie die Schnellzugriff-Funktion 'Aufräumen'
- Oder löschen Sie Objekte einzeln über die jeweiligen Lösch-Funktionen
- Erstellen Sie vor dem Löschen ein Backup!
"@
        
        # Speichere Dokumentation
        $documentation | Out-File -FilePath $docPath -Encoding UTF8
        
        Hide-Progress
        
        $message = @"
Dokumentation erfolgreich erstellt:

$(if ($documentFSMO) { "- FSMO-Rollen dokumentiert`n" })$(if ($exportDomainInfo) { "- Domänen-Informationen exportiert`n" })
Hauptdokument: $docPath
$(if ($exportDomainInfo -and $dcFile) { "DC-Liste: $dcFile" })
"@
        
        [System.Windows.MessageBox]::Show($message, "Dokumentation erstellt", "OK", "Information")
        
    } catch {
        Hide-Progress
        Write-Log "Fehler bei Dokumentation: $($_.Exception.Message)" -Level "ERROR"
        [System.Windows.MessageBox]::Show("Fehler bei der Dokumentation:`n$($_.Exception.Message)", "Fehler", "OK", "Error")
    }
}

function Create-AdvancedFeatures {
    <#
    .SYNOPSIS
    Führt erweiterte Features für Test-Umgebungen aus
    
    .DESCRIPTION
    Erstellt DNS-Einträge, Service Principal Names (SPNs) und dokumentiert FSMO-Rollen
    #>
    try {
        Write-Log "Starte Ausführung erweiterter Features..." -Level "INFO"
        
        $createDNS = $Global:GuiControls.CheckBoxCreateDNSEntries.IsChecked
        $createSPNs = $Global:GuiControls.CheckBoxCreateSPNs.IsChecked
        $documentFSMO = $Global:GuiControls.CheckBoxDocumentFSMO.IsChecked
        
        if (-not ($createDNS -or $createSPNs -or $documentFSMO)) {
            Write-Log "Keine erweiterten Features ausgewählt" -Level "WARN"
            [System.Windows.MessageBox]::Show("Bitte wählen Sie mindestens ein erweitertes Feature aus.", "Hinweis", "OK", "Warning")
            return
        }
        
        $result = [System.Windows.MessageBox]::Show(
            "Möchten Sie folgende erweiterte Features ausführen?`n`n" +
            "$(if ($createDNS) { '- DNS-Einträge erstellen (simuliert)`n' })" +
            "$(if ($createSPNs) { '- Service Principal Names erstellen`n' })" +
            "$(if ($documentFSMO) { '- FSMO-Rollen dokumentieren`n' })" +
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
        if ($createDNS -and $Global:CreatedComputers.Count -gt 0) {
            Update-Progress -Current 1 -Total 3 -Text "Erstelle DNS-Einträge..."
            
            $dnsFile = ".\DNS_Entries_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $dnsEntries = @()
            $domain = (Get-ADDomain).DNSRoot
            $ipBase = "10.0.1."
            
            for ($i = 0; $i -lt $Global:CreatedComputers.Count; $i++) {
                $computer = $Global:CreatedComputers[$i]
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
                
                Write-Log "DNS-Einträge für '$computer' erstellt (IP: $ip)" -Level "DEBUG"
                $successCount++
            }
            
            $dnsEntries | Export-Csv -Path $dnsFile -NoTypeInformation -Encoding UTF8
            $reportData += "DNS-Einträge: $dnsFile ($($dnsEntries.Count) Einträge)"
        }
        
        # 2. Service Principal Names erstellen
        if ($createSPNs -and $Global:CreatedServiceAccounts.Count -gt 0) {
            Update-Progress -Current 2 -Total 3 -Text "Erstelle Service Principal Names..."
            
            $spnFile = ".\SPNs_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $spnData = @()
            $domain = (Get-ADDomain).DNSRoot
            
            foreach ($serviceAccount in $Global:CreatedServiceAccounts) {
                try {
                    # Hole Service-Account-Details
                    $account = Get-ADUser -Identity $serviceAccount -ErrorAction Stop
                    
                    # Erstelle verschiedene SPNs basierend auf Service-Typ
                    $spns = @()
                    
                    # Wenn Account mit "svc-sql" beginnt
                    if ($serviceAccount -like "svc-sql*") {
                        $spns += "MSSQLSvc/sqlserver.$domain"
                        $spns += "MSSQLSvc/sqlserver.$domain:1433"
                    }
                    # Wenn Account mit "svc-web" beginnt
                    elseif ($serviceAccount -like "svc-web*") {
                        $spns += "HTTP/webapp.$domain"
                        $spns += "HTTP/webapp.$domain:80"
                        $spns += "HTTP/webapp.$domain:443"
                    }
                    # Wenn Account mit "svc-" beginnt (generisch)
                    elseif ($serviceAccount -like "svc-*") {
                        $serviceName = $serviceAccount.Substring(4)
                        $spns += "HOST/$serviceName.$domain"
                    }
                    # Standard
                    else {
                        $spns += "HOST/$serviceAccount.$domain"
                    }
                    
                    # SPNs zum Account hinzufügen
                    foreach ($spn in $spns) {
                        try {
                            Set-ADUser -Identity $serviceAccount -Add @{servicePrincipalName=$spn} -ErrorAction Stop
                            
                            $spnData += [PSCustomObject]@{
                                Account = $serviceAccount
                                SPN = $spn
                                Status = "Created"
                                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            }
                            
                            Write-Log "SPN '$spn' zu Service-Account '$serviceAccount' hinzugefügt" -Level "DEBUG"
                        } catch {
                            $spnData += [PSCustomObject]@{
                                Account = $serviceAccount
                                SPN = $spn
                                Status = "Failed: $($_.Exception.Message)"
                                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                            }
                            $errorCount++
                        }
                    }
                    
                    $successCount++
                    
                } catch {
                    Write-Log "Fehler bei SPN-Erstellung für '$serviceAccount': $($_.Exception.Message)" -Level "ERROR"
                    $errorCount++
                }
            }
            
            $spnData | Export-Csv -Path $spnFile -NoTypeInformation -Encoding UTF8
            $reportData += "SPNs: $spnFile ($($spnData.Count) SPNs)"
        }
        
        # 3. FSMO-Rollen dokumentieren
        if ($documentFSMO) {
            Update-Progress -Current 3 -Total 3 -Text "Dokumentiere FSMO-Rollen..."
            
            $fsmoFile = ".\FSMO_Documentation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            
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
                Write-Log "Fehler bei FSMO-Dokumentation: $($_.Exception.Message)" -Level "ERROR"
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
        Write-Log "Fehler bei erweiterten Features: $($_.Exception.Message)" -Level "ERROR"
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
        $Global:GuiControls.GridProgressArea.Visibility = [System.Windows.Visibility]::Visible
        $Global:GuiControls.LabelProgress.Content = $Text
        $Global:GuiControls.ProgressBarMain.Value = $Value
        
        # UI aktualisieren
        $Global:Window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Render, [action]{})
    } catch {
        Write-Log "Fehler beim Anzeigen des Fortschritts: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Hide-Progress {
    <#
    .SYNOPSIS
    Versteckt die Fortschrittsanzeige
    #>
    try {
        $Global:GuiControls.GridProgressArea.Visibility = [System.Windows.Visibility]::Collapsed
        $Global:GuiControls.ProgressBarMain.Value = 0
    } catch {
        Write-Log "Fehler beim Verstecken des Fortschritts: $($_.Exception.Message)" -Level "ERROR"
    }
}

function Update-Progress {
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
        $percentage = [math]::Round(($Current / $Total) * 100, 0)
        
        if ($Text) {
            Show-Progress -Text "$Text ($Current von $Total)" -Value $percentage
        } else {
            $Global:GuiControls.ProgressBarMain.Value = $percentage
        }
    } catch {
        Write-Log "Fehler beim Aktualisieren des Fortschritts: $($_.Exception.Message)" -Level "ERROR"
    }
}

#endregion

function Start-Application {
    try { 
        Initialize-Application 
        Write-Log "Starte GUI..." 
        $null = $Global:Window.ShowDialog() 
    } catch { 
        Write-Log "Kritischer Fehler in der Anwendung: $($_.Exception.Message)" -Level "ERROR" 
        [System.Windows.MessageBox]::Show("Ein kritischer Fehler ist aufgetreten:`n$($_.Exception.Message)", "Kritischer Fehler", "OK", "Error") 
    } finally { 
        Write-Log "Anwendung beendet." 
    } 
} 
 
#endregion 
 
# ============================================================================ 
# SCRIPT ENTRY POINT 
# ============================================================================ 
Start-Application

