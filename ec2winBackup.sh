#!/bin/bash
#
# Author:   Bogdan Radulescu <bogdan@nimblex.net>
#
#set -x

Description="ec2backup-`date +%Y%m%d`"  # Don't change this because you risk deleting other AMIs

Warning() {
  echo -e "\e[31m Warning: \e[39m$@"
}

Info() {
  echo -e "\e[32m Info: \e[39m$@"
}

while getopts ":c:" opt; do
  case $opt in
    c)
      CONF=$OPTARG
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      exit 1
      ;;
  esac
done

if [[ $CONF ]]; then
  Info "we'll use $CONF for settings"
elif [[ -f ec2winBackup.conf ]]; then
  CONF=ec2winBackup.conf
elif [[ -f /etc/ec2winBackup.conf ]]; then
  CONF=/etc/ec2winBackup.conf
else
  Warning "ec2winBackup.conf was not found in the $PWD directory or in /etc"
  Info "You can copy the sample to /etc/ec2winBackup.conf and adjust it accordingly"
  exit
fi

# Set Environment Variables
. $CONF

# Sanity checks
command -v aws >/dev/null 2>&1      || { echo >&2 "AWS CLI Tools were not detected. Make sure you can run aws in the command line."; exit 1; }



WinAMIs=("`aws --profile=$Profile ec2 describe-images --owners $AMIOwner --filters "Name=platform,Values=windows" --query 'Images[*].[Name,Description,ImageId]' | jq '.[]' -c`")

createAMIs() {
  Info "Running at `date`"
  while read line; do
    Instance=`echo $line | awk -F "\"" '{print $2}'`
    Name=`echo $line | awk -F "\"" '{print $4}'`-`date +%Y%m%d`
    BID="\"$Name\",\"$Description\""
    # Here we skip the AMI creation if we already have one from the same day.
    echo ${WinAMIs[*]} | grep -q "$BID" && continue || \
    if [ $Instance != "" ] && [ $Name != "" ]; then
        Info "Creating AMI for $Name - $Instance"
        aws --profile=$Profile ec2 create-image --no-reboot --instance-id $Instance --name "$Name" --description "$Description"
    else
        Warning "Either the name ($Name) or instance ID ($Instance) is missing."
    fi
  done < <(aws --profile=$Profile ec2 describe-instances --filters "Name=platform,Values=windows" "Name=instance-state-name,Values=running" "Name=tag-key,Values=Production" "Name=tag-value,Values=yes" --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`] | [0].Value]' | jq '.[]|.[]' -c)
}

cleanAMIs() {
  # It is incomplete because we should actually delete all the snapshots for those AMIs.
  for AMI in ${WinAMIs[@]}; do
    echo $AMI | grep -q ec2backup || continue   # This is important so we don't delete other AMIs
    AGE=`echo $AMI | awk -F "\"" '{print $4}' | awk -F "-" '{print $2}'`
    if [[ $AGE -lt $(echo "`date +%Y%m%d` - $Retention" | bc) ]]; then
        DEL=`echo $AMI | awk -F "\"" '{print $6}'`
        Info "Deleting $DEL"
        SnapIDs=`aws --profile=$Profile ec2 describe-images --owners $AMIOwner --image-id $DEL --query 'Images[*].BlockDeviceMappings[*].Ebs.SnapshotId' --output=text`
        aws --profile=$Profile ec2 deregister-image --image-id $DEL
        for snap in $SnapIDs; do
            echo "Deleting $snap"
            aws --profile=$Profile ec2 delete-snapshot --snapshot-id $snap
        done
    fi
  done
}

createAMIs >> /var/log/ec2winBackup.log
cleanAMIs >> /var/log/ec2winBackup.log
