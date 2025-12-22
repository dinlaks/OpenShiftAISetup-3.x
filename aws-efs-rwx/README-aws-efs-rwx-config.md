# Complete Guide: AWS EFS RWX Storage for OpenShift AI

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Architecture](#architecture)
4. [Step-by-Step Setup](#step-by-step-setup)
5. [Validation and Testing](#validation-and-testing)
6. [Usage for OpenShift AI](#usage-for-openshift-ai)
7. [Automation Script](#automation-script)
8. [Troubleshooting](#troubleshooting)
9. [Clean Up](#clean-up)

---

## Overview

This guide walks you through setting up AWS EFS (Elastic File System) as ReadWriteMany (RWX) storage for OpenShift 4.20 and OpenShift AI 3.0 on AWS.

**What you'll accomplish:**
- Install AWS EFS CSI Driver Operator
- Create an EFS file system with mount targets
- Configure security groups for NFS access
- Set up static provisioning for RWX storage
- Validate with test workloads
- Create reusable storage for OpenShift AI workbenches

**Important Note:** The AWS EFS Operator for OpenShift does NOT support dynamic provisioning. We'll use **static provisioning** with EFS Access Points, which is reliable and production-ready.

---

## Prerequisites

### Required Tools
- `oc` CLI (OpenShift command-line tool)
- `aws` CLI (AWS command-line tool) configured with proper credentials
- Cluster admin access to OpenShift 4.20
- OpenShift AI 3.0 installed

### AWS Permissions Required
Your AWS credentials need permissions for:
- EFS: CreateFileSystem, CreateMountTarget, CreateAccessPoint, DescribeFileSystems, DescribeMountTargets
- EC2: DescribeInstances, DescribeVpcs, DescribeSubnets, DescribeSecurityGroups, AuthorizeSecurityGroupIngress
- VPC: Access to query network information

### Verify Prerequisites

```bash
# Check OpenShift access
oc whoami
oc get nodes

# Check AWS CLI
aws sts get-caller-identity

# Get your cluster infrastructure name
CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
echo "Cluster Infrastructure Name: $CLUSTER_NAME"
```

---

## Architecture

### Components
1. **EFS File System**: Shared network file system in AWS
2. **Mount Targets**: Network endpoints in each availability zone
3. **Access Points**: Isolated entry points to the file system (one per PVC)
4. **EFS CSI Driver**: Kubernetes CSI driver that mounts EFS to pods
5. **Static PVs**: Pre-created PersistentVolumes pointing to access points
6. **PVCs**: PersistentVolumeClaims that bind to static PVs

### Data Flow
```
Pod → PVC → PV → EFS Access Point → EFS File System → EFS Mount Target → Worker Node
```

---

## Step-by-Step Setup

### Step 1: Install AWS EFS CSI Driver Operator

#### 1.1 Create Operator Namespace

Apply the manifest from `manifests/01-namespace.yaml`:
```bash
oc apply -f manifests/01-namespace.yaml
```

#### 1.2 Install the Operator

Apply the manifest from `manifests/02-operator-group-subscription.yaml`:
```bash
oc apply -f manifests/02-operator-group-subscription.yaml
```

#### 1.3 Wait for Operator Installation

```bash
# Watch operator installation (wait for "Succeeded")
oc get csv -n openshift-cluster-csi-drivers -w

# Verify operator pod is running
oc get pods -n openshift-cluster-csi-drivers
```

Expected output:
```
NAME                                READY   STATUS    RESTARTS   AGE
aws-efs-operator-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
```

#### 1.4 Create ClusterCSIDriver Instance

Apply the manifest from `manifests/03-cluster-csi-driver.yaml`:
```bash
oc apply -f manifests/03-cluster-csi-driver.yaml
```

#### 1.5 Verify CSI Driver Deployment

```bash
# Check CSI driver pods (should see node pods on each worker)
oc get pods -n openshift-cluster-csi-drivers | grep efs

# Check CSI driver
oc get csidriver efs.csi.aws.com
```

Expected output:
```
NAME                                READY   STATUS    RESTARTS   AGE
aws-efs-operator-xxxxxxxxxx-xxxxx   1/1     Running   0          5m
efs-csi-node-xxxxx                  3/3     Running   0          4m
efs-csi-node-xxxxx                  3/3     Running   0          4m
efs-csi-node-xxxxx                  3/3     Running   0          4m
```

**Note:** You will only see node pods (DaemonSet), NOT a controller deployment. This is expected.

---

### Step 2: Create EFS File System

#### 2.1 Get Cluster Network Information

```bash
# Get cluster infrastructure name
CLUSTER_NAME=$(oc get infrastructure cluster -o jsonpath='{.status.infrastructureName}')
echo "Cluster Name: $CLUSTER_NAME"

# Get VPC ID
VPC_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    --query 'Reservations[0].Instances[0].VpcId' --output text)
echo "VPC ID: $VPC_ID"

# Get private subnet IDs
SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=*private*" \
    --query 'Subnets[*].SubnetId' --output text)
echo "Private Subnets: $SUBNET_IDS"

# Get worker security group
WORKER_SG=$(aws ec2 describe-instances \
    --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
    "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)
echo "Worker Security Group: $WORKER_SG"
```

Save these values - you'll need them!

#### 2.2 Create EFS File System

```bash
# Create EFS file system
FILE_SYSTEM_ID=$(aws efs create-file-system \
    --performance-mode generalPurpose \
    --throughput-mode bursting \
    --encrypted \
    --tags Key=Name,Value=openshift-ai-efs Key=Cluster,Value=${CLUSTER_NAME} \
    --query 'FileSystemId' --output text)

echo "EFS File System ID: $FILE_SYSTEM_ID"
```

**Important:** Save this `FILE_SYSTEM_ID` - you'll use it throughout this guide.

#### 2.3 Wait for EFS to Be Available

```bash
# Check EFS status (wait for "available")
aws efs describe-file-systems --file-system-id $FILE_SYSTEM_ID \
    --query 'FileSystems[0].LifeCycleState' --output text
```

Wait until it shows `available` (usually takes 10-20 seconds).

---

### Step 3: Configure Security Groups

#### 3.1 Allow NFS Traffic Between Worker Nodes

```bash
# Add NFS (port 2049) ingress rule to worker security group
aws ec2 authorize-security-group-ingress \
    --group-id $WORKER_SG \
    --protocol tcp \
    --port 2049 \
    --source-group $WORKER_SG

echo "Added NFS rule to worker security group"
```

If you see an error about the rule already existing, that's fine.

#### 3.2 Verify Security Group Rule

```bash
# Verify port 2049 is allowed
aws ec2 describe-security-groups --group-ids $WORKER_SG \
    --query 'SecurityGroups[0].IpPermissions[?ToPort==`2049`]'
```

You should see a rule allowing TCP port 2049 from the same security group.

---

### Step 4: Create EFS Mount Targets

Mount targets are required in each availability zone so pods can access EFS.

#### 4.1 Create Mount Targets in Each Subnet

```bash
# Create mount target in each private subnet
for subnet in $SUBNET_IDS; do
    echo "Creating mount target in subnet: $subnet"
    aws efs create-mount-target \
        --file-system-id $FILE_SYSTEM_ID \
        --subnet-id $subnet \
        --security-groups $WORKER_SG
    echo ""
done
```

#### 4.2 Wait for Mount Targets to Be Available

```bash
echo "Waiting for mount targets to become available..."
sleep 30

# Check mount target status
aws efs describe-mount-targets --file-system-id $FILE_SYSTEM_ID \
    --query 'MountTargets[*].[MountTargetId,SubnetId,LifeCycleState,IpAddress]' \
    --output table
```

**Wait until all mount targets show `LifeCycleState: available`**. This usually takes 1-2 minutes.

You can monitor continuously with:
```bash
watch -n 10 "aws efs describe-mount-targets --file-system-id $FILE_SYSTEM_ID --query 'MountTargets[*].[MountTargetId,SubnetId,LifeCycleState]' --output table"
```

Press `Ctrl+C` when all show "available".

---

### Step 5: Create Storage Class for Static Provisioning

Apply the manifest from `manifests/04-storage-class.yaml`:
```bash
oc apply -f manifests/04-storage-class.yaml
```

Verify:
```bash
oc get storageclass efs-static
```

---

### Step 6: Create Storage Provisioning Script

This script automates the creation of EFS Access Points, PVs, and PVCs.

#### 6.1 Create the Script

```bash
cat > create-efs-storage.sh <<'SCRIPT'
#!/bin/bash
set -e

NAMESPACE=$1
PV_NAME=$2
SIZE=${3:-50Gi}

if [ -z "$NAMESPACE" ] || [ -z "$PV_NAME" ]; then
    echo "Usage: $0 <namespace> <pv-name> [size]"
    echo ""
    echo "Examples:"
    echo "  $0 rhods-notebooks workbench1-storage 100Gi"
    echo "  $0 my-project shared-data 200Gi"
    exit 1
fi

# Set your EFS File System ID here
EFS_ID="YOUR_EFS_FILE_SYSTEM_ID"

if [ "$EFS_ID" = "YOUR_EFS_FILE_SYSTEM_ID" ]; then
    echo "ERROR: Please edit this script and set EFS_ID to your actual EFS file system ID"
    exit 1
fi

echo "Creating EFS access point for $PV_NAME..."
AP_ID=$(aws efs create-access-point \
    --file-system-id $EFS_ID \
    --posix-user Uid=1000,Gid=1000 \
    --root-directory "Path=/${PV_NAME},CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=777}" \
    --tags Key=Name,Value=${PV_NAME} Key=Namespace,Value=${NAMESPACE} \
    --query 'AccessPointId' --output text)

echo "Access Point created: $AP_ID"
echo "Creating PV and PVC from manifests..."

# Create PV from template
sed "s/{{PV_NAME}}/${PV_NAME}/g; s/{{EFS_ID}}/${EFS_ID}/g; s/{{AP_ID}}/${AP_ID}/g; s/{{SIZE}}/${SIZE}/g" \
    manifests/05-pv-template.yaml | oc apply -f -

# Create PVC from template
sed "s/{{PV_NAME}}/${PV_NAME}/g; s/{{NAMESPACE}}/${NAMESPACE}/g; s/{{SIZE}}/${SIZE}/g" \
    manifests/06-pvc-template.yaml | oc apply -f -

echo ""
echo "✅ Storage created successfully!"
echo "   PV: ${PV_NAME}"
echo "   PVC: ${PV_NAME} (in namespace ${NAMESPACE})"
echo "   Access Point: ${AP_ID}"
echo "   Size: ${SIZE}"
echo ""
echo "Use this PVC in your workbench or application."
SCRIPT

chmod +x create-efs-storage.sh
```

#### 6.2 Update the Script with Your EFS ID

```bash
# Replace YOUR_EFS_FILE_SYSTEM_ID with your actual EFS ID
sed -i "s/YOUR_EFS_FILE_SYSTEM_ID/${FILE_SYSTEM_ID}/" create-efs-storage.sh

# Verify it was updated
grep "EFS_ID=" create-efs-storage.sh
```

---

## Validation and Testing

### Step 7: Create Test Namespace

```bash
oc new-project test-efs-rwx
```

### Step 8: Create Test Storage

```bash
# Create storage for testing
./create-efs-storage.sh test-efs-rwx test-storage-1 10Gi
```

Expected output:
```
Creating EFS access point for test-storage-1...
Access Point created: fsap-xxxxxxxxxxxxxxxxx
Creating PV and PVC from manifests...
persistentvolume/test-storage-1 created
persistentvolumeclaim/test-storage-1 created

✅ Storage created successfully!
     PV: test-storage-1
     PVC: test-storage-1 (in namespace test-efs-rwx)
     Access Point: fsap-xxxxxxxxxxxxxxxxx
     Size: 10Gi

Use this PVC in your workbench or application.
```

### Step 9: Verify Storage Binding

```bash
# Check PV
oc get pv test-storage-1

# Check PVC
oc get pvc test-storage-1 -n test-efs-rwx
```

Expected output:
```
NAME             STATUS   VOLUME           CAPACITY   ACCESS MODES   STORAGECLASS   AGE
test-storage-1   Bound    test-storage-1   10Gi       RWX            efs-static     30s
```

Both should show `STATUS: Bound`.

### Step 10: Test with First Pod

Apply the manifest from `manifests/07-test-pod-1.yaml`:
```bash
oc apply -f manifests/07-test-pod-1.yaml
```

Wait for pod to be running:
```bash
oc get pod test-pod-1 -n test-efs-rwx -w
```

Check logs:
```bash
oc logs test-pod-1 -n test-efs-rwx
```

Expected output:
```
========================================
EFS RWX Storage Test - Pod 1
========================================
Hostname: test-pod-1
Time: Sat Dec 21 06:00:00 UTC 2025

Creating test file...
10485760 bytes (10 MB, 10 MiB) copied, 0.123456 s, 85.0 MB/s

Files in /data:
total 11M
-rw-r--r--. 1 1000 1000  XXX Dec 21 06:00 test.txt
-rw-r--r--. 1 1000 1000  10M Dec 21 06:00 testfile.bin

✅ SUCCESS! Pod 1 can write to EFS!

Pod running... (keeping alive for 1 hour)
```

### Step 11: Test RWX with Second Pod

Apply the manifest from `manifests/08-test-pod-2.yaml`:
```bash
oc apply -f manifests/08-test-pod-2.yaml
```

Wait for pod to be running:
```bash
oc get pod test-pod-2 -n test-efs-rwx -w
```

Check logs:
```bash
oc logs test-pod-2 -n test-efs-rwx
```

Expected output should show:
- Pod 2 can see files created by Pod 1
- Pod 2 can read test.txt written by Pod 1
- Pod 2 can append to the shared file
- Both pods are reading/writing the same storage (RWX confirmed!)

### Step 12: Verify Both Pods Are Running

```bash
oc get pods -n test-efs-rwx
```

Expected output:
```
NAME         READY   STATUS    RESTARTS   AGE
test-pod-1   1/1     Running   0          5m
test-pod-2   1/1     Running   0          2m
```

**✅ If both pods are running and Pod 2 can see Pod 1's files, your RWX storage is working perfectly!**

---

## Usage for OpenShift AI

Now that storage is validated, you can use it for OpenShift AI workbenches and applications.

### Create Storage for OpenShift AI Namespace

```bash
# Create storage for a data science workbench
./create-efs-storage.sh rhods-notebooks user1-workbench 100Gi

# Create storage for shared datasets
./create-efs-storage.sh rhods-notebooks shared-datasets 500Gi

# Create storage for pipeline artifacts
./create-efs-storage.sh rhods-notebooks pipeline-artifacts 200Gi
```

### Use in Jupyter Notebook Workbench

When creating a workbench in OpenShift AI dashboard:

1. Go to Data Science Projects
2. Create or select a project
3. Create a workbench
4. Under "Cluster storage", select "Use existing persistent storage"
5. Select the PVC you created (e.g., `user1-workbench`)

### Use in Custom Pod/Deployment

Apply your custom pod manifest with the PVC reference. For example:

```yaml
apiVersion: v1
kind: Pod
metadata:
    name: my-notebook
    namespace: rhods-notebooks
spec:
    containers:
    - name: notebook
        image: quay.io/modh/odh-pytorch-notebook:latest
        volumeMounts:
        - name: workbench-storage
            mountPath: /opt/app-root/src
    volumes:
    - name: workbench-storage
        persistentVolumeClaim:
            claimName: user1-workbench  # Your PVC name
```

### Multiple Users Sharing Data

You can have multiple workbenches access the same PVC for shared datasets:

```bash
# Create shared storage
./create-efs-storage.sh rhods-notebooks team-shared-data 1Ti

# Multiple users can mount the same PVC in their workbenches
# Just select "team-shared-data" when creating each workbench
```

---

## Automation Script

### Quick Reference Script

Save this for your team:

```bash
cat > efs-quick-provision.sh <<'SCRIPT'
#!/bin/bash
# Quick EFS Storage Provisioning for OpenShift AI
# Usage: ./efs-quick-provision.sh <user-name> [size]

USER=$1
SIZE=${2:-100Gi}

if [ -z "$USER" ]; then
    echo "Usage: $0 <user-name> [size]"
    echo "Example: $0 alice 100Gi"
    exit 1
fi

NAMESPACE="rhods-notebooks"
PV_NAME="${USER}-workbench"

echo "Creating storage for user: $USER"
./create-efs-storage.sh $NAMESPACE $PV_NAME $SIZE

echo ""
echo "✅ Done! User $USER can now use PVC: $PV_NAME"
echo "   Tell them to select '$PV_NAME' when creating their workbench"
SCRIPT

chmod +x efs-quick-provision.sh
```

Usage:
```bash
# Quickly create storage for a user
./efs-quick-provision.sh alice 100Gi
./efs-quick-provision.sh bob 200Gi
```

---

## Troubleshooting

### PVC Stays in Pending

**Symptom:**
```bash
oc get pvc my-pvc -n my-namespace
NAME     STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   AGE
my-pvc   Pending                                      efs-static     2m
```

**Solution:**
1. Check if PV exists:
     ```bash
     oc get pv my-pvc
     ```

2. Check PV status:
     ```bash
     oc describe pv my-pvc
     ```

3. Ensure PV is not already bound to another claim

4. Check PVC details:
     ```bash
     oc describe pvc my-pvc -n my-namespace
     ```

### Pod Stuck in ContainerCreating

**Symptom:**
```bash
oc get pod my-pod -n my-namespace
NAME     READY   STATUS              RESTARTS   AGE
my-pod   0/1     ContainerCreating   0          5m
```

**Solution:**
1. Check pod events:
     ```bash
     oc describe pod my-pod -n my-namespace
     ```

2. Look for mount errors. Common issues:
     - Mount targets not available
     - Security group blocking NFS traffic
     - Node CSI driver not running

3. Check CSI driver node pods:
     ```bash
     oc get pods -n openshift-cluster-csi-drivers | grep efs-csi-node
     ```

4. Check CSI driver logs:
     ```bash
     NODE_NAME=$(oc get pod my-pod -n my-namespace -o jsonpath='{.spec.nodeName}')
     oc logs -n openshift-cluster-csi-drivers -l app=aws-efs-csi-driver-node \
         --field-selector spec.nodeName=$NODE_NAME --tail=100
     ```

### Mount Timeout Errors

**Symptom:** Pod events show "mount.nfs: Connection timed out"

**Solution:**
1. Verify mount targets are available:
     ```bash
     aws efs describe-mount-targets --file-system-id $FILE_SYSTEM_ID \
         --query 'MountTargets[*].[SubnetId,LifeCycleState,IpAddress]' --output table
     ```

2. Check security group allows NFS:
     ```bash
     aws ec2 describe-security-groups --group-ids $WORKER_SG \
         --query 'SecurityGroups[0].IpPermissions[?ToPort==`2049`]'
     ```

3. If no rule exists, add it:
     ```bash
     aws ec2 authorize-security-group-ingress \
         --group-id $WORKER_SG \
         --protocol tcp \
         --port 2049 \
         --source-group $WORKER_SG
     ```

### Access Denied or Permission Errors

**Symptom:** Pod can mount but gets permission denied when writing

**Solution:**
1. Check the access point configuration (UID/GID should be 1000:1000)

2. Verify directory permissions are 777 in the access point

3. Check pod's security context - it should run as UID 1000

### List All EFS Resources

```bash
# List all EFS file systems
aws efs describe-file-systems \
    --query 'FileSystems[*].[FileSystemId,Name,LifeCycleState]' --output table

# List all access points for your file system
aws efs describe-access-points --file-system-id $FILE_SYSTEM_ID \
    --query 'AccessPoints[*].[AccessPointId,Name,LifeCycleState]' --output table

# List all PVs using EFS
oc get pv -o custom-columns=NAME:.metadata.name,DRIVER:.spec.csi.driver,HANDLE:.spec.csi.volumeHandle | grep efs
```

---

## Clean Up

### Remove Test Resources

```bash
# Delete test pods
oc delete pod test-pod-1 test-pod-2 -n test-efs-rwx

# Delete test PVC (this does NOT delete the EFS access point or data)
oc delete pvc test-storage-1 -n test-efs-rwx

# Delete test PV
oc delete pv test-storage-1

# Delete test namespace
oc delete project test-efs-rwx
```

### Remove Specific Storage

To completely remove a storage volume:

```bash
# 1. Delete the PVC
oc delete pvc <pvc-name> -n <namespace>

# 2. Delete the PV
oc delete pv <pv-name>

# 3. Delete the EFS access point (optional - this deletes the data!)
# Get the access point ID from the PV before deleting
ACCESS_POINT_ID="fsap-xxxxx"
aws efs delete-access-point --access-point-id $ACCESS_POINT_ID
```

**Warning:** Deleting the EFS access point will delete all data stored in it!

### Complete Teardown (Only if removing everything)

```bash
# 1. Delete all PVCs and PVs
oc delete pv -l storageclass=efs-static
oc delete pvc --all -n rhods-notebooks

# 2. Delete all access points
for ap in $(aws efs describe-access-points --file-system-id $FILE_SYSTEM_ID --query 'AccessPoints[*].AccessPointId' --output text); do
    aws efs delete-access-point --access-point-id $ap
done

# 3. Delete mount targets
for mt in $(aws efs describe-mount-targets --file-system-id $FILE_SYSTEM_ID --query 'MountTargets[*].MountTargetId' --output text); do
    aws efs delete-mount-target --mount-target-id $mt
done

# Wait 2 minutes for mount targets to be deleted
sleep 120

# 4. Delete EFS file system
aws efs delete-file-system --file-system-id $FILE_SYSTEM_ID

# 5. Uninstall operator
oc delete subscription aws-efs-csi-driver-operator -n openshift-cluster-csi-drivers
oc delete csv -n openshift-cluster-csi-drivers -l operators.coreos.com/aws-efs-csi-driver-operator.openshift-cluster-csi-drivers
oc delete clustercsidrivers efs.csi.aws.com
```

---

## Summary

You now have a production-ready RWX storage solution for OpenShift AI using AWS EFS with:

✅ **Installed** AWS EFS CSI Driver Operator  
✅ **Created** EFS file system with mount targets  
✅ **Configured** security groups for NFS access  
✅ **Set up** static provisioning with access points  
✅ **Validated** RWX functionality with test pods  
✅ **Automated** storage creation with reusable scripts  

### Key Points to Remember

1. **Static Provisioning Only**: The operator doesn't support dynamic provisioning. You must create PVs manually.

2. **One Access Point per PVC**: Each PVC gets its own EFS access point for isolation.

3. **Shared Storage**: Multiple pods can mount the same PVC for true RWX access.

4. **Data Persistence**: Data is stored in EFS and persists even if pods, PVCs, or PVs are deleted (unless you delete the access point).

5. **Use the Script**: Always use `create-efs-storage.sh` to provision storage - it handles everything automatically.

### Next Steps

- Create storage for your OpenShift AI users
- Configure workbenches to use the storage
- Set up shared datasets for teams
- Monitor EFS usage in AWS Console
