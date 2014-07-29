#!/bin/bash
#
# Author:	Bogdan Radulescu <bogdan@nimblex.net>

START=`date +%s`

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
elif [[ -f ec2backup.conf ]]; then
  CONF=ec2backup.conf
elif [[ -f /etc/ec2backup.conf ]]; then
  CONF=/etc/ec2backup.conf
else
  Warning "ec2backup.conf was not found in the $PWD directory or in /etc"
  Info "You can copy the sample to /etc/ec2backup.conf and adjust it accordingly"
  exit
fi

# Set Environment Variables
. $CONF

# Sanity checks
command -v aws >/dev/null 2>&1		|| { echo >&2 "AWS CLI Tools were not detected. Make sure you can run aws in the command line."; exit 1; }


# This function take the name of the volume as the single parameter
create_snapshot() {
  aws --profile=$PROFILE ec2 create-snapshot --output=text --description="ec2backup-`date +%Y-%m-%d`" --volume-id $1 | awk '{print "Snapshot " $5 " for volume " $8 " is " $7}'
}

# This function takes two parameters, volume ID and days of retention
prune_snapshot() {
  date_days_ago=`date +%Y-%m-%d --date "$2 days ago"`
  day_days_ago_s=`date --date="$date_days_ago" +%s`
 
  # Get snapshot info for the Volume
  aws --profile=$PROFILE ec2 describe-snapshots --output=text | awk "/$1/ && /ec2backup/ && /completed/" > /tmp/ec2_snapshots.txt 2>&1
 
  # Make sure we don't delete the last snapshot
  [[ `wc -l /tmp/ec2_snapshots.txt | cut -d " " -f1` -eq 1 ]] && Info skipping delete for the last snapshot of $1 && return

  # Loop to remove any snapshots older than specified days
  while read line
  do
        snapshot_name=`echo "$line" | awk '{print $6}'`
        snapshot_date=`echo "$line" | awk '{print $7}' | awk -F "T" '{printf "%s\n", $1}'`
        snapshot_date_s=`date --date="$snapshot_date" +%s`
 
        if (( $snapshot_date_s <= $day_days_ago_s )); then
                        Info "Deleting snapshot $snapshot_name for volume $1"
                        aws --profile=$PROFILE ec2 delete-snapshot --snapshot-id $snapshot_name
#        else
#                        Info "NOT deleting snapshot $snapshot_name for volume $1"
        fi
  done < /tmp/ec2_snapshots.txt
}

Email() {
  command -v smtp-cli >/dev/null 2>&1      || { echo >&2 "The smtp-cli tool was not detected. Maybe you can get it here http://www.logix.cz/michal/devel/smtp-cli/smtp-cli"; exit 1; }
  smtp-cli --to=$MAIL_TO --from=$MAIL_FROM --user=$MAIL_USER --pass=$MAIL_PASS --server=$MAIL_SRV:25 --subject="ec2backup has something for you" --body-plain="$@"
}

# Get a list of volumes that are available in EC2
AVAILABLE_VOLs=(`aws --profile=$PROFILE ec2 describe-volumes --output=text | awk '/VOLUME/ { for (i=1;i<=NF;i++) { if ($i~"vol-") {print $i} } }'`)

# Here we only sanitize the volumes list keeping only volumes that are still available in EC2
VBKP=($(comm -12 <(printf '%s\n' "${AVAILABLE_VOLs[@]}" | LC_ALL=C sort) <(printf '%s\n' "${VOLIDs[@]}" | LC_ALL=C sort)))

# Here we make a list of volumes which are not available anymore so they can be removed from config
RVOL=($(comm -13 <(printf '%s\n' "${AVAILABLE_VOLs[@]}" | LC_ALL=C sort) <(printf '%s\n' "${VOLIDs[@]}" | LC_ALL=C sort)))

debug() {
echo ------------------------
echo "available " ${AVAILABLE_VOLs[@]}
echo "for_backp " ${VOLIDs[@]}
echo "intersect " ${VBKP[@]}
echo "not ava   " ${RVOL[@]}
echo ------------------------
aws --profile=$PROFILE ec2 describe-snapshots --output=text | awk '/pending/'
}

main() {
  echo -e "________________________________________________\n`date`"
  if [[ ${#RVOL[@]} -gt 0 ]]; then
    Warning Volumes ${RVOL[@]} are not available anymore
    Email "Volumes ${RVOL[@]} are not available anymore"
  fi
  for volume in ${VBKP[@]}; do
    create_snapshot $volume
    prune_snapshot  $volume $RETAIN 
  done

  echo "Issued commands in $((`date +%s` - $START)) seconds"
}

main >> /var/log/ec2backup.log
