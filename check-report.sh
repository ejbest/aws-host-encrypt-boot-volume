#!/bin/bash

set -eo pipefail
INSTANCE_ID=$1
AWS_REGION=$2

if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "\nUsage: ./encrypt-ebs-vol.sh <INSTANCE_ID> <AWS_REGION>"
    echo -e "Example: ./encrypt-ebs-vol.sh i-1234567890abcdef0 us-east-1"
    exit 1
fi

# Get instance details
INSTANCE=$(aws --output json --region $AWS_REGION ec2 describe-instances --instance-ids $INSTANCE_ID)
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting INSTANCE_ID $retval"; exit $retVal; fi
VOLUME_ID=$(echo $INSTANCE | jq -r .Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId)
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting VolumeId $retval"; exit $retVal; fi
VOLUME_DEVICE=$(echo $INSTANCE | jq -r .Reservations[].Instances[].BlockDeviceMappings[].DeviceName)
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting DeviceName $retval"; exit $retVal; fi

# Get volume details
VOLUME=$(aws --output json --region $AWS_REGION ec2 describe-volumes --volume-id $VOLUME_ID)
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting VOLUME info $retval"; exit $retVal; fi
VOLUME_AZ=$(echo $VOLUME | jq -r .Volumes[].AvailabilityZone)
VOLUME_TYPE=$(echo $VOLUME | jq -r .Volumes[].VolumeType)
VOLUME_IOPS=$(echo $VOLUME | jq -r .Volumes[].Iops)
VOLUME_SIZE=$(echo $VOLUME | jq -r .Volumes[].Size)

echo "Instance......................: $INSTANCE_ID"
echo "Region........................: $AWS_REGION"
echo "Root Volume...................: $VOLUME_ID"
echo "Availability Zone.............: $VOLUME_AZ"
echo "Volume Type...................: $VOLUME_TYPE"
echo "Volume IOPS...................: $VOLUME_IOPS"
echo "Volume Size...................: $VOLUME_SIZE"


ROOT_DEVICE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID  | grep "RootDeviceName" | cut -d "|" -f5 | awk '{$1=$1;print}')
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting RootDeviceName $retval"; exit $retVal; fi

BLOCK_DEVICE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep "  DeviceName"   | cut -d "|" -f6 | awk '{$1=$1;print}')
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting DeviceName $retval"; exit $retVal; fi

echo "Root Device Name..............: $ROOT_DEVICE"
echo "Block Device Name.............: $BLOCK_DEVICE"
if [ "$ROOT_DEVICE" == "$BLOCK_DEVICE" ]; then
  echo "Device Name for drive.........: Devices Match"
else
  echo "Red Flags - Investiate........: DEVICES DIFFER Red Flags"
  echo "Red Flags - Investiate........: DEVICES DIFFER Red Flags"
fi

ENCRYPTED_STATUS=$(aws ec2 describe-volumes --volume-ids $VOLUME_ID --query "Volumes[0].Encrypted" --output json | jq -r '.')
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting VOLUME details $retval"; exit $retVal; fi

echo "Volume Encryption Status......: $ENCRYPTED_STATUS"

aws ec2 --output table describe-tags --filters "Name=resource-id,Values=$VOLUME_ID"
retval=$?; if [ $retval -ne 0 ]; then echo "problem getting device tags $retval"; exit $retVal; fi
