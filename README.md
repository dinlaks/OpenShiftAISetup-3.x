# OpenShift AI (RHOAI) Deployment Guide

This directory contains the GitOps configuration for deploying OpenShift AI operators in the correct dependency order with automated CRD deployment and status verification.

## **Prerequisites**

### **Required Infrastructure**
- **OpenShift 4.20.x cluster** (tested and verified)
- **OC CLI tool** installed and configured
- **GPU-enabled nodes** (NVIDIA GPUs recommended for SLM/LLM workloads)
- **Cluster admin privileges** for operator installation
- **Internet connectivity** for operator image pulls

### **System Requirements**
- **Minimum 3 worker nodes** (recommended for production)
- **GPU nodes** with NVIDIA drivers (for ML/AI workloads)
- **Sufficient resources** for operator pods and workloads
- **Storage** for model storage and data persistence

### Install OpenShift Environment

To install OpenShift with GPU nodes, use the Red Hat Demo Platform Environment

- [AWS with OpenShift Open Environment](https://catalog.demo.redhat.com/catalog?item=babylon-catalog-prod/sandboxes-gpte.sandbox-ocp.prod&utm_source=webapp&utm_medium=share-link)
- Select **OpenShift 4.20.x clusters**
- Select **m6a.4xlarge** 



### **GPU Spot Instance Price Script**
- Once OCP cluster and AI is installed, we can use this **scripts/gpu-config.sh** to find the best price and helps to create a machine

## **Version Compatibility**
> **⚠️ IMPORTANT**: This configuration is specifically tested for:
> - **OpenShift Container Platform 4.20**
> - **RHOAI 3.0**
> 
> For other OCP versions, update the NFD and NVIDIA operator overlay files accordingly.

## **Quick Start**

### **1. Clone and Navigate**
```bash
git clone https://github.com/dinlaks/OpenShiftAISetup.git
cd OpenShiftAISetup
```

### **2. Verify Prerequisites**
```bash
# Check OC CLI
oc version

# Verify cluster access
oc get nodes

# Check for GPU nodes (optional)
oc get nodes -l node-role.kubernetes.io/worker
```

### **3. Deploy All Operators**
```bash
# Make script executable
chmod +x deploy-operators.sh

# Run the deployment script
./deploy-operators.sh
```

## **Deployment Process**

The `deploy-operators.sh` script automatically handles the complete deployment process:

### **Phase 1: Infrastructure Operators**
1. **NFD Operator** - Node Feature Discovery
   - Deploys operator
   - Applies NFD instance CRD
   - Waits for `Status: Available`

2. **NVIDIA GPU Operator** - GPU management
   - Deploys operator
   - Applies ClusterPolicy CRD
   - Waits for `state: ready`

### **Phase 2: Platform Operators**
3. **OpenShift Serverless Operator** - Knative serving
4. **OpenShift Pipelines Operator** - Pipelines
5. **Authorino Operator** - Authentication/Authorization
6. **Cert-Manager Operator** - Certs 
7. **leaderWorkerSet Operator** - Requires for LLM-d
8. **Red Hat Connectivity Link Operator** - Requires for LLM-d
9. **Service Mesh 3 and Kueue are installed automatically via the DataScienceCluster CR** 


### **Phase 3: AI Platform**
6. **RHOAI Operator** - OpenShift AI platform
   - Deploys operator
   - Applies DataScienceCluster CRD
   - Waits for `Status: Ready`

## **Manual Deployment (Alternative)**

If you prefer manual deployment:

```bash
# Deploy operators in order
oc apply -k nfd-operator/base/
oc apply -k nvidia-operator/base/
oc apply -k serverless-operator/base/
oc apply -k pipelines-operator/base/
oc apply -k authorino-operator/base/
oc apply -k cert-manager-operator/base/
oc apply -k lws-operator/base/
oc apply -k rhcl-operator/base/
oc apply -k rhoai-operator/base/

# Apply CRDs after operators are ready
oc apply -k nfd-operator/overlays/crds/
oc apply -k nvidia-operator/overlays/crds/
oc apply -k cert-manager-operator/overlays/crds/
oc apply -k rhoai-operator/overlays/crds/
```

## **Enable UserWorload Monitoring**

```bash
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
    alertmanagerMain:
      enableUserAlertmanagerConfig: true
```

## **Update ODH Dashboard if necessary**

```bash
apiVersion: opendatahub.io/v1alpha
kind: OdhDashboardConfig
metadata:
 name: odh-dashboard-config
 namespace: redhat-ods-applications
spec:
 dashboardConfig:
   disableTracking: false
   disableModelRegistry: false
   disableModelCatalog: false
   disableKServeMetrics: false
   genAiStudio: true
   modelAsService: true
   disableLMEval: false
 notebookController:
   enabled: true
   notebookNamespace: rhods-notebooks
   pvcSize: 20Gi
```

## **Add a Hardware Profile for GPU**

```bash
apiVersion: infrastructure.opendatahub.io/v1alpha1
kind: HardwareProfile
metadata:
 name: gpu-profile
 namespace: redhat-ods-applications
spec:
 identifiers:
   - identifier: cpu
     displayName: CPU
     resourceType: CPU
     minCount: 1
     maxCount: "8"
     defaultCount: "1"
   - identifier: memory
     displayName: Memory
     resourceType: Memory
     minCount: 1Gi
     maxCount: 16Gi
     defaultCount: 12Gi
   - identifier: nvidia.com/gpu
     displayName: GPU
     resourceType: Accelerator
     minCount: 1
     maxCount: 4
     defaultCount: 1
```

## **Verification**

After deployment, verify all components:

```bash
# Check operator pods
oc get pods -n openshift-nfd
oc get pods -n nvidia-gpu-operator
oc get pods -n redhat-ods-operator

# Check CRDs
oc get nfd-instance -n openshift-nfd
oc get clusterpolicy
oc get datasciencecluster

# Check GPU resources
oc describe nodes | grep nvidia.com/gpu
```

## **Accessing OpenShift AI**

1. **Get the dashboard URL**:
   ```bash
   oc get route -n redhat-ods-applications
   ```

2. **Login with OpenShift credentials**
3. **Start using Jupyter notebooks, model serving, and ML pipelines**

## **Troubleshooting**

### **Common Issues**
- **GPU not detected**: Ensure NFD instance is `Available` and GPU nodes are labeled
- **Operators not ready**: Check resource limits and node capacity
- **CRDs not applied**: Verify operator pods are running before applying overlays

### **Useful Commands**
```bash
# Check operator status
oc get csv -n openshift-nfd
oc get csv -n nvidia-gpu-operator

# View operator logs
oc logs -n openshift-nfd deployment/nfd-operator

# Check GPU resources
oc get nodes -o json | jq '.items[].status.allocatable | select(."nvidia.com/gpu")'
```

## **Deploying First Model**
For deploying first model please refer to [deploying a model on Red Hat OpenShift AI 3.0](deploy-model.md)

## ** Configuring MCP Servers**
To configure MCP servers please refer to [configure MCP servers](mcp-servers/)

## **Next Steps**

1. **Configure authentication** (htpasswd, LDAP, etc.)
2. **Set up storage classes** for model storage
3. **Configure monitoring** and logging
4. **Set up CI/CD pipelines** for ML workflows

# Uninstall all the deployed operators
To uninstall and clean up all the operators, use the script uninstall-operators.sh
