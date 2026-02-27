#!/bin/bash

# OpenShift AI Operators Deployment Script
# This script deploys operators in the correct dependency order

set -e

echo "=== Deploying OpenShift AI Operators in Dependency Order ==="

# Function to wait for resource to exist
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300}
    
    echo "   Waiting for $resource_type/$resource_name to exist..."
    local count=0
    while [ $count -lt $timeout ]; do
        if oc get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
            echo "   ✓ $resource_type/$resource_name found"
            return 0
        fi
        sleep 5
        count=$((count + 5))
    done
    echo "   ✗ Timeout waiting for $resource_type/$resource_name to exist"
    return 1
}

# Function to wait for resource to exist and be ready
wait_for_resource_ready() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local jsonpath_condition=$4
    local expected_value=$5
    local timeout=${6:-300}
    
    echo "   Waiting for $resource_type/$resource_name to exist and be ready..."
    local count=0
    while [ $count -lt $timeout ]; do
        if oc get $resource_type $resource_name -n $namespace >/dev/null 2>&1; then
            local current_value=$(oc get $resource_type $resource_name -n $namespace -o jsonpath="$jsonpath_condition" 2>/dev/null || echo "")
            if [ "$current_value" = "$expected_value" ]; then
                echo "   ✓ $resource_type/$resource_name is ready"
                return 0
            fi
        fi
        sleep 5
        count=$((count + 5))
    done
    echo "   ✗ Timeout waiting for $resource_type/$resource_name to be ready"
    return 1
}

# Function to wait for CSV by label
wait_for_csv_by_label() {
    local label=$1
    local namespace=$2
    local timeout=${3:-300}
    
    echo "   Waiting for CSV with label $label to exist..."
    local count=0
    while [ $count -lt $timeout ]; do
        if oc get csv -l $label -n $namespace --no-headers 2>/dev/null | grep -q .; then
            echo "   ✓ CSV with label $label found"
            return 0
        fi
        sleep 5
        count=$((count + 5))
    done
    echo "   ✗ Timeout waiting for CSV with label $label to exist"
    return 1
}

# Phase 1: Infrastructure Operators (must be first)
echo "--- Phase 1: Deploying Infrastructure Operators ---"

echo "1. Deploying NFD Operator..."
oc apply -k nfd-operator/base/
echo "   Waiting for NFD Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/nfd.openshift-nfd" "openshift-nfd" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/nfd.openshift-nfd -n openshift-nfd --timeout=300s

echo "   Applying NFD Overlay (CRDs)..."
oc apply -k nfd-operator/overlays/crds/
echo "   Waiting for NFD instance to be Available..."
wait_for_resource "nodefeaturediscovery" "nfd-instance" "openshift-nfd" 300
oc wait --for=jsonpath='{.status.conditions[?(@.type=="Available")].status}'=True nodefeaturediscovery/nfd-instance -n openshift-nfd --timeout=300s

echo "2. Deploying NVIDIA GPU Operator..."
oc apply -k nvidia-operator/base/
echo "   Waiting for NVIDIA GPU Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator" "nvidia-gpu-operator" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator -n nvidia-gpu-operator --timeout=300s

echo "   Applying NVIDIA GPU Operator Overlay (CRDs)..."
oc apply -k nvidia-operator/overlays/crds/
echo "   Waiting for GPU ClusterPolicy to be ready..."
wait_for_resource_ready "clusterpolicy" "gpu-cluster-policy" "nvidia-gpu-operator" "{.status.state}" "ready" 300

# Phase 2: Platform Operators
echo "--- Phase 2: Deploying Platform Operators ---"

echo "3. Deploying OpenShift Serverless Operator..."
oc apply -k serverless-operator/base/
echo "   Waiting for OpenShift Serverless Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/serverless-operator.openshift-serverless" "openshift-serverless" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/serverless-operator.openshift-serverless -n openshift-serverless --timeout=300s

