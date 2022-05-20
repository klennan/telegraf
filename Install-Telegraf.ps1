function Install-Telegraf {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [String[]]
        $ComputerName,

        [Parameter(HelpMessage="A list of optional files to include. They must be in the local conf directory named <option>.conf")]
        [ValidateSet("activeDirectory","dfs","dotnet","exchange","iis","mssql-config","radius","rightfax","windowsdns","windowsprocesses")]
        [String[]]$Options
    )

    # Copy source files to destination
    BEGIN {
        # telegraf.exe should be in the same path as this script
        $InstallerSourcePath = ".\"
        $MandatoryFiles      = @("telegraf.exe","telegraf.conf","conf\windowssystem.conf","conf\outputs.influxdb2.conf")
        $OptionalFiles       = @()
        # fill in your values here
        $InfluxBucket        = ""
        $InfluxOrg           = ""
        $InfluxToken         = ""
        $InfluxUrl           = ""

        foreach ($Opt in $Options) { $OptionalFiles += "conf\$Opt.conf" }
        $ArgumentList = @($MandatoryFiles,$OptionalFiles)
    }
    PROCESS {
        foreach ($Computer in $ComputerName) {
            Write-Verbose "Attempting PSSession with $Computer"
            try {
                try { $Session = New-PSSession -ComputerName $Computer -ErrorAction Stop }
                catch { "Failed to establish PSSession with $Computer"; continue }

                Write-Verbose "Session established. Copying files to $Computer"
                foreach ($File in $MandatoryFiles) {
                    Copy-Item "$InstallerSourcePath\$File" "c:\Windows\Temp" -ToSession $Session -ErrorAction SilentlyContinue
                }
                foreach ($File in $OptionalFiles) {
                    Copy-Item "$InstallerSourcePath\$File" "c:\Windows\Temp" -ToSession $Session -ErrorAction SilentlyContinue
                }

                Write-Verbose "Running install procedure on $Computer"
                $InvokeResult = Invoke-Command -Session $Session -ArgumentList $ArgumentList -ScriptBlock {
                    [CmdletBinding()]
                    param (
                        [Parameter(Mandatory)]
                        [Array]$MandatoryFiles,
                        [Array]$OptionalFiles,
                        [String]$InfluxBucket,
                        [String]$InfluxOrg,
                        [String]$InfluxToken,
                        [String]$InfluxUrl
                    )
                    # Configure environment variables
                    [Environment]::SetEnvironmentVariable("INFLUX_BUCKET", "$InfluxBucket", "Machine")
                    [Environment]::SetEnvironmentVariable("INFLUX_ORG", "$InfluxOrg", "Machine")
                    [Environment]::SetEnvironmentVariable("INFLUX_TOKEN", "$InfluxToken", "Machine")
                    [Environment]::SetEnvironmentVariable("INFLUX_URL", "$InfluxUrl", "Machine")

                    # Copy over telegraf.exe
                    if (!(Test-Path "C:\Program Files\Telegraf")) { mkdir "C:\Program Files\Telegraf" }
                    if (!(Test-Path "C:\Program Files\Telegraf\conf")) { mkdir "C:\Program Files\Telegraf\conf" }

                    # Stop and uninstall if it already exists (upgrading?)
                    Set-Location 'C:\Program Files\telegraf'
                    if ((Get-Service -name Telegraf -ErrorAction SilentlyContinue)) {
                        Stop-Service telegraf
                        .\telegraf.exe --service uninstall
                    }

                    foreach ($File in $MandatoryFiles) {
                        Move-Item "C:\Windows\Temp\$($File.replace('conf\',''))" "C:\Program Files\telegraf\$File" -Force
                    }
                    foreach ($File in $OptionalFiles) {
                        Move-Item "C:\Windows\Temp\$($File.replace('conf\',''))" "C:\Program Files\telegraf\$File" -Force
                    }

                    # Register service
                    .\telegraf.exe --service install --config-directory 'C:\Program Files\telegraf\conf'
                    Start-Service telegraf
                }

                Remove-PSSession $Session
                Write-Verbose "Competed procedure on $Computer"
            }
            catch { $Error[0].Exception.Message }
            $InvokeResult
        }
    }
    END { }
    # Send install script to destination

}
