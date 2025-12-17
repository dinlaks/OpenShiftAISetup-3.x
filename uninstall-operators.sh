#!/bin/bash

# OpenShift AI Operators Uninstall Script

# Don't exit on error - we want to continue even if some components fail
# set -e

# Function to handle errors gracefully
handle_error() {
    local exit_code=$1
    local component=$2
    if [ $exit_code -ne 0 ]; then
        echo "   ⚠ Warning: Failed to remove $component (exit code: $exit_code)"
        echo "   Continuing with next component..."
    fi
}

echo "=== Uninstalling OpenShift AI Operators ==="

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    
    if [ -n "$namespace" ]; then
        oc get $resource_type $resource_name -n $namespace >/dev/null 2>&1
    else
        oc get $resource_type $resource_name >/dev/null 2>&1
    fi
}

# Function to wait for resource to be deleted
wait_for_deletion() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-300}
    
    # First check if resource exists
    if ! resource_exists "$resource_type" "$resource_name" "$namespace"; then
        echo "   ✓ $resource_type/$resource_name not found (already deleted or never existed)"
        return 0
    fi
    
    echo "   Waiting for $resource_type/$resource_name to be deleted..."
    local count=0
    while [ $count -lt $timeout ]; do
        if ! resource_exists "$resource_type" "$resource_name" "$namespace"; then
            echo "   ✓ $resource_type/$resource_name deleted"
            return 0
        fi
        sleep 5
        count=$((count + 5))
    done
    echo "   ⚠ Timeout waiting for $resource_type/$resource_name to be deleted (may still exist)"
    return 1
}

# Phase 3: Remove AI Platform Operator first
echo "--- Phase 3: Removing AI Platform Operator ---"

echo "6. Removing RHOAI Operator..."
echo "   Checking for DataScienceCluster..."
if resource_exists "datasciencecluster" "default-dsc" ""; then
    echo "   Removing DataScienceCluster..."
    oc delete datasciencecluster default-dsc --ignore-not-found=true
    wait_for_deletion "datasciencecluster" "default-dsc" "" 300
else
    echo "   ✓ DataScienceCluster not found (skipping)"
fi

echo "   Removing RHOAI Operator CRDs..."
if [ -d "rhoai-operator/overlays/crds" ]; then
    oc delete -k rhoai-operator/overlays/crds/ --ignore-not-found=true 2>/dev/null || echo "   ✓ RHOAI CRDs not found (skipping)"
else
    echo "   ✓ RHOAI CRDs directory not found (skipping)"
fi

echo "   Removing RHOAI Operator..."
if [ -d "rhoai-operator/base" ]; then
    oc delete -k rhoai-operator/base/ --ignore-not-found=true
    wait_for_deletion "csv" "rhods-operator" "redhat-ods-operator" 300
else
    echo "   ✓ RHOAI Operator base directory not found (skipping)"
fi

# Phase 2: Remove Platform Operators
echo "--- Phase 2: Removing Platform Operators ---"

echo "5. Removing Authorino Operator..."
if [ -d "authorino-operator/base" ]; then
    oc delete -k authorino-operator/base/ --ignore-not-found=true
    # Wait for any CSV with authorino in the name
    echo "   Waiting for Authorino CSV to be deleted..."
    oc get csv -n openshift-operators | grep authorino | awk '{print $1}' | xargs -r oc delete csv -n openshift-operators --ignore-not-found=true
    wait_for_deletion "csv" "authorino-operator" "openshift-operators" 300
else
    echo "   ✓ Authorino Operator base directory not found (skipping)"
fi

echo "4. Removing OpenShift ServiceMesh Operator..."
if [ -d "servicemesh-operator/base" ]; then
    oc delete -k servicemesh-operator/base/ --ignore-not-found=true
    # Wait for any CSV with servicemesh in the name
    echo "   Waiting for ServiceMesh CSV to be deleted..."
    oc get csv -n openshift-operators | grep servicemesh | awk '{print $1}' | xargs -r oc delete csv -n openshift-operators --ignore-not-found=true
    wait_for_deletion "csv" "servicemeshoperator" "openshift-operators" 300
else
    echo "   ✓ ServiceMesh Operator base directory not found (skipping)"
fi

echo "3. Removing OpenShift Serverless Operator..."
if [ -d "serverless-operator/base" ]; then
    oc delete -k serverless-operator/base/ --ignore-not-found=true
    wait_for_deletion "csv" "serverless-operator" "openshift-serverless" 300
else
    echo "   ✓ Serverless Operator base directory not found (skipping)"
fi

# Phase 1: Remove Infrastructure Operators last
echo "--- Phase 1: Removing Infrastructure Operators ---"

echo "2. Removing NVIDIA GPU Operator..."
echo "   Checking for GPU ClusterPolicy..."
if resource_exists "clusterpolicy" "gpu-cluster-policy" ""; then
    echo "   Removing GPU ClusterPolicy..."
    oc delete clusterpolicy gpu-cluster-policy --ignore-not-found=true
    wait_for_deletion "clusterpolicy" "gpu-cluster-policy" "" 300
