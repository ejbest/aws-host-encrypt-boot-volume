#!/bin/bash

set -eo pipefail

VOLUME_ID=$1
VOLUME_ID_NEW=$2

# Delete old EBS volume and all associated snapshots
SNAPSHOT_IDS=$(aws ec2 describe-snapshots --filters Name=volume-id,Values=${VOLUME_ID} --query 'Snapshots[*].SnapshotId' --output text)


for SNAPSHOT_ID in $SNAPSHOT_IDS; do
  echo "Deleting snapshot $SNAPSHOT_ID"
  aws ec2 delete-snapshot --snapshot-id $SNAPSHOT_ID
done

echo -e "\nDeleting the old EBS volume ${VOLUME_ID}"
aws ec2 delete-volume --volume-id ${VOLUME_ID}

# Check if the deletion was successful
if [ $? -eq 0 ]; then
  echo "EBS volume $VOLUME_ID has been deleted successfully."
else
  echo "Failed to delete EBS volume $VOLUME_ID."
fi

# Get size of New EBS volume and add code in main.tf for importing

VOLUME_SIZE=$(aws ec2 describe-volumes --volume-ids $VOLUME_ID_NEW --query "Volumes[0].Size" --output text)

TF_CODE="
resource \"aws_ebs_volume\" \"new_volume\" {
  availability_zone = \"unknown\"
  size              = $VOLUME_SIZE
}
"

TF_FILE="main.tf"
echo "$TF_CODE" >> $TF_FILE

echo "EBS resource code appended to $TF_FILE"

# Import new EBS volume in terraform
terraform import aws_ebs_volume.new_volume $VOLUME_ID_NEW

#Running terrafom destroy
terraform destroy --auto-approve 
