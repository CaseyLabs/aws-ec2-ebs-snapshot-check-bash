#!/bin/bash
export PATH=$PATH:/usr/local/bin/:/usr/bin

### Put this in a separate file ie README vv

## AWS Missing Snapshot Verification Script
#
# Written by Casey Labs Inc. and Bleeding Edge Solutions
#
# PURPOSE:
# - Gather a list of all EBS volumes attached to running EC2 instances.
# - Check the snapshots times associated with the EBS volumes.
# - If there are no recent snapshots, send out an alert notification.

## Requirements ##

# 1) IAM USER:
#
# This script requires an IAM policy attached to an IAM User or an IAM Role.
# IAM permissions required:
#
# {
#    "Version": "2012-10-17",
#    "Statement": [
#        {
#            "Sid": "Stmt1426256275000",
#            "Effect": "Allow",
#            "Action": [
#                "ec2:DescribeInstances",
#                "ec2:DescribeSnapshots",
#                "ec2:DescribeVolumes"
#            ],
#            "Resource": [
#                "*"
#            ]
#        }
#    ]
# }

# 2) AWS CLI: 
#
# This script requires the AWS CLI tools to be installed, available at: https://aws.amazon.com/cli/
#
# Linux install instructions for AWS CLI:
#
# - Install Python pip (e.g. yum install python-pip or apt-get install python-pip)
# - Then run: pip install awscli
#
# Configure AWS CLI by running this command (can be skipped if using an IAM Role): 
#		sudo aws configure
#
# Access Key & Secret Access Key: enter in your IAM user crendentials
# Region Name: the region that this instance is currently in (e.g. us-east-1, us-west-1, etc)
# Output Format: enter "text"

# 3) SCRIPT INSTALLATION:
#
# Copy this script to /opt/aws/check-snapshots.sh
# And make it exectuable: chmod +x /opt/aws/check-snapshots.sh
#
# Then setup a crontab job for nightly backups:
# 
# 00 07 * * *     root    AWS_CONFIG_FILE="/root/.aws/config" /opt/aws/check-snapshot.sh


# Safety feature: exit script if error is returned, or if variables not set. Exit if a pipeline results in an error.
set -u -o pipefail

### User configurable options, 
# Set Logging Options (0-5, 1 debug, 5 verbose)
declare -i LOG_LEVEL=1

## Global Variable Declarations ##

declare -r LOGGER='/usr/bin/logger'
declare -r ECHO='/bin/echo'
declare -r DATE='/bin/date'
declare -r AWS='/usr/bin/aws'
declare -r CURL='/usr/bin/curl'

declare -r BINARIES=( ${LOGGER} ${ECHO} ${DATE} ${AWS} ${CURL} )

declare PLACEMARK='lost'

# Volumes must have a snapshot that is under $DAYS_MIN days old
declare -ri DAYS_MIN=3	

# $DAY_MIN converted into seconds
declare -ri DAYS_MIN_SEC=$(${DATE} +%s --date "${DAYS_MIN} days ago")	

# Get list of running instances
declare INSTANCES=$(${AWS} ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters "Name=instance-state-name,Values=running" --output text)
declare INSTANCES_NUM=$(${AWS} ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters "Name=instance-state-name,Values=running" --output text | wc -l)

# Grab current AWS region
declare REGION=$(${CURL} -s http://169.254.169.254/latest/meta-data/placement/availability-zone|sed s'/.$//')


## Function Declarations ##
DoLog () {
	local fail_flag=${2:-0}
        if (( ${DEBUG} > 0 ))
        then
                #If debugging add some extra tags
                local log_tag="[PID:$$]-[${0%.*/.\/}]-[${PLACEMARK}]"
        else
                local log_tag="[PID:$$]-[${0%.*/.\/}]"
        fi
        if (( ${fail_flag} == 1 ))
        then
                #If fail flag raised print error to STDERR and daemon.err facility
                ${LOGGER}  -p daemon.err -s -t "${log_tag}" "$1"
        else
                #Log all else as informational
                ${ECHO} "[$(${DATE} +%r)] ${log_tag}: $1"
                ${LOGGER}  -p daemon.info -t "${log_tag}" "$1"
        fi
}


# Confirm that the AWS CLI and related tools are installed.
DepCheck() {
	PLACEMARK=${FUNCNAME[0]}
	for bin in ${BINARIES}
	do
		#Check if file exists
		[[ -f ${bin} ]] || DoLog "Binary ${bin} does not exist" 1
		#Check if file executable
		[[ -x ${bin} ]] || DoLog "Binary ${bin} is not executable" 1
	done
}

# Clean up temp files upon exiting the script.
CleanUp() {
	(( ${DEBUG} > 0 )) && echo -e "\nClean the things"
	#Reset Bash variables
	set +u +o pipefail
}

# Terminate the script.
Terminate() {
	MESSAGE=${1:-Terminating.}
	RETURN=${2:-0}
	if (( ${RETURN} > 0 ))
	then
		DoLog "${MESSAGE}" 1
	else
		DoLog "${MESSAGE}" 0
	fi
		
	exit ${RETURN} 
}

# Send alert if snapshots are missing.
DoAlert() {
	DoLog "Alert! Instance: ${instance} (${description}) Volume: ${volume} has no recent snapshots." '1'
}

# Trap function signal to trap (kill -l to list)
# Terminate function calls exit, exit trap will run cleanup function.
trap "Terminate" SIGINT 
trap "Terminate" SIGKILL
trap "CleanUp" EXIT


## Script Commands ##


DepCheck || Terminate "Dependency checks failed" 1


DoLog "There are ${INSTANCES_NUM} instances running."

for instance in ${INSTANCES}
do
	description=$(${AWS} ec2 describe-instances --region ${REGION} --instance-id ${instance} --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value[]')
	
	DoLog "Checking ${instance}: (${description})"

    # Check launch date of instance
	launch_time=$(${AWS} ec2 describe-instances --region ${REGION} --instance-ids ${instance} --query 'Reservations[*].Instances[*].[LaunchTime]' --output text | sed 's/T.*$//')
	launch_time_sec=$(${DATE} "--date=${launch_time}" +%s)

	# Proceed if the instance launch date is greater than 3 days, otherwise exit. Why? Because we don't want alerts for recently launched instances.
	[[ ${launch_time_sec} > ${DAYS_MIN_SEC} ]] && DoLog "${instance} (${description}) was launched less than $DAYS_MIN days ago, not alerting." && continue
	
	# Grab all volume IDs attached to this particular instance
	volume_list=$(${AWS} ec2 describe-volumes --region ${REGION} --filters Name=attachment.instance-id,Values=${instance} --query Volumes[].VolumeId --output text)
			   
	for volume in ${volume_list}; do
		# Grab all snapshot associated with this particular volume, and find the most recent snapshot time
		last_snap=$(${AWS} ec2 describe-snapshots --region ${REGION} --output=text --filters "Name=volume-id,Values=${volume}" --query Snapshots[].[StartTime] | sed 's/T.*$//' | sort -u | tail -n1)

		if [[ -z ${last_snap} ]]; then
			DoAlert
		else
			last_snap_sec=$(${DATE} "--date=${last_snap}" +%s)
		
			# If the latest snapshot is older than $DAYS_MIN, send an alert.
			if [[ ${last_snap_sec} < ${DAYS_MIN_SEC} ]]; then 
				DoAlert
			fi
		fi
	done
done


Terminate