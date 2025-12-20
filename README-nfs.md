
# ReadWriteMany Storage for OpenShift AI on AWS - TBD

## Overview

Configure Amazon Elastic File System (EFS) to provide ReadWriteMany (RWX) storage for OpenShift AI workloads. Standard EBS volumes only support ReadWriteOnce (RWO), making EFS the recommended solution for sharing model data across multiple pods.

## Phase 1: AWS Configuration

### Step 1: Create an EFS File System

1. Navigate to AWS Console > EFS
2. Click **Create file system**
3. Set name to `openshift-ai-storage`
4. Select the VPC containing your OpenShift nodes
5. Click **Create** and note the File System ID (e.g., `fs-0123456789abcdef`)

### Step 2: Configure Network Security

1. Locate your OpenShift worker nodes' Security Group
2. Go to EFS File System > **Network** tab
3. Edit the associated Security Group with this Inbound Rule:
    - **Type:** NFS
    - **Protocol:** TCP
    - **Port:** 2049
    - **Source:** OpenShift worker node Security Group ID

### Step 3: Create IAM Policy and Role

Create an IAM Policy named `EFSCSIODriverPolicy`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
     {
        "Effect": "Allow",
        "Action": [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones"
        ],
        "Resource": "*"
     },
     {
        "Effect": "Allow",
        "Action": ["elasticfilesystem:CreateAccessPoint"],
        "Resource": "*",
        "Condition": {
          "StringLike": {
             "aws:RequestTag/efs.csi.aws.com/cluster": "true"
          }
        }
     },
     {
        "Effect": "Allow",
        "Action": "elasticfilesystem:DeleteAccessPoint",
        "Resource": "*",
        "Condition": {
          "StringLike": {
             "aws:ResourceTag/efs.csi.aws.com/cluster": "true"
          }
        }
     }
  ]
}
```

## Phase 2: OpenShift Configuration

### Step 1: Install AWS EFS CSI Driver Operator

1. Log in to OpenShift Web Console as administrator
2. Go to **Operators > OperatorHub**
3. Search for "AWS EFS CSI Driver Operator" and click **Install**
4. Use default namespace: `openshift-cluster-csi-drivers`

### Step 2: Create ClusterCSIDriver Instance

1. Go to **Administration > CustomResourceDefinitions**
2. Search for `ClusterCSIDriver` and click the **Instances** tab
3. Create with this YAML:

```yaml
apiVersion: operator.openshift.io/v1
kind: ClusterCSIDriver
metadata:
  name: efs.csi.aws.com
spec:
  managementState: Managed
```

### Step 3: Create StorageClass

Go to **Storage > StorageClasses > Create StorageClass**. Replace `<file-system-id>` with your actual EFS ID:

```yaml
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-rwx
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: <fs-0123456789abcdef>
  directoryPerms: "777"
  gidRangeStart: "1000"
  gidRangeEnd: "2000"
  basePath: "/dynamic_provisioning"
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

## Phase 3: Using RWX Storage in OpenShift AI

### Step 1: Create Persistent Volume Claim

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ai-model-shared-storage
  namespace: <your-data-science-project-namespace>
spec:
  accessModes:
     - ReadWriteMany
  resources:
     requests:
        storage: 100Gi
  storageClassName: efs-rwx
  volumeMode: Filesystem
```


### Step 1.5: Validate RWX Storage with Sample Deployment

Create a test deployment to verify multiple pods can write to the shared storage simultaneously:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
    name: efs-rwx-validator
    namespace: <your-data-science-project-namespace>
spec:
    replicas: 2
    selector:
        matchLabels:
            app: efs-test
    template:
        metadata:
            labels:
                app: efs-test
        spec:
            containers:
            - name: writer
                image: registry.access.redhat.com/ubi8/ubi-minimal
                command: ["/bin/sh"]
                args:
                    - "-c"
                    - "while true; do echo \"Data from $(hostname) at $(date)\" >> /mnt/shared-data/validation.log; sleep 5; done"
                volumeMounts:
                - name: shared-storage
                    mountPath: /mnt/shared-data
            volumes:
            - name: shared-storage
                persistentVolumeClaim:
                    claimName: ai-model-shared-storage
```

Deploy and verify both pod replicas write concurrently to the same log file, confirming RWX functionality is working correctly.



### Step 2: Connect to OpenShift AI Workbench

1. Open OpenShift AI Dashboard
2. Go to your Data Science Project
3. Create a Workbench or Data Connection
4. Select **Existing Persistent Volume Claim**
5. Choose `ai-model-shared-storage`

Multiple notebooks and model-serving pods can now mount the same PVC simultaneously.