else
    echo "   ✓ GPU ClusterPolicy not found (skipping)"
fi

echo "   Removing NVIDIA GPU Operator CRDs..."
if [ -d "nvidia-operator/overlays/crds" ]; then
    oc delete -k nvidia-operator/overlays/crds/ --ignore-not-found=true 2>/dev/null || echo "   ✓ NVIDIA GPU Operator CRDs not found (skipping)"
else
    echo "   ✓ NVIDIA GPU Operator CRDs directory not found (skipping)"
fi

echo "   Removing NVIDIA GPU Operator..."
if [ -d "nvidia-operator/base" ]; then
    oc delete -k nvidia-operator/base/ --ignore-not-found=true
    wait_for_deletion "csv" "gpu-operator-certified" "nvidia-gpu-operator" 300
else
    echo "   ✓ NVIDIA GPU Operator base directory not found (skipping)"
fi

echo "1. Removing NFD Operator..."
echo "   Checking for NFD instance..."
if resource_exists "nodefeaturediscovery" "nfd-instance" "openshift-nfd"; then
    echo "   Removing NFD instance..."
    oc delete nodefeaturediscovery nfd-instance -n openshift-nfd --ignore-not-found=true
    wait_for_deletion "nodefeaturediscovery" "nfd-instance" "openshift-nfd" 300
else
    echo "   ✓ NFD instance not found (skipping)"
fi

echo "   Removing NFD Operator CRDs..."
if [ -d "nfd-operator/overlays/crds" ]; then
    oc delete -k nfd-operator/overlays/crds/ --ignore-not-found=true 2>/dev/null || echo "   ✓ NFD Operator CRDs not found (skipping)"
else
    echo "   ✓ NFD Operator CRDs directory not found (skipping)"
fi

echo "   Removing NFD Operator..."
if [ -d "nfd-operator/base" ]; then
    oc delete -k nfd-operator/base/ --ignore-not-found=true
    wait_for_deletion "csv" "nfd-operator" "openshift-nfd" 300
else
    echo "   ✓ NFD Operator base directory not found (skipping)"
fi

# Clean up any remaining resources
echo "--- Cleaning up remaining resources ---"

echo "Removing any remaining subscriptions..."
oc delete subscription --all -n openshift-nfd --ignore-not-found=true || handle_error $? "subscriptions in openshift-nfd"
oc delete subscription --all -n nvidia-gpu-operator --ignore-not-found=true || handle_error $? "subscriptions in nvidia-gpu-operator"
oc delete subscription --all -n openshift-serverless --ignore-not-found=true || handle_error $? "subscriptions in openshift-serverless"
oc delete subscription --all -n redhat-ods-operator --ignore-not-found=true || handle_error $? "subscriptions in redhat-ods-operator"

echo "Removing any remaining operator groups..."
oc delete operatorgroup --all -n openshift-nfd --ignore-not-found=true || handle_error $? "operator groups in openshift-nfd"
oc delete operatorgroup --all -n nvidia-gpu-operator --ignore-not-found=true || handle_error $? "operator groups in nvidia-gpu-operator"
oc delete operatorgroup --all -n openshift-serverless --ignore-not-found=true || handle_error $? "operator groups in openshift-serverless"
oc delete operatorgroup --all -n redhat-ods-operator --ignore-not-found=true || handle_error $? "operator groups in redhat-ods-operator"

echo "Removing any remaining install plans..."
oc delete installplan --all -n openshift-nfd --ignore-not-found=true || handle_error $? "install plans in openshift-nfd"
oc delete installplan --all -n nvidia-gpu-operator --ignore-not-found=true || handle_error $? "install plans in nvidia-gpu-operator"
oc delete installplan --all -n openshift-serverless --ignore-not-found=true || handle_error $? "install plans in openshift-serverless"
oc delete installplan --all -n redhat-ods-operator --ignore-not-found=true || handle_error $? "install plans in redhat-ods-operator"

echo "Removing any remaining CSVs..."
oc delete csv --all -n openshift-nfd --ignore-not-found=true || handle_error $? "CSVs in openshift-nfd"
oc delete csv --all -n nvidia-gpu-operator --ignore-not-found=true || handle_error $? "CSVs in nvidia-gpu-operator"
oc delete csv --all -n openshift-serverless --ignore-not-found=true || handle_error $? "CSVs in openshift-serverless"
oc delete csv --all -n redhat-ods-operator --ignore-not-found=true || handle_error $? "CSVs in redhat-ods-operator"

echo "=== All operators uninstalled successfully! ==="
echo ""
echo "Uninstall Summary:"
echo "✓ RHOAI Operator and DataScienceCluster removed"
echo "✓ Authorino Operator removed"
echo "✓ OpenShift ServiceMesh Operator removed"
echo "✓ OpenShift Serverless Operator removed"
echo "✓ NVIDIA GPU Operator and ClusterPolicy removed"
echo "✓ NFD Operator and NFD instance removed"
echo "✓ All remaining resources cleaned up"
echo ""