#!/bin/bash

set -eo pipefail

INSTANCE_ID=$1
AWS_REGION=$2

if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "\nUsage: ./encrypt-ebs-vol.sh <INSTANCE_ID> <AWS_REGION>"
    echo -e "Example: ./encrypt-ebs-vol.sh i-1234567890abcdef0 us-east-1"
    exit 1
fi

echo -e "Stopping EC2 instance.."
aws --output json  --region ${AWS_REGION} ec2 stop-instances --instance-ids ${INSTANCE_ID}
retval=$?; if [ $retval -ne 0 ]; then echo "problem stopping instance $INSTANCE_ID $retval"; exit $retVal; fi

echo -e "\nWaiting 3m to ensure instance is fully stopped.."
sleep 180

# Get instance details
KMS_KEY_ALIAS=alias/test-key
INSTANCE=$(aws --output json --region $AWS_REGION ec2 describe-instances --instance-ids $INSTANCE_ID)
retval=$?; if [ $retval -ne 0 ]; then echo "problem obtaining $INSTANCE_ID  $retval"; exit $retVal; fi
VOLUME_ID=$(echo $INSTANCE | jq -r .Reservations[].Instances[].BlockDeviceMappings[].Ebs.VolumeId)
VOLUME_DEVICE=$(echo $INSTANCE | jq -r .Reservations[].Instances[].BlockDeviceMappings[].DeviceName)

# Get volume details
VOLUME=$(aws --output json --region $AWS_REGION ec2 describe-volumes --volume-id $VOLUME_ID)
retval=$?; if [ $retval -ne 0 ]; then echo "problem obtaining $VOLUME_ID details $retval"; exit $retVal; fi
VOLUME_AZ=$(echo $VOLUME | jq -r .Volumes[].AvailabilityZone)
VOLUME_TYPE=$(echo $VOLUME | jq -r .Volumes[].VolumeType)
VOLUME_IOPS=$(echo $VOLUME | jq -r .Volumes[].Iops)
VOLUME_SIZE=$(echo $VOLUME | jq -r .Volumes[].Size)

# Get Volume Tags details
VOLUME_TAGS=$(echo $VOLUME | jq -r '.Volumes[].Tags' | sed 's|\: |\=|g' | sed 's|\"||g')
VOLUME_TAGS=$(echo $VOLUME_TAGS | sed 's|\ ||g')

echo -e "\nCreating a snapshot of the EBS volume ${VOLUME_ID}"
SOURCE_SNAPSHOT_ID=$(aws --output json  --region $AWS_REGION ec2 create-snapshot --volume-id $VOLUME_ID --description "$VOLUME_ID snapshot" --tag-specifications "ResourceType=snapshot,Tags=$VOLUME_TAGS" | jq -r .SnapshotId)

echo -e "\nWaiting 5m to ensure snapshot ${SOURCE_SNAPSHOT_ID} is ready"
sleep 300

echo -e "\nCopying the volume ${VOLUME_ID} snapshot ${SOURCE_SNAPSHOT_ID} and encrypting it with KMS key alias ${KMS_KEY_ALIAS}.."
SNAPSHOT_ID=$(aws --output json --region $AWS_REGION ec2 copy-snapshot --region $AWS_REGION --source-region $AWS_REGION --source-snapshot-id $SOURCE_SNAPSHOT_ID --description "Snapshot copy of $SOURCE_SNAPSHOT_ID" --encrypted --kms-key-id $KMS_KEY_ALIAS | jq -r .SnapshotId)

echo -e "\nWaiting 5m to ensure copied snapshot ${SNAPSHOT_ID} is ready"
sleep 300

echo -e "\nCreating new encrypted volume from snapshot ${SNAPSHOT_ID}"

# gp2 volumes do not accept the `--iops` parameter flag
if [[ "${VOLUME_TYPE}" == "gp2" ]]; then
    NEW_VOLUME=$(aws --output json  --region $AWS_REGION ec2 create-volume --encrypted --volume-type $VOLUME_TYPE --size $VOLUME_SIZE --snapshot-id $SNAPSHOT_ID --availability-zone $VOLUME_AZ --tag-specifications "ResourceType=volume,Tags=$VOLUME_TAGS")
    retval=$?; if [ $retval -ne 0 ]; then echo "problem creating new gp2 volume $retval"; exit $retVal; fi
else
    NEW_VOLUME=$(aws --output json  --region $AWS_REGION ec2 create-volume --encrypted --volume-type $VOLUME_TYPE --iops $VOLUME_IOPS --size $VOLUME_SIZE --snapshot-id $SNAPSHOT_ID --availability-zone $VOLUME_AZ --tag-specifications "ResourceType=volume,Tags=$VOLUME_TAGS")
    retval=$?; if [ $retval -ne 0 ]; then echo "problem creating new volume $retval"; exit $retVal; fi
fi

NEW_VOLUME_ID=$(echo $NEW_VOLUME | jq -r .VolumeId)

echo -e "\nWaiting 5m for the new volume ${NEW_VOLUME_ID} to be created"
sleep 300

echo -e "\nDettaching the old EBS volume ${VOLUME_ID} from instance ${INSTANCE_ID}"
aws --output json  --region ${AWS_REGION} ec2 detach-volume --volume-id ${VOLUME_ID} --force
retval=$?; if [ $retval -ne 0 ]; then echo "problem detaching volume $VOLUME_ID error $retval"; exit $retVal; fi

echo -e "\nWaiting 1m for the old volume ${VOLUME_ID} to be dettached"
sleep 60

echo -e "\nAttaching new volume ${NEW_VOLUME_ID} to instance ${INSTANCE_ID} to ${VOLUME_DEVICE}"
aws --output json  --region ${AWS_REGION} ec2 attach-volume --device ${VOLUME_DEVICE} --instance-id ${INSTANCE_ID} --volume-id ${NEW_VOLUME_ID}
retval=$?; if [ $retval -ne 0 ]; then echo "problem attaching volume $NEW_VOLUME_ID error $retval"; exit $retVal; fi

echo -e "\nWaiting 1m for the new volume to be attached"
sleep 60

echo -e "\nStarting the instance again.."
aws --output json  --region ${AWS_REGION} ec2 start-instances --instance-ids ${INSTANCE_ID}
retval=$?; if [ $retval -ne 0 ]; then echo "problem starting $INSTANCE_ID error $retval"; exit $retVal; fi
