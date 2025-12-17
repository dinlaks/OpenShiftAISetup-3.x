#!/bin/sh

# This script finds the current cheapest spot price for various AWS GPU instances
# based on user input for the AWS region and prepares a machineset YAML file for OpenShift.

# --- Configuration ---
NUM_GPU_OPTIONS=13 # Supports 13 GPU options
DEFAULT_CHOICE=7 # Default instance choice
DEFAULT_PROFILE="default" 
DEFAULT_REGION_PROMPT="us-east-1" # Suggest a common region

# 1. PROFILE SELECTION AND EXPORT
# ---

echo "--- AWS Profile and Region Configuration ---"

# Ask for the AWS Profile
echo -n "Enter the AWS profile name to use for Spot Price lookup (e.g., 'spot-finder') [$DEFAULT_PROFILE]: "
read USER_PROFILE_CHOICE

if [ -z "$USER_PROFILE_CHOICE" ]; then
    SPOT_PROFILE="$DEFAULT_PROFILE"
else
    SPOT_PROFILE="$USER_PROFILE_CHOICE"
fi

export AWS_PROFILE="$SPOT_PROFILE"
echo "Using AWS Profile: $AWS_PROFILE"

# Check credentials using the specified profile
if ! aws sts get-caller-identity --profile "$SPOT_PROFILE" > /dev/null 2>&1; then
    echo "Error: AWS credentials for profile '$SPOT_PROFILE' are not configured or invalid."
    exit 1
fi

# 2. TARGET REGION INPUT
# ---

# Ask the user for the target AWS region
echo -n "Enter the AWS Region for Spot Price lookup (e.g., 'us-east-2') [$DEFAULT_REGION_PROMPT]: "
read USER_REGION_CHOICE

if [ -z "$USER_REGION_CHOICE" ]; then
    TARGET_REGION="$DEFAULT_REGION_PROMPT"
else
    TARGET_REGION="$USER_REGION_CHOICE"
fi

# 3. VERIFY CLUSTER REGION VS TARGET REGION
# ---

# Get cluster region and availability zone from a running node
REGION=$(oc get nodes -o jsonpath='{.items[0].metadata.labels.topology\.kubernetes\.io/region}')
ZONE=$(oc get nodes -o jsonpath='{.items[0].metadata.labels.topology\.kubernetes\.io/zone}')

# Use the user-provided region for the lookup, but verify the cluster is nearby
if [ "$REGION" != "$TARGET_REGION" ]; then
    echo "Warning: Your OpenShift cluster is in $REGION, but the Spot Price lookup will use $TARGET_REGION."
    echo "This may cause machine set creation failures if the region is wrong."
fi

# We use TARGET_REGION for the lookup, but keep original $ZONE and $REGION for validation
LOOKUP_REGION="$TARGET_REGION"

