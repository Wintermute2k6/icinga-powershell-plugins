<#
.SYNOPSIS
    Checks how much space on a partition is used.
.DESCRIPTION
    Invoke-IcingaCheckUsedPartition returns either 'OK', 'WARNING' or 'CRITICAL', based on the thresholds set.
    e.g 'C:' is at 8% usage, WARNING is set to 60, CRITICAL is set to 80. In this case the check will return OK.

    The plugin will return `UNKNOWN` in case partition data (size and free space) can not be fetched. This is
    normally happening in case the user the plugin is running with does not have permissions to fetch this
    specific partition data.

    More Information on https://github.com/Icinga/icinga-powershell-plugins
.FUNCTIONALITY
    This module is intended to be used to check how much usage there is on an partition.
    Based on the thresholds set the status will change between 'OK', 'WARNING' or 'CRITICAL'. The function will return one of these given codes.

    The plugin will return `UNKNOWN` in case partition data (size and free space) can not be fetched. This is
    normally happening in case the user the plugin is running with does not have permissions to fetch this
    specific partition data.
.ROLE
    ### WMI Permissions

    * Root\Cimv2

    ### Performance Counter

    * LogicalDisk(*)\% free space

    ### Required User Groups

    * Performance Monitor Users
.EXAMPLE
    PS>Invoke-IcingaCheckUsedPartitionSpace -Warning 60 -Critical 80
    [OK]: Check package "Used Partition Space" is [OK]
    | 'Partition C'=8,06204986572266%;60;;0;100 'Partition D'=12,06204736572266%;60;;0;100 'Partition K'=19,062047896572266%;60;;0;100
.EXAMPLE
    PS>Invoke-IcingaCheckUsedPartitionSpace -Warning 60 -Critical 80 -Exclude "C:\"
    [OK]: Check package "Used Partition Space" is [OK]
    | 'Partition D'=12,06204736572266%;60;;0;100 'Partition K'=19,062047896572266%;60;;0;100
.EXAMPLE
    PS>Invoke-IcingaCheckUsedPartitionSpace -Warning 60 -Critical 80 -Include "C:\"
    [OK]: Check package "Used Partition Space" is [OK]
    | 'Partition C'=8,06204986572266%;60;;0;100
.PARAMETER Warning
    Used to specify a Warning threshold. This can either be a byte-value type like '10GB'
    or a %-value, like '10%'
.PARAMETER Critical
    Used to specify a Critical threshold. This can either be a byte-value type like '10GB'
    or a %-value, like '10%'
.PARAMETER Exclude
    Used to specify an array of partitions to be excluded.
    e.g. 'C:\','D:\'
.PARAMETER Include
    Used to specify an array of partitions to be included. If not set, the check expects that all not excluded partitions should be checked.
    e.g. 'C:\','D:\'
.PARAMETER IgnoreEmptyChecks
    Overrides the default behaviour of the plugin in case no check element is left for being checked (if all elements are filtered out for example).
    Instead of returning `Unknown` the plugin will return `Ok` instead if this argument is set.
.PARAMETER SkipUnknown
    Allows to set Unknown partitions to Ok in case no metrics could be loaded.
.PARAMETER NoPerfData
    Disables the performance data output of this plugin
.PARAMETER Verbosity
    Changes the behavior of the plugin output which check states are printed:
    0 (default): Only service checks/packages with state not OK will be printed
    1: Only services with not OK will be printed including OK checks of affected check packages including Package config
    2: Everything will be printed regardless of the check state
    3: Identical to Verbose 2, but prints in addition the check package configuration e.g (All must be [OK])
.INPUTS
    System.String
.OUTPUTS
    System.String
.LINK
    https://github.com/Icinga/icinga-powershell-plugins
.NOTES
#>

function Invoke-IcingaCheckUsedPartitionSpace()
{
    param(
        $Warning                   = $null,
        $Critical                  = $null,
        [array]$Include            = @(),
        [array]$Exclude            = @(),
        [switch]$IgnoreEmptyChecks = $FALSE,
        [switch]$NoPerfData        = $FALSE,
        [switch]$SkipUnknown       = $FALSE,
        [ValidateSet(0, 1, 2, 3)]
        [int]$Verbosity            = 0
    );

    $Disks       = Get-IcingaPhysicalDiskInfo;
    $DiskPackage = New-IcingaCheckPackage -Name 'Used Partition Space' -Verbose $Verbosity -IgnoreEmptyPackage:$IgnoreEmptyChecks -OperatorAnd -AddSummaryHeader;

    foreach ($disk in $Disks.Values) {

        foreach ($partitions in $disk.PartitionLayout.Keys) {
            $partition        =  $disk.PartitionLayout[$partitions];
            $ProcessPartition = $TRUE;

            if ([string]::IsNullOrEmpty($partition.DriveLetter)) {
                continue;
            }

            if ($disk.DriveReference.ContainsKey($partition.DriveLetter) -eq $FALSE) {
                continue;
            }

            $PartitionId = $disk.DriveReference[$partition.DriveLetter];

            if ($partitions -ne $PartitionId) {
                continue;
            }

            foreach ($entry in $Include) {
                $ProcessPartition = $FALSE;
                if ($entry.Replace(':', '').ToLower() -eq $partition.DriveLetter.Replace(':', '').ToLower()) {
                    $ProcessPartition = $TRUE;
                    break;
                }
            }
            foreach ($entry in $Exclude) {
                if ($entry.Replace(':', '').ToLower() -eq $partition.DriveLetter.Replace(':', '').ToLower()) {
                    $ProcessPartition = $FALSE;
                    break;
                }
            }

            if ($ProcessPartition -eq $FALSE) {
                continue;
            }

            $IcingaCheck = New-IcingaCheck -Name ([string]::Format('Partition {0}', $partition.DriveLetter)) -Value $partition.UsedSpace -Unit 'B' -Minimum 0 -Maximum $partition.Size -NoPerfData:$SetUnknown -BaseValue $partition.Size;

            if ([string]::IsNullOrEmpty($partition.FreeSpace) -Or [string]::IsNullOrEmpty($partition.Size)) {
                if ($SkipUnknown -eq $FALSE) {
                    $IcingaCheck.SetUnknown('No disk size and/or free space available', $TRUE) | Out-Null;
                } else {
                    $IcingaCheck.SetOk('No disk size and/or free space available', $TRUE) | Out-Null;
                }
            } else {
                $IcingaCheck.WarnOutOfRange($Warning).CritOutOfRange($Critical) | Out-Null;
            }

            $DiskPackage.AddCheck($IcingaCheck);
        }
    }

    return (New-IcingaCheckResult -Check $DiskPackage -NoPerfData $NoPerfData -Compile);
}