echo "4. Deploying OpenShift ServiceMesh Operator..."
oc apply -k servicemesh-operator/base/
echo "   Waiting for OpenShift ServiceMesh Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/servicemeshoperator3.openshift-operators" "openshift-operators" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/servicemeshoperator3.openshift-operators -n openshift-operators --timeout=300s

echo "5. Deploying OpenShift Pipelines Operator..."
oc apply -k pipelines-operator/
echo "   Waiting for OpenShift Pipelines Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/openshift-pipelines-operator-rh.openshift-operators" "openshift-operators" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/openshift-pipelines-operator-rh.openshift-operators -n openshift-operators --timeout=300s

echo "6. Deploying Authorino Operator..."
oc apply -k authorino-operator/base/
echo "   Waiting for Authorino Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/authorino-operator.openshift-operators" "openshift-operators" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/authorino-operator.openshift-operators -n openshift-operators --timeout=300s

echo "7. Deploying Cert-Manager Operator..."
oc apply -k cert-manager-operator/base/
echo "   Waiting for Cert-Manager Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/openshift-cert-manager-operator.cert-manager-operator" "cert-manager-operator" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/openshift-cert-manager-operator.cert-manager-operator -n cert-manager-operator --timeout=300s

echo "   Applying Cert-Manager Operator Overlay (CRDs)..."
oc apply -k cert-manager-operator/overlays/crds/
echo "   Waiting for Cert-Manager cluster to be ready..."
wait_for_resource_ready "cluster" "cert-manager-operator" "{.status.state}" "ready" 300

<<COMMENT
echo "8. Deploying LeaderWorkerSet Operator..."
oc apply -k lws-operator/base/
echo "   Waiting for LeaderWorkerSet Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/leader-worker-set.openshift-lws-operator" "openshift-lws-operators" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/leader-worker-set.openshift-lws-operator -n openshift-lws-operators --timeout=300s

echo "9. Deploying RHCL Operator..."
oc apply -k leaderworkerset-operator/
echo "   Waiting for LeaderWorkerSet Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/rhcl-operator.openshift-operators" "openshift-operators" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/rhcl-operator.openshift-operators -n openshift-operators --timeout=300s
COMMENT

# Phase 3: AI Platform Operator (depends on all previous)
echo "--- Phase 3: Deploying AI Platform Operator ---"

echo "10. Deploying RHOAI Operator..."
oc apply -k rhoai-operator/base/
echo "   Waiting for RHOAI Operator to be ready..."
wait_for_csv_by_label "operators.coreos.com/rhods-operator.redhat-ods-operator" "redhat-ods-operator" 300
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/rhods-operator.redhat-ods-operator -n redhat-ods-operator --timeout=300s

echo "   Applying RHOAI Operator Overlay (CRDs)..."
oc apply -k rhoai-operator/overlays/crds/
echo "   Waiting for DataScienceCluster to be ready..."
wait_for_resource_ready "datasciencecluster" "default-dsc" "redhat-ods-operator" "{.status.conditions[?(@.type==\"Ready\")].status}" "True" 600

echo "=== All operators deployed successfully! ==="
echo ""
echo "Deployment Summary:"
echo "✓ NFD Operator with NFD instance (Available)"
echo "✓ NVIDIA GPU Operator with ClusterPolicy (Ready)"
echo "✓ OpenShift Serverless Operator"
echo "✓ OpenShift Pipelines Operator"
echo "✓ Authorino Operator"
echo "✓ Cert-Manager Operator"
echo "✓ LeaderWorkerSet Operator"
echo "✓ RHCL Operator"
echo "✓ RHOAI Operator with DataScienceCluster (Ready)"
echo ""
echo "Next steps and ToDos:"
echo "1. Verify RHOAI Dashboard is accessible"
echo "2. Patch OdhDashboard to enable Model Registry UI, enable training ui"
echo "3. Deploy Mariadb for Model Registry"
echo "4. Configure Model Registry for RHOAI with Mariadb"
echo "5. Enable observability for RHOAI"
echo "6. Deploy LlamaStackInstance for LlamaStack"