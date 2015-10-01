#!/bin/bash
# July 2015 version 1.2
# Changed name from blk_prsr
# Allow multiple Action codes
# Include PID and Process (all) fields
# Update output file naming
#
# blk_prsr.sh
# February 2014 version 1.1
# Added filter for 9th field in input to be "+"
# Specified IO action filter is input on command line
# Output is csv and contains DeviceName,CPU,SequenceNum,TimeStamp(sec),Action,Operation,StartBlock,NumOfBlocks
#
# December 2013, Eric Lamkin, DCSG
# Reads blk_parse output, passes only rows with the specified action, can filter on device
# blk_parse input contains rows of space separated values
# blk_parse rows contain the following fields -
# DeviceMajor,DeviceMinor CPU SequenceNum TimeStamp(sec) PID Action Operation StartBlock + NumOfBlocks Process
# Output is csv and contains DeviceName,SequenceNum,TimeStamp(sec),Action,Operation,StartBlock,NumOfBlocks
#
#
version=1.2
outputext="-btc.csv"
usage()
{
  echo "Version: $version"
  echo "$0 converts default format blkparse text output to .csv format"
  echo "It also allows for filtering on trace action codes and device"
  echo "Usage: $0 blk_parse_file partition_file [output_file_ID [action_codes [device]]]"
  echo "First two file names are required"
  echo "Input is from blk_parse_file"
  echo "Output file will be named with -"
  echo " input file name + output_file_ID + action_filter + device_filter + $outputext"
  echo "Output_file_ID is optional, use - as a place holder if necessary"
  echo "Action_codes for filtering are optional and can be combined (no spaces), default is CQ"
  echo " C=completed, D=Issued, I=Inserted, Q=queued,"
  echo " M=back merged, F=front merged, G=get request or use . for all"
  echo "The device is a device name like sdb and is optional, default is to pass all devices"
  echo "The partition file allows mapping device major,minor in the trace file to device names"
  echo "The partition file can be obtained with cat /proc/partitions > part.txt"
  echo "The partition file must come from the same system the trace came from"
}

if [ $# -eq 0 ];then
  usage;exit
fi

blkfile=$1
prtfile=$2
outfile=$3
declare -u actn=${4:-CQ}
devfltr=$5

#Verify blk_parse file exists
if [ ! -f $blkfile ];then
  echo -e "\n ##>> blk_parse file $blkfile not found\n"
  usage;exit 1
fi

#Verify partition file exists
if [ ! -f $prtfile ];then
  echo -e "\n ##>> partition file $prtfile not found\n"
  usage;exit 1
fi

# Build device mapping tables
declare -A _devmmname  #indexed by major,minor
declare -A _devnamemm  #indexed by name
declare -i ptncnt
bld_dev_tbl()
{
  declare -a _devparttbl #full file as a single dimension array
  declare -i devpartndx  #line index to partition file
  declare -i valperrow=4 mjrofst=0 mnrofst=1 blkofst=2 namofst=3 rowndx
  local partfile=$1
  _devparttbl=($(cat $partfile))
  #validate partition file by examining header row
  if [ ${_devparttbl[$mjrofst]} != "major" -o ${_devparttbl[$mnrofst]} != "minor" -o ${_devparttbl[$blkofst]} != "#blocks" -o ${_devparttbl[$namofst]} != "name" ];then
    echo "invalid partition file - first line must contain \"major minor #blocks name\""
    exit 2
  fi
  #calculate # of partition entries
  ptncnt=$((${#_devparttbl[@]} / $valperrow - 1))
  echo "$ptncnt partition entries found"
  #build an associative array with key = major,minor pair as will be found in the Blk_parse file and a value of the partition name
  for (( devpartndx=1 ; $devpartndx <= $ptncnt ; devpartndx++ ))
  do
    rowndx=$((devpartndx * $valperrow)) #row index in partition table
    pmm="${_devparttbl[$(($rowndx + $mjrofst))]},${_devparttbl[$(($rowndx + $mnrofst))]}" #partition major,minor
    pnam="${_devparttbl[$(($rowndx + $namofst))]}" #partition name
    pblk="${_devparttbl[$(($rowndx + $blkofst))]}" #partition #blocks
    #echo "partition $devpartndx mm=$pmm name=$pnam blocks=$pblk"
    _devmmname[$pmm]=$pnam
    _devnamemm[$pnam]=$pmm
  done
}

bld_dev_tbl $prtfile
#echo ${_devmmname[@]}
#echo ${_devnamemm[@]}
#declare -a _names=(${_devmmname[@]})
#for (( ndx=0 ; $ndx < $ptncnt ; ndx++ ));do
#  echo "${_names[$ndx]}=${_devnamemm[${_names[$ndx]}]}"
#done

#Build display values for action if it is . and device filter
dispactn=$actn
dispdevf=$devfltr
if [ $actn == "." ];then dispactn="all";fi

#Convert device-filter name to major,minor found in blk_parse
mmfltr="1" #default if no device-filter given
mmval="1"  #default it no device filter given
if [ "x$devfltr" != "x" ];then
  mmfltr="\"${_devnamemm[$devfltr]}\""
  mmval="\$1"
  dispdevf="_$devfltr"
fi

# Form output file name with input file name, output_file_ID, action filter, device filter and -btc.csv
if [ "x$outfile" == "x-" ];then outfile="";fi
if [ "x$outfile" != "x" ];then outfile="_"$outfile;fi
outfile=$blkfile$outfile"_"$dispactn$dispdevf$outputext

echo "Reading trace file $blkfile"
echo "Reading partition file $prtfile"
echo "Writing csv file $outfile"
echo "Filtering for action codes $dispactn"

if [ $actn != "." ];then actn="[$actn]";fi #brackets for awk matching expression, . for any character

if [ $mmfltr == "\"\"" ];then
  echo "device $devfltr not found in partition table"
  cat $prtfile
  exit 2
elif [ $mmfltr != "1" ];then
  echo "Filtering for device $devfltr"
fi

# Process trace file, passing only rows that match the selected Action values
# Optionally filter for a particular device/partition major,minor designator
#
# Space separated input from blk_parse
# Allowing gawk to parse by spaces works for the rows of interest but not well for all rows
# DeviceMajor,DeviceMinor CPU SequenceNum TimeStamp(sec) PID Action Operation StartBlock + NumOfBlocks Process
# Fields for csv output
# DeviceName,CPU,SequenceNum,TimeStamp(sec),PID,Action,Operation,StartBlock,NumOfBlocks,Process
#
#Set output file header
echo "DevName,CPU,SeqNum,Time(sec),PID,Action,Operation,StartBlk,NumBlks,Process" > $outfile
#Build mjr,mnr -> dev-name translation logic
declare -a _mms=(${_devnamemm[@]})
gawkxlate="{"
for (( ndx=0 ; $ndx < $ptncnt ; ndx++ ));do
  #echo "${_mms[$ndx]}=${_devmmname[${_mms[$ndx]}]}"
  gawkxlate+="if (\$1 == \"${_mms[$ndx]}\") DEVN=\"${_devmmname[${_mms[$ndx]}]}\"; else "
done
gawkxlate+="DEVN=\"Y\";"
#echo $gawkxlate

#Used double quoting with \escape to allow shell variable expansion
gawk "BEGIN {OFS = \",\"; DEVN=\"X\"}; {if (\$6 ~ /$actn/ && \$9 == \"+\" && $mmval == $mmfltr) $gawkxlate print DEVN, \$2, \$3, \$4, \$5, \$6, \$7, \$8, \$10, \$11}}" < $blkfile >> $outfile