# Function to display instance type options and find the cheapest
show_instance_types() {
    echo "Available GPU Instance Types (Lookup Region: $LOOKUP_REGION, Zone: $ZONE):"
    echo "--------------------------------------------------------------------------------------------------------------------------"
    printf "%-4s %-15s %-70s %-15s\n" "ID" "Instance Type" "Description" "Spot Price"
    echo "--------------------------------------------------------------------------------------------------------------------------"

    declare -a prices
    print_instance_info() {
        local id=$1
        local type=$2
        local desc=$3
        # Use LOOKUP_REGION for spot price command
        local price=$(spotprice -inst "$type" -reg "$LOOKUP_REGION" -az "$ZONE" | grep -o '[0-9\\.]*' | tail -n 1)
        prices[$id]=$price
        printf "%-4s %-15s %-70s \$%s/hour\n" "$id)" "$type" "$desc" "$price"
    }

    # --- EXPANDED GPU INSTANCE LIST (Ordered by general cost/power) ---
    print_instance_info 1 p4d.24xlarge    "8 A100 (40GB each), 96 vCPUs, 1152 GB RAM (High-End Training)"
    print_instance_info 2 g6e.48xlarge    "8 L40S GPUs, 192 vCPUs, 768 GB RAM (High-End Inference/Training)"
    print_instance_info 3 g6e.24xlarge    "4 L40S GPUs, 96 vCPUs, 768 GB RAM"
    print_instance_info 4 g6e.12xlarge    "4 L40S GPUs, 48 vCPUs, 384 GB RAM"
    print_instance_info 5 g6e.4xlarge     "1 L40S GPU (48GB), 16 vCPUs, 128 GB RAM"
    print_instance_info 6 g6.12xlarge     "8 L4 GPUs, 48 vCPUs, 192 GB RAM (Mid-Range Distributed)"
    print_instance_info 7 g6.8xlarge      "1 L4 GPU (24GB), 32 vCPUs, 128 GB RAM (Default Mid-Range)"
    print_instance_info 8 g5.8xlarge      "1 A10G GPU (24GB), 32 vCPUs, 128 GB RAM (Mid-Range General Purpose)"
    print_instance_info 9 p3.8xlarge      "4 V100 GPUs, 32 vCPUs, 244 GB RAM (Legacy Training)"
    print_instance_info 10 g4dn.2xlarge   "1 T4 GPU (16GB), 8 vCPUs, 32 GB RAM (Entry-Level Inference)"
    print_instance_info 11 g5.xlarge      "1 A10G GPU (24GB), 4 vCPUs, 16 GB RAM (Lowest Cost A10G)"
    print_instance_info 12 g4dn.xlarge    "1 T4 GPU (16GB), 4 vCPUs, 16 GB RAM (Lowest Cost T4)"
    print_instance_info 13 g4ad.xlarge    "1 AMD Radeon Pro V520, 4 vCPUs, 16 GB RAM (AMD Graphics Option)"
    echo "--------------------------------------------------------------------------------------------------------------------------"

    # --- Cheapest Price Calculation (Remains the same) ---
    local cheapest_id=0
    local cheapest_price=""

    for i in $(seq 1 $NUM_GPU_OPTIONS); do
        if [ -n "${prices[$i]}" ] && [ "${prices[$i]}" != "0" ]; then
            cheapest_id=$i
            cheapest_price=${prices[$i]}
            break
        fi
    done

    if [ "$cheapest_id" -ne 0 ]; then
        i=$(expr $cheapest_id + 1)
        while [ $i -le $NUM_GPU_OPTIONS ]; do
            if [ -n "${prices[$i]}" ] && [ "$(echo "${prices[$i]} < $cheapest_price" | bc)" = "1" ]; then
                cheapest_price=${prices[$i]}
                cheapest_id=$i
            fi
            i=$(expr $i + 1)
        done
        echo "Suggestion: The cheapest available instance is #$cheapest_id at \$${prices[$cheapest_id]}/hour."
    else
        echo "Suggestion: No spot prices available or instance types not currently offered in $LOOKUP_REGION/$ZONE."
    fi
    echo ""
}

# Function to get instance type based on selection
get_instance_type() {
    case $1 in
        1) echo "p4d.24xlarge" ;;
        2) echo "g6e.48xlarge" ;;
        3) echo "g6e.24xlarge" ;;
        4) echo "g6e.12xlarge" ;;
        5) echo "g6e.4xlarge" ;;
        6) echo "g6.12xlarge" ;;
        7) echo "g6.8xlarge" ;;
        8) echo "g5.8xlarge" ;;
        9) echo "p3.8xlarge" ;;
        10) echo "g4dn.2xlarge" ;;
        11) echo "g5.xlarge" ;;
        12) echo "g4dn.xlarge" ;;
        13) echo "g4ad.xlarge" ;;
        *) echo "g6.8xlarge" ;; # default
    esac
}

# Function to get GPU description for naming (used in machine set naming)
get_gpu_description() {
    case $1 in
        1) echo "a100" ;;
        2) echo "l40s" ;;
        3) echo "l40s" ;;
        4) echo "l40s" ;;
        5) echo "l40s" ;;
        6) echo "l4" ;;
        7) echo "l4" ;;
        8) echo "a10g" ;;
        9) echo "v100" ;;
        10) echo "t4" ;;
        11) echo "a10g" ;;
        12) echo "t4" ;;
        13) echo "amd" ;;
        *) echo "l4" ;; # default
    esac
}

# Function to get storage size based on instance type
get_storage_size() {
    if [ "$1" -eq 1 ]; then
        echo "1500"
    elif [ "$1" -ge 2 ] && [ "$1" -le 9 ]; then
        echo "1000"
    else
        echo "500"
    fi
}

