ec2backup
=========

Backup script for Amazon EC2 volumes
------------------------------------

The purpose of the script is to allow you to make a simple backup to Amazon EC2 volumes.

It accomplishes that by taking snapshots and it also cleans up after itself by deleting old snapshots. As a failsafe it only deletes snapshots created by ec2backup only if you have more than one snapshot. Still, it is yet to be tested :)

It has a very simple config file that is self explanatory and the idea is to run it as a cron for daily snapshots. You can specify the config file with the `-c` parameter in case you need to initiate various backups at different times.

The script produces logs which can be accessed in `/var/log/ec2backup.log`.

For backing up volumes where you keep DB data it is recommended you look at [ec2-consistent-snapshot](https://github.com/alestic/ec2-consistent-snapshot)
