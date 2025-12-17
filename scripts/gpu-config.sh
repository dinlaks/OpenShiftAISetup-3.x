#!/bin/sh

# Check for AWS credentials
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "AWS credentials not configured. Please run 'aws configure' and follow the prompts."
    aws configure
fi

# Get cluster region and availability zone
REGION=$(oc get nodes -o jsonpath='{.items[0].metadata.labels.topology\.kubernetes\.io/region}')
ZONE=$(oc get nodes -o jsonpath='{.items[0].metadata.labels.topology\.kubernetes\.io/zone}')

# Function to display instance type options
show_instance_types() {
    echo "Available GPU Instance Types (Region: $REGION, Zone: $ZONE):"
    echo "-------------------------------------------------------------------------------------"
    printf "%-4s %-15s %-40s %-15s\n" "ID" "Instance Type" "Description" "Spot Price"
    echo "-------------------------------------------------------------------------------------"

    declare -a prices
    print_instance_info() {
        local id=$1
        local type=$2
        local desc=$3
        local price=$(spotprice -inst $type -reg $REGION -az $ZONE | grep -o '[0-9\\.]*' | tail -n 1)
        prices[$id]=$price
        printf "%-4s %-15s %-40s \$%s/hour\n" "$id)" "$type" "$desc" "$price"
    }

    print_instance_info 1 p3.8xlarge "4 Tesla V100 GPUs, 32 vCPUs, 244 GB RAM"
    print_instance_info 2 g6e.4xlarge "1 L40s GPU, 16 vCPUs, 64 GB RAM"
    print_instance_info 3 g6e.12xlarge "4 L40s GPUs, 48 vCPUs, 192 GB RAM (default)"
    print_instance_info 4 g6.12xlarge "8 L4 GPUs, 48 vCPUs, 192 GB RAM"
    print_instance_info 5 g6e.24xlarge "4 L40s GPUs, 96 vCPUs, 384 GB RAM"
    print_instance_info 6 g6e.48xlarge "8 L40s GPUs, 192 vCPUs, 768 GB RAM"
    print_instance_info 7 p4d.24xlarge "8 A100 GPUs (40GB each), 96 vCPUs, 1152 GB RAM"
    echo "-------------------------------------------------------------------------------------"

    # Find the cheapest instance
    local cheapest_id=0
    local cheapest_price=""

    # Find the first available price to initialize
    for i in 1 2 3 4 5 6 7; do
        if [ -n "${prices[$i]}" ]; then
            cheapest_id=$i
            cheapest_price=${prices[$i]}
            break
        fi
    done

    # If we found a price, loop through the rest to find the cheapest
    if [ "$cheapest_id" -ne 0 ]; then
        i=$(expr $cheapest_id + 1)
        while [ $i -le 7 ]; do
            if [ -n "${prices[$i]}" ] && [ "$(echo "${prices[$i]} < $cheapest_price" | bc)" = "1" ]; then
                cheapest_price=${prices[$i]}
                cheapest_id=$i
            fi
            i=$(expr $i + 1)
        done
        echo "Suggestion: The cheapest instance is #$cheapest_id at \$${prices[$cheapest_id]}/hour."
    else
        echo "Suggestion: No spot prices available for any instance type."
    fi
    echo ""
}

# Function to get instance type based on selection
get_instance_type() {
    case $1 in
        1) echo "p3.8xlarge" ;;
        2) echo "g6e.4xlarge" ;;
        3) echo "g6e.12xlarge" ;;
        4) echo "g6.12xlarge" ;;
        5) echo "g6e.24xlarge" ;;
        6) echo "g6e.48xlarge" ;;
        7) echo "p4d.24xlarge" ;;
        *) echo "g6e.12xlarge" ;; # default
    esac
}

# Function to get GPU description for naming
get_gpu_description() {
    case $1 in
        1) echo "v100" ;;
        2) echo "l40s" ;;
        3) echo "l40s" ;;
        4) echo "l4" ;;
        5) echo "l40s" ;;
        6) echo "l40s" ;;
        7) echo "a100" ;;
        *) echo "l40s" ;; # default
    esac
}

# Function to get storage size based on instance type
get_storage_size() {
    case $1 in
        1|2|3|4) echo "500" ;;
        5|6|7) echo "1000" ;;
        *) echo "500" ;; # default
    esac
}

# Check if instance type is provided as argument
if [ "$1" != "" ]; then
    CHOICE=$1
else
    # Interactive mode
    show_instance_types
    echo -n "Select instance type (1-7) [3]: "
    read CHOICE
    if [ "$CHOICE" = "" ]; then
        CHOICE=3
    fi
fi

# Validate choice
if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt 7 ]; then
    echo "Invalid choice. Using default (g6e.12xlarge)"
    CHOICE=3
fi

SELECTED_INSTANCE_TYPE=$(get_instance_type $CHOICE)
GPU_DESC=$(get_gpu_description $CHOICE)
STORAGE_SIZE=$(get_storage_size $CHOICE)

echo "Selected instance type: $SELECTED_INSTANCE_TYPE"
echo "GPU description: $GPU_DESC"
echo "Storage size: ${STORAGE_SIZE}GB"
echo ""

# Get the base machineset name
MS_NAME=$(oc get machinesets -n openshift-machine-api | grep '1a\|1b\|1c\|2a\|2b\|2c' | head -n1 | awk '{print $1}')

# GPU MS name with dynamic GPU description
MS_NAME_GPU="${MS_NAME}-gpu-${GPU_DESC}"

# Extract current machineset
echo "Extracting current machineset configuration..."
oc get machineset $MS_NAME -n openshift-machine-api -o yaml > gpu-ms.yaml

# Get Current Instance Type
INSTANCE_TYPE=$(yq eval '.spec.template.spec.providerSpec.value.instanceType' gpu-ms.yaml)

echo "Current instance type: $INSTANCE_TYPE"
echo "Changing to: $SELECTED_INSTANCE_TYPE"

# Change the name of MS
sed -i .bak "s/${MS_NAME}/${MS_NAME_GPU}/g" gpu-ms.yaml

# Change instance type to selected GPU instance
sed -i .bak "s/${INSTANCE_TYPE}/${SELECTED_INSTANCE_TYPE}/g" gpu-ms.yaml

# Increase the instance volume based on instance type
sed -i .bak "s/volumeSize: 100/volumeSize: ${STORAGE_SIZE}/g" gpu-ms.yaml

# Set Replica as 1
sed -i .bak "s/replicas: 0/replicas: 1/g" gpu-ms.yaml

echo "Configuration updated successfully!"
echo "Machine set name: $MS_NAME_GPU"
echo "Instance type: $SELECTED_INSTANCE_TYPE"
echo "Storage size: ${STORAGE_SIZE}GB"
echo ""
echo "To create the machine set, run:"
echo "oc create -f gpu-ms.yaml"
echo ""
echo "To check machine status, run:"
echo "oc get machine -n openshift-machine-api"