# Check if instance type is provided as argument
if [ "$1" != "" ]; then
    CHOICE=$1
else
    # Interactive mode
    show_instance_types
    echo -n "Select instance type (1-$NUM_GPU_OPTIONS) [$DEFAULT_CHOICE]: "
    read CHOICE
    if [ "$CHOICE" = "" ]; then
        CHOICE=$DEFAULT_CHOICE
    fi
fi

# Validate choice
if [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt $NUM_GPU_OPTIONS ]; then
    echo "Invalid choice. Using default (ID $DEFAULT_CHOICE)"
    CHOICE=$DEFAULT_CHOICE
fi

SELECTED_INSTANCE_TYPE=$(get_instance_type $CHOICE)
GPU_DESC=$(get_gpu_description $CHOICE)
STORAGE_SIZE=$(get_storage_size $CHOICE)

# Define the output filename with GPU model descriptor
OUTPUT_FILENAME="gpu-ms-${GPU_DESC}.yaml"

echo "Selected instance type: $SELECTED_INSTANCE_TYPE"
echo "GPU description: $GPU_DESC"
echo "Storage size: ${STORAGE_SIZE}GB"
echo ""

# Get the base machineset name (assumes a standard worker machineset exists in the zone)
MS_NAME=$(oc get machinesets -n openshift-machine-api | grep "${ZONE}" | head -n1 | awk '{print $1}')

if [ -z "$MS_NAME" ]; then
    echo "Error: Could not find a base machineset in zone $ZONE to use as a template."
    echo "Please ensure there is a standard worker machineset available (e.g., 'aws-$REGION-a-worker')."
    exit 1
fi

# GPU MS name with dynamic GPU description
MS_NAME_GPU="${MS_NAME}-gpu-${GPU_DESC}"

echo "Using base machineset: $MS_NAME"
echo "Extracting current machineset configuration..."

# Use the new dynamic filename for extraction
oc get machineset "$MS_NAME" -n openshift-machine-api -o yaml > "$OUTPUT_FILENAME"

# Get Current Instance Type
INSTANCE_TYPE=$(yq eval '.spec.template.spec.providerSpec.value.instanceType' "$OUTPUT_FILENAME")

echo "Current instance type: $INSTANCE_TYPE"
echo "Changing to: $SELECTED_INSTANCE_TYPE"

# --- Modify the machineset YAML ---

# 1. Change the name of MS
sed -i .bak "s/${MS_NAME}/${MS_NAME_GPU}/g" "$OUTPUT_FILENAME"

# 2. Change instance type to selected GPU instance
sed -i .bak "s/${INSTANCE_TYPE}/${SELECTED_INSTANCE_TYPE}/g" "$OUTPUT_FILENAME"

# 3. Increase the instance volume based on instance type
sed -i .bak "s/volumeSize: [0-9]\{1,\}/volumeSize: ${STORAGE_SIZE}/g" "$OUTPUT_FILENAME"

# 4. Set Replica as 1
sed -i .bak "s/replicas: 0/replicas: 1/g" "$OUTPUT_FILENAME"

# 5. Remove unnecessary status/metadata fields (optional cleanup)
yq eval 'del(.metadata.creationTimestamp, .metadata.resourceVersion, .metadata.uid, .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration", .status)' -i "$OUTPUT_FILENAME"

# 6. Inject the spot market option (OpenShift Machine API uses this annotation for Spot)
yq eval '.spec.template.metadata.labels += {"machine.openshift.io/capacity-type": "spot"}' -i "$OUTPUT_FILENAME"
yq eval '.spec.template.metadata.annotations += {"machine.openshift.io/spot-max-price": ""}' -i "$OUTPUT_FILENAME"

echo "Configuration updated successfully!"
echo "Machine set name: $MS_NAME_GPU"
echo "Instance type: $SELECTED_INSTANCE_TYPE"
echo "Storage size: ${STORAGE_SIZE}GB"
echo "Spot instance flag added."
echo ""
echo "----------------------------------------------------------------------------------"
echo "To create the machine set and provision the Spot GPU node, run:"
echo "oc create -f $OUTPUT_FILENAME"
echo ""
echo "To check machine status, run:"
echo "oc get machine -n openshift-machine-api"
echo "----------------------------------------------------------------------------------"
