#!/bin/bash
# gawk and gsed was recommended to me 
set -eo pipefail

INSTANCE_ID=$1
AWS_REGION=$2

if [ -z "$1" ] || [ -z "$2" ]; then
    echo -e "\nUsage: ./encrypt-ebs-vol.sh <INSTANCE_ID> <AWS_REGION>"
    echo -e "Example: ./encrypt-ebs-vol.sh i-1234567890abcdef0 us-east-1"
    exit 1
fi

echo -e "#####################################################"
echo -e "## Stopping EC2 instance ############################"
echo -e "#####################################################"
# Function to get the current state of the instance
aws --output json  --region ${AWS_REGION} ec2 stop-instances --instance-ids ${INSTANCE_ID}
retval=$?; if [ $retval -ne 0 ]; then echo "problem stopping instance $INSTANCE_ID $retval"; exit $retVal; fi
get_instance_state() {
  aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[*].Instances[*].State.Name" --output text
  retval=$?; if [ $retval -ne 0 ]; then echo "problem stopping instance $INSTANCE_ID $retval"; exit $retVal; fi
}
STATE=$(get_instance_state)

# Loop until the instance is stopped
while [ "$STATE" != "stopped" ]; do
  echo "Instance state: $STATE"
  sleep 10  # Wait for 10 seconds before checking again 
  STATE=$(get_instance_state)
done
echo "Instance $INSTANCE_ID is now stopped."
#echo -e "\nWaiting 3m to ensure instance is fully stopped.."
#sleep 180

# Get instance details
echo "Getting now all the required details............" 
KMS_KEY_ALIAS=alias/test-key
SNAPSHOT_NAME="encrypted-test-snap"
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


echo -e "#####################################################"
echo -e "## Creating First Snapshot ##########################"
echo -e "#####################################################"
echo -e "\nCreating a snapshot of the EBS volume ${VOLUME_ID}"
SOURCE_SNAPSHOT_ID=$(aws --output json  --region $AWS_REGION ec2 create-snapshot --volume-id $VOLUME_ID --description "$VOLUME_ID snapshot" --tag-specifications "ResourceType=snapshot,Tags=$VOLUME_TAGS" | jq -r .SnapshotId)
retval=$?; if [ $retval -ne 0 ]; then echo "Problem Creating First Snapshot $retval"; exit $retVal; fi
get_snapshot_state() {
  aws ec2 describe-snapshots --snapshot-ids $SOURCE_SNAPSHOT_ID --query "Snapshots[*].State" --output text
  retval=$?; if [ $retval -ne 0 ]; then echo "Problem getting details about Snapshot $retval"; exit $retVal; fi
}
STATE=$(get_snapshot_state)
while [ "$STATE" != "completed" ]; do
  echo "Snapshot state: $STATE"
  sleep 10  # Wait for 10 seconds before checking again
  STATE=$(get_snapshot_state)
  retval=$?; if [ $retval -ne 0 ]; then echo "Problem getting details about Snapshot $retval"; exit $retVal; fi
done
echo "Snapshot $SNAPSHOT_ID is now completed."

echo -e "#####################################################"
echo -e "## Copy Snapshot and Encrypt ########################"
echo -e "#####################################################"
echo -e "\nCopying the volume ${VOLUME_ID} snapshot ${SOURCE_SNAPSHOT_ID} and encrypting it with KMS key alias ${KMS_KEY_ALIAS}.."
SNAPSHOT_ID=$(aws --output json --region $AWS_REGION ec2 copy-snapshot --region $AWS_REGION --tag-specifications "ResourceType=snapshot,Tags=[{Key=Name,Value=$SNAPSHOT_NAME}]" --source-region $AWS_REGION --source-snapshot-id $SOURCE_SNAPSHOT_ID --description "Snapshot copy of $SOURCE_SNAPSHOT_ID" --encrypted --kms-key-id $KMS_KEY_ALIAS | jq -r .SnapshotId)
retval=$?; if [ $retval -ne 0 ]; then echo "Problem Creating First Snapshot $retval"; exit $retVal; fi
get_snapshot_state() {
  aws ec2 describe-snapshots --snapshot-ids $SNAPSHOT_ID --query "Snapshots[*].State" --output text
}
STATE=$(get_snapshot_state)
while [ "$STATE" != "completed" ]; do
  echo "Snapshot state: $STATE"
  sleep 20  # Wait for 10 seconds before checking again
  STATE=$(get_snapshot_state)
done
echo "Snapshot $SNAPSHOT_ID is now completed."

