#!/bin/bash
# set -x

AMIOwner="997957216438"
Description="ec2backup-`date +%Y%m%d`"  # Don't change this because you risk deleting other AMIs
Retention=7 # This is calculated in days
Profile="default"

WinAMIs=("`aws --profile=$Profile ec2 describe-images --owners $AMIOwner --filters "Name=platform,Values=windows" --query 'Images[*].[Name,Description,ImageId]' | jq '.[]' -c`")

while read line; do
    Instance=`echo $line | awk -F "\"" '{print $2}'`
    Name=`echo $line | awk -F "\"" '{print $4}'`-`date +%Y%m%d`
    BID="\"$Name\",\"$Description\""
    # Here we skip the AMI creation if we already have one from the same day.
    echo ${WinAMIs[*]} | grep -q "$BID" && continue || \
    if [ $Instance != "" ] && [ $Name != "" ]; then
        echo Creating AMI for $Name - $Instance
        aws ec2 create-image --no-reboot --instance-id $Instance --name "$Name" --description "$Description"
    else
        echo "Either the name ($Name) or instance ID ($Instance) is missing."
    fi
done < <(aws --profile=$Profile ec2 describe-instances --filters "Name=platform,Values=windows" "Name=instance-state-name,Values=running" "Name=tag-key,Values=Production" "Name=tag-value,Values=yes" --query 'Reservations[*].Instances[*].[InstanceId,Tags[?Key==`Name`] | [0].Value]' | jq '.[]|.[]' -c)


# This part should be unregistering AMIs. It is untested!
for AMI in ${WinAMIs[@]}; do
    echo $AMI | grep -q ec2backup || continue   # This is important so we don't delete other AMIs
    AGE=`echo $AMI | awk -F "\"" '{print $4}' | awk -F "-" '{print $2}'`
    if [[ $AGE -lt $(echo "`date +%Y%m%d` - $Retention" | bc) ]]; then
        DEL=`echo $AMI | awk -F "\"" '{print $6}'`
        echo Deleting $DEL
        aws --profile=$Profile ec2 deregister-image --image-id $DEL
    fi
done
