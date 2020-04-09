Param(
    [Parameter(Mandatory=$true)]$CsvFile
)

Function Write-Log(){
    param
        (
            [ValidateSet("Error", "Warning", "Info")]$LogLevel,
            $UserOrGroup,
            [string]$Message
        )

    #Name of the log file containing date/time
    $logFileName = "MonitorCsvEntries_$((Get-Date).ToString('ddMMyyyy')).log"

    #Header of the log file in csv format
    $header = "datetime,user,action,message"

    #Date/time of the log entry
    $datetime = (Get-Date).ToString('dd/MM/yyyy hh:mm:ss')

    #Log entry variable containing each parameter passed when funcion is called
    $logEntry = "$datetime,$LogLevel,$UserOrGroup,$Message"

    #Check if log file already exists
    if(-not(Test-Path $logFileName)){
        #Try to create a file and add content
        try{
            New-Item -ItemType "File" -Path $logFileName -ErrorAction Stop
            Add-Content -Path $logFileName -Value $header -ErrorAction Stop
        }
        catch{
            #Prints the exception related to log file creation/write
            $_.Exception.Message
            Exit
        }
    }

    #Adds a log entry into log file    
    try{
        Add-Content -Path $logFileName -Value $logEntry -ErrorAction Stop
    }
    catch{
        $_.Exception.Message
        #Prints the exception related to log file creation/write
        Exit
    }
    
}
#Making sure sensitive variables are clean
$currentEntries = $null
$compareMembers = $null

#Get list of entries and saves to a file
Write-Log -LogLevel "Info" -UserOrGroup $csvFile -Message "Starting entries acquisition"
    
#Try to get a list of entries from the RH's csv file to save it in a reference file
try{
    $currentEntries = Import-Csv $CsvFile -ErrorAction Stop        
    Write-Log -LogLevel "Info" -UserOrGroup $csvFile "List of members acquired succesfully"

    #If entries count is greater than 0/not empty
    if(($currentEntries|Measure-Object).Count -gt 0){
        try{
            #Creates a variable with the name of the reference file containing date/time
            $logFileName =  "$($csvFile)_Entries_$((Get-Date).ToString('ddMMyyyy_hhmmss')).csv"
            #Export list to a csv file
            $currentEntries | Export-Csv "$($logFileName)" -NoTypeInformation -ErrorAction Stop
            Write-Log -LogLevel "Error" -UserOrGroup $csvFile "List of entries saved in csv file $($logFileName)"
        }
        catch{
            #Writes a log entry with the error related to export list to a csv file
            Write-Log -LogLevel "Error" -UserOrGroup $csvFile $_.Exception.Message
        }
    }
    #If list count is zero
    else{
        Write-Log -LogLevel "Error" -UserOrGroup $csvFile "File $($csvFile) is empty"
        Write-Log -LogLevel  "Error" -UserOrGroup $csvFile "Script execution stopped"
        Break
    }
}
catch{
    #Writes a log entry with the error related to get list of entries
    Write-Log -LogLevel "Error" -UserOrGroup $csvFile $_.Exception.Message
}

#Creates a variable containing the log file name related to list entries added and/or removed
$logFileName = "$($csvFile)_EntriesAddedRemoved_$((Get-Date).ToString('ddMMyyyy_hhmmss')).csv"

#If csv list file count in disk is greater than 1
If((Get-Item "$($csvFile)_Entries_*" |Measure-Object).Count -gt 1){
    try{
        #Compares the current list of entries with the previous execution list which has been saved in a csv file
        $compareMembers = Compare-Object -DifferenceObject (Import-Csv (Get-Item "$($csvFile)_Entries_*" | Sort-Object LastWriteTime -Descending | Select-Object -First 1)) -ReferenceObject (Import-Csv (Get-Item "$($csvFile)_Entries_*" | Sort-Object LastWriteTime -Descending | Select-Object -Skip 1 -First 1)) -PassThru -Property SamAccountName -ErrorAction Stop
        Write-Log -LogLevel "Info" -UserOrGroup $csvFile -Message "Lists comparison ran succesfully. Users added/removed saved into file $($logFileName)"
    }
    catch{
        Write-Log -LogLevel "Error" -UserOrGroup $csvFile -Message $_.Exception.Message
    }
}
#If csv list file count in disk is equal or less than 1, starts "first execution mode"
else{
     Write-Log -LogLevel Error -UserOrGroup $csvFile -Message "Unable to compare current list and previous one. Script in 'First Execution Mode' or the file with list entries is missing. If in 'First Exeuction Mode', all users in the list will be added in the group"

    #If the current entries count is greater than 0
    if(($currentEntries|Measure-Object).Count -gt 0){

        #Once this is in "first execution mode", adds a column to each object in current member array with "Added Member" signal
        $currentEntries | Add-Member -Name "SideIndicator" -MemberType NoteProperty -Value "=>" -Force
            
        #Exports a list containing all entries that have been either added or removed to/from the distribution list
        try{
            $currentEntries | Export-Csv "$($logFIleName)" -NoTypeInformation -ErrorAction Stop
            Write-Log -LogLevel "Info" -UserOrGroup $csvFile -Message "Entries activity sucessfully exported to log file $($logFileName)"
        }
        catch{
            #Writes a log entry with the error related to csv export
            Write-Log -LogLevel "Error" -UserOrGroup $csvFile -Message $_.Exception.Message
        }

        #Returns the current list of entries as a result of the Compare-Object cmdlet because it is in "first execution mode"
        return $currentEntries
    }
    #If the current list of entries count is equal to zero
    else
    {   
        #Writes a log entry with a static string error sentence that it is unable to list current members
        Write-Log -LogLevel "Error" -UserOrGroup $csvFile -Message "Unable to get list of entries"
    }
}

#If the array with add/removed entries is greater than 0/not empty (now it is not in "first execution mode")
if(($compareMembers|Measure-Object).Count -gt 0){
    Write-Log -LogLevel "Info" -UserOrGroup $group -Message "List of entries change detected. Users added: $(($compareMembers|Where-Object{$_.SideIndicator -eq "=>"}|Measure-Object).Count) - Users removed: $(($compareMembers|Where-Object{$_.SideIndicator -eq "<="}|Measure-Object).Count)"
            
    #Exports a list containing all entries that have been either added or removed to/from the Distribution List
    try{
        $compareMembers | Export-Csv "$($logFileName)" -NoTypeInformation -ErrorAction Stop
        Write-Log -LogLevel "Info" -UserOrGroup $csvFile -Message "List of entries activity exported to log file $($logFileName)"
    }
    catch{
        #Writes a log entry with the error related to csv export
        Write-Log -LogLevel "Error" -UserOrGroup $csvFile -Message $_.Exception.Message
    }

    #Created an array object to receive entries objects. This function cannot return the objects resulted from Compare-Object due to issues in reading the objects that have other objects inside
    $arrCompareMembers = @()

    #For each compared object
    foreach($entry in $compareMembers){

        #If the object has the signal added "=>" adds the respective signal string to the entry object in a new column
        if($entry.SideIndicator -eq "=>"){
            $entry | Add-Member -Name SideIndicator -MemberType NoteProperty -Value "=>" -Force
        }

        #If the object has the signal removed "=>" the respective signal string to the entry object in a new column
        if($entry.SideIndicator -eq "<="){
            $entry | Add-Member -Name SideIndicator -MemberType NoteProperty -Value "<=" -Force
        }
        #Adds the entry object to the array that's going to be returned
        $arrCompareMembers += $entry
    }

    #Return the final list of entries that have been either added or removed            
    return $arrCompareMembers
}