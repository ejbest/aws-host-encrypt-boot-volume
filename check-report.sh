#!/bin/bash

set -eo pipefail
INSTANCE_ID=$1
AWS_REGION=$2

if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "\nUsage: ./encrypt-ebs-vol.sh <INSTANCE_ID> <AWS_REGION>"
    echo -e "Example: ./encrypt-ebs-vol.sh i-1234567890abcdef0 us-east-1"
    exit 1
fi

echo "Instance for task.............: $INSTANCE_ID"
echo "Regionn.......................: $AWS_REGION"
AZ=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep Availability | cut -f 6 -d "|" | awk '{$1=$1;print}')
echo "Availability Zone.............: $AZ"

# Get instance details
INSTANCE_INFO=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" )
# Do I need the above 

VOLUME=$(aws ec2 describe-instances | grep -i volume | cut -d "|" -f7 | awk '{$1=$1;print}')
echo "Root Volume...................: $VOLUME"

ROOT_DEVICE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID  | grep "RootDeviceName" | cut -d "|" -f5 | awk '{$1=$1;print}')
BLOCK_DEVICE=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID | grep "  DeviceName"   | cut -d "|" -f6 | awk '{$1=$1;print}')
echo "Root Device Name..............: $ROOT_DEVICE"
echo "Block Device Name.............: $BLOCK_DEVICE"
if [ "$ROOT_DEVICE" == "$BLOCK_DEVICE" ]; then
  echo "Device Name for drive.........: Devices Match"
else
  echo "Red Flags - Investiate........: DEVICES DIFFER Red Flags"
  echo "Red Flags - Investiate........: DEVICES DIFFER Red Flags"
  echo "Red Flags - Investiate........: DEVICES DIFFER Red Flags"
  echo "Red Flags - Investiate........: DEVICES DIFFER Red Flags"
fi

ENCRYPTED_STATUS=$(aws ec2 describe-volumes --volume-ids $VOLUME --query "Volumes[0].Encrypted" --output text)
echo "Volume Encryption Status......: $ENCRYPTED_STATUS"

aws ec2 describe-tags --filters "Name=resource-id,Values=$VOLUME"
