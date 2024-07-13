#!/bin/bash

set -eo pipefail

VOLUME_ID=$1

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

# sed to edit the terraform template  

terraform import 

terraform destroy --auto-approve 