echo -e "#####################################################"
echo -e "## Create New Volume ################################"
echo -e "#####################################################"
# gp2 volumes do not accept the `--iops` parameter flag
if [[ "${VOLUME_TYPE}" == "gp2" ]]; then
    NEW_VOLUME=$(aws --output json  --region $AWS_REGION ec2 create-volume --encrypted --volume-type $VOLUME_TYPE --size $VOLUME_SIZE --snapshot-id $SNAPSHOT_ID --availability-zone $VOLUME_AZ --tag-specifications "ResourceType=volume,Tags=$VOLUME_TAGS")
    retval=$?; if [ $retval -ne 0 ]; then echo "problem creating new gp2 volume $retval"; exit $retVal; fi
else
    NEW_VOLUME=$(aws --output json  --region $AWS_REGION ec2 create-volume --encrypted --volume-type $VOLUME_TYPE --iops $VOLUME_IOPS --size $VOLUME_SIZE --snapshot-id $SNAPSHOT_ID --availability-zone $VOLUME_AZ --tag-specifications "ResourceType=volume,Tags=$VOLUME_TAGS")
    retval=$?; if [ $retval -ne 0 ]; then echo "problem creating new volume $retval"; exit $retVal; fi
fi
NEW_VOLUME_ID=$(echo $NEW_VOLUME | jq -r .VolumeId)
get_volume_state() {
  aws ec2 describe-volumes --volume-ids $NEW_VOLUME_ID --query "Volumes[*].State" --output text
}
STATE=$(get_volume_state)
while [ "$STATE" != "available" ]; do
  echo "Volume state: $STATE"
  sleep 10  # Wait for 10 seconds before checking again
  STATE=$(get_volume_state)
done
echo "Volume $NEW_VOLUME_ID is now available."

echo -e "#####################################################"
echo -e "## Detach Volume ####################################"
echo -e "#####################################################"
echo -e "\nDettaching the old EBS volume ${VOLUME_ID} from instance ${INSTANCE_ID}"
aws --output json  --region ${AWS_REGION} ec2 detach-volume --volume-id ${VOLUME_ID} --force
retval=$?; if [ $retval -ne 0 ]; then echo "problem detaching volume $VOLUME_ID error $retval"; exit $retVal; fi
echo -e "\nWaiting 1m for the old volume ${VOLUME_ID} to be dettached"
get_volume_attachment_state() {
  aws ec2 describe-volumes --volume-ids $VOLUME_ID --query "Volumes[*].Attachments[*].State" --output text
}
while [ "$STATE" != " " ] && [ "$STATE" = "Available" ]; do
  echo "Volume attachment state: $STATE"
  sleep 10  # Wait for 10 seconds before checking again
  STATE=$(get_volume_attachment_state)
done
echo "Volume $VOLUME_ID is now detached."

echo -e "#####################################################"
echo -e "## Attach New Volume ################################"
echo -e "#####################################################"
echo -e "\nAttaching new volume ${NEW_VOLUME_ID} to instance ${INSTANCE_ID} to ${VOLUME_DEVICE}"
aws --output json  --region ${AWS_REGION} ec2 attach-volume --device ${VOLUME_DEVICE} --instance-id ${INSTANCE_ID} --volume-id ${NEW_VOLUME_ID}
retval=$?; if [ $retval -ne 0 ]; then echo "problem attaching volume $NEW_VOLUME_ID error $retval"; exit $retVal; fi
STATE="CHECK"
while [ "$STATE" != "attached" ]; do
  echo "Volume attachment state: $STATE"
  sleep 10  # Wait for 10 seconds before checking again
  STATE=$(aws ec2 describe-volumes --volume-ids $NEW_VOLUME_ID --query "Volumes[*].Attachments[*].State" --output text)
done
echo "Volume $NEW_VOLUME_ID is now attached."

echo -e "#####################################################"
echo -e "## Starting the EC2 now #############################"
echo -e "#####################################################"
echo -e "\nStarting the instance again.."
aws --output json  --region ${AWS_REGION} ec2 start-instances --instance-ids ${INSTANCE_ID}
retval=$?; if [ $retval -ne 0 ]; then echo "problem starting $INSTANCE_ID error $retval"; exit $retVal; fi
get_instance_state() {
  aws ec2 describe-instances --instance-ids $INSTANCE_ID --query "Reservations[*].Instances[*].State.Name" --output text
  retval=$?; if [ $retval -ne 0 ]; then echo "problem checking instance $INSTANCE_ID $retval"; exit $retVal; fi
}
STATE=$(get_instance_state)
while [ "$STATE" != "running" ]; do
  echo "Instance state: $STATE"
  sleep 10  # Wait for 10 seconds before checking again
  STATE=$(get_instance_state)
done
echo "Instance $INSTANCE_ID is now running."
