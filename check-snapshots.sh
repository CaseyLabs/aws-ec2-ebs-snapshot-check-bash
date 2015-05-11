#!/bin/bash
export PATH=$PATH:/usr/local/bin/:/usr/bin

## AWS Missing Snapshot Verification Script
# Written by Casey Labs Inc. and Bleeding Edge Solutions
# Github Repo: https://github.com/CaseyLabs/aws-ec2-ebs-snapshot-check-bash

# Safety feature: exit script if error is returned, or if variables not set. Exit if a pipeline results in an error.
set -u -o pipefail

### User configurable options,
# Set Logging Options (0-5, 1 debug, 5 verbose)
declare -i LOG_LEVEL=1

## Global Variable Declarations ##

# This script requires the following dependencies:
declare -r BINARIES=(logger echo date aws curl)

# Volumes must have a snapshot that is under $DAYS_MIN days old
declare -ri DAYS_MIN=3

# $DAY_MIN converted into seconds
declare -ri DAYS_MIN_SEC=$(date +%s --date "${DAYS_MIN} days ago")

# Get list of running instances
declare INSTANCES=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters "Name=instance-state-name,Values=running" --output text)
declare INSTANCES_NUM=$(aws ec2 describe-instances --query 'Reservations[*].Instances[*].[InstanceId]' --filters "Name=instance-state-name,Values=running" --output text | wc -l)

# Grab current AWS region
declare REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone|sed s'/.$//')


## Function Declarations ##
DoLog () {
  local fail_flag=${2:-0}
  local log_tag="[PID:$$]-[${0%.*/.\/}]"

  if (( ${fail_flag} == 1 )); then
    #If fail flag raised print error to STDERR and daemon.err facility
    logger  -p daemon.err -s -t "${log_tag}" "$1"
  else
    #Log all else as informational
    echo "[$(date +%r)] ${log_tag}: $1"
    logger  -p daemon.info -t "${log_tag}" "$1"
  fi
}


# Confirm that the AWS CLI and related tools are installed.
DepCheck() {
  for prerequisite in ${BINARIES}; do
    hash ${BINARIES[@]} &> /dev/null
    if [[ $? == 1 ]]; then
      echo "In order to use this script, the executable \"$prerequisite\" must be installed." 1>&2; exit 70
    fi
  done
}

# Clean up temp files upon exiting the script.
CleanUp() {
  echo -e "\nScript cleanup."
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

DepCheck || Terminate "Dependency checks failed." 1

DoLog "There are ${INSTANCES_NUM} instances running."

for instance in ${INSTANCES}; do
  description=$(aws ec2 describe-instances --region ${REGION} --instance-id ${instance} --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value[]')

  DoLog "Checking ${instance}: (${description})"

  # Check launch date of instance
  launch_time=$(aws ec2 describe-instances --region ${REGION} --instance-ids ${instance} --query 'Reservations[*].Instances[*].[LaunchTime]' --output text | sed 's/T.*$//')
  launch_time_sec=$(date "--date=${launch_time}" +%s)

  # Proceed if the instance launch date is greater than 3 days, otherwise exit. Why? Because we don't want alerts for recently launched instances.
  [[ ${launch_time_sec} > ${DAYS_MIN_SEC} ]] && DoLog "${instance} (${description}) was launched less than $DAYS_MIN days ago, not alerting." && continue

  # Grab all volume IDs attached to this particular instance
  volume_list=$(aws ec2 describe-volumes --region ${REGION} --filters Name=attachment.instance-id,Values=${instance} --query Volumes[].VolumeId --output text)

  for volume in ${volume_list}; do
    # Grab all snapshot associated with this particular volume, and find the most recent snapshot time
    last_snap=$(aws ec2 describe-snapshots --region ${REGION} --output=text --filters "Name=volume-id,Values=${volume}" --query Snapshots[].[StartTime] | sed 's/T.*$//' | sort -u | tail -n1)

    if [[ -z ${last_snap} ]]; then
      DoAlert
    else
      last_snap_sec=$(date "--date=${last_snap}" +%s)

      # If the latest snapshot is older than $DAYS_MIN, send an alert.
      if [[ ${last_snap_sec} < ${DAYS_MIN_SEC} ]]; then
        DoAlert
      fi
    fi
  done
done


Terminate