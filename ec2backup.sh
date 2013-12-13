#!/bin/bash
#
# Author:	Bogdan Radulescu <bogdan@nimblex.net>


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
command -v java >/dev/null 2>&1		|| { echo >&2 "Java was not detected. Make sure you can run java in the command line."; exit 1; }
command -v ec2dsnap >/dev/null 2>&1	|| { echo >&2 "EC2 Tools were not detected. Make sure you can run ec2dsnap in the command line."; exit 1; }


# This function take the name of the volume as the single parameter
create_snapshot() {
  ec2addsnap -d "ec2backup-`date +%Y-%m-%d`" $1 | awk '{print "Snapshot " $2 " for volume " $3 " is " $4}'
}

# This function takes two parameters, volume ID and days of retention
prune_snapshot() {
  date_days_ago=`date +%Y-%m-%d --date "$2 days ago"`
  day_days_ago_s=`date --date="$date_days_ago" +%s`
 
  # Get snapshot info for the Volume
  ec2dsnap | awk "/$1/ && /ec2backup/ && /completed/" > /tmp/ec2_snapshots.txt 2>&1
 
  # Make sure we don't delete the last snapshot
  [[ `wc -l /tmp/ec2_snapshots.txt | cut -d " " -f1` -eq 1 ]] && Info skipping delete for the last snapshot of $1 && return

  # Loop to remove any snapshots older than specified days
  while read line
  do
        snapshot_name=`echo "$line" | awk '{print $2}'`
        snapshot_date=`echo "$line" | awk '{print $5}' | awk -F "T" '{printf "%s\n", $1}'`
        snapshot_date_s=`date --date="$snapshot_date" +%s`
 
        if (( $snapshot_date_s <= $day_days_ago_s )); then
                        Info "Deleting snapshot $snapshot_name for volume $1"
                        ec2-delete-snapshot $snapshot_name
#        else
#                        Info "NOT deleting snapshot $snapshot_name for volume $1"
        fi
  done < /tmp/ec2_snapshots.txt
}

# Get a list of volumes that are available in EC2
AVAILABLE_VOLs=(`ec2dvol | awk '/VOLUME/ {print $2}'`)

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
ec2dsnap | awk '/pending/'
}

Warning Volumes ${RVOL[@]} are not available anymore

for volume in ${VBKP[@]}; do
  create_snapshot $volume
  prune_snapshot  $volume $RETAIN 
done


