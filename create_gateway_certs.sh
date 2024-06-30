#!/bin/bash

set -e

# Get the current working directory
WORKINGDIR="$PWD"

# Get the current architecture
ARCH=`arch`

# Using corecell as a platform to run lorawan basicstation
PLATFORM='corecell'

# Using standard variant for Raspberry Pi running 64bit bookworm OS.
VARIANT='std'

# LoRa basicstation git repository to clone using tag
REMOTE_TAG='v2.0.6'

# Bash text color codes to highlight text
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NOCOLOR='\033[0m'

# Function to print colored text
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NOCOLOR}"
}

# Function to convert string to uppercase
to_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]' 
}

# Function to print how to use this script
usage() {
    print_color "$GREEN" "USAGE: $0 --GATEWAY_NAME=<gateway name> --GATEWAY_REGION=<AWS Region> --RF_REGION_CODE=<LoRaWAN RF Region Code [Default=US915]> --GATEWAY_DESCRIPTION=<Description for Gateway>[optional] "
    exit 1
}


# Parse arguments and set as bash variables
while [ $# -gt 0 ]; do
    case $(to_uppercase "$1") in
        --AWS_ACCESS_KEY_ID=*)
            AWS_ACCESS_KEY_ID="${1#*=}"
            ;;
        --AWS_SECRET_ACCESS_KEY=*)
            AWS_SECRET_ACCESS_KEY="${1#*=}"
            ;;
        --AWS_SESSION_TOKEN=*)
            AWS_SESSION_TOKEN="${1#*=}"
            ;;
        --GATEWAY_NAME=*)
            GATEWAY_NAME="${1#*=}"
            ;;
        --GATEWAY_REGION=*)
            GATEWAY_REGION="${1#*=}"
            ;;
        --GATEWAY_DESCRIPTION=*)
            GATEWAY_DESCRIPTION="${1#*=}"
            ;;
        --RF_REGION_CODE=*)
            RF_REGION_CODE="${1#*=}"
            ;;
        *)
            echo "Unknown parameter: $1"
            usage
            ;;
    esac
    shift
done

# Set default values for optional parameters
GATEWAY_REGION=${GATEWAY_REGION:-'us-east-1'}
export AWS_REGION=$GATEWAY_REGION
DEFAULT_GATEWAY_DESCRIPTION="LoRaWAN Gateway with Name ${GATEWAY_NAME} in ${GATEWAY_REGION}"

GATEWAY_DESCRIPTION=${GATEWAY_DESCRIPTION:-$DEFAULT_GATEWAY_DESCRIPTION}
RF_REGION_CODE=${RF_REGION_CODE:-'US915'}

if [ -z "${AWS_ACCESS_KEY_ID}" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then

    print_color "$RED" "ERROR: Set AWS credentials as environment variables or provide --AWS_ACCESS_KEY_ID, --AWS_SECRET_ACCESS_KEY and --AWS_SESSION_TOKEN input."
    exit 1

else

print_color "$BLUE" """

                Check AWS Identity
-----------------------------------------------------
"""
print_color "$GREEN" """`aws sts get-caller-identity  --output table`"""
sleep 1

fi


# Check if required parameters are set as script arguments
if [ -z "$GATEWAY_NAME" ] || [ -z "$GATEWAY_REGION" ]; then

print_color "$RED" "ERROR: Both 'GATEWAY_NAME' and 'GATEWAY_REGION' must be specified." # print error message
usage # print usage and exit

fi

# Clone sx1302_hal git repository to current working directory
print_color "$BLUE" """

            Clone lora-net/sx1302_hal 
-----------------------------------------------------

"""
print_color "$GREEN" "Clone sx1302_hal repo"
print_color "$NOCOLOR" """
git clone https://github.com/Lora-net/sx1302_hal.git sx1302_hal

"""
git clone https://github.com/Lora-net/sx1302_hal.git sx1302_hal
sleep 1


# Patch reset_lgw.sh in sx1302_hal cloned repository to use pinctrl
print_color "$BLUE" """

    Patch lora-net/sx1302_hal cloned repository:
        - use pinctrl in reset_lgw.sh
-----------------------------------------------------
"""

print_color "$NOCOLOR" """
cd '$WORKINGDIR/sx1302_hal'
git apply '${WORKINGDIR}/lora_sx1302.patch'

"""

cd "$WORKINGDIR/sx1302_hal"
git apply "$WORKINGDIR/lora_sx1302.patch"

print_color "$BLUE" """

                make install sx1302
-----------------------------------------------------
"""
print_color "$NOCOLOR" "make  > sx1302_compile.log 2>&1 && tail -n2 sx1302_compile.log "

make  > sx1302_compile.log 2>&1 && tail -n2 sx1302_compile.log 
cd tools/
GATEWAY_EUI=`../util_chip_id/chip_id|grep 'INFO: concentrator EUI:'| awk -F 'EUI: 0x' '{print $2}'`

print_color "$MAGENTA" """
    Gateway EUI: $GATEWAY_EUI
"""

sleep 2
# Clone lora/basicstation git repository to current working directory
print_color "$BLUE" """

                Clone lora/basicstation 
-----------------------------------------------------

"""
print_color "$GREEN" """

Clone basicstation repo"""
print_color "$NOCOLOR" """
cd '$WORKINGDIR'
git clone https://github.com/lorabasics/basicstation basicstation
cd basicstation
git checkout ${REMOTE_TAG}
"""

cd "$WORKINGDIR"
git clone https://github.com/lorabasics/basicstation basicstation
cd basicstation
git checkout ${REMOTE_TAG}

sleep 2

print_color "$BLUE" """

    Patch lora/basicstation cloned repository:
        - use '$ARCH' and corecell in setup.gmk
        - use pinctrl in reset_lgw.sh
-----------------------------------------------------
"""

print_color "$NOCOLOR" """
cd '$WORKINGDIR/basicstation'
git apply '$WORKINGDIR/lora_basicstation.patch'

"""

# Patch setup.gmk and reset_lgw.sh files in basicstation then build basicstation package
cd "$WORKINGDIR/basicstation"
git apply "$WORKINGDIR/lora_basicstation.patch"

print_color "$BLUE" """

            make install basicstation
-----------------------------------------------------
"""
print_color "$NOCOLOR" "make platform=${PLATFORM} variant=${VARIANT} arch=${ARCH} > basicstation_make.log 2>&1 && tail -n2 basicstation_make.log"

make platform=${PLATFORM} variant=${VARIANT} arch=${ARCH} > basicstation_make.log 2>&1 && tail -n2 basicstation_make.log

print_color "$MAGENTA" """
###################################################################################################
    Creating LoRaWAN gateway in AWS Region: $GATEWAY_REGION
        - Gateway Name : $GATEWAY_NAME
        - Gateway Description: $GATEWAY_DESCRIPTION
        - Gateway EUI: $GATEWAY_EUI
        - LoRaWAN RF Region Code: $RF_REGION_CODE
###################################################################################################
"""
sleep 2

print_color "$BLUE" """

        Create gateway certificates in a folder     
-----------------------------------------------------
"""
print_color "$GREEN" "Creating $GATEWAY_NAME in AWS Region: $GATEWAY_REGION"
if ! [ "$GATEWAY_DESCRIPTION" = '' ]; then
    print_color "$GREEN" "Gateway Description: $GATEWAY_DESCRIPTION"
fi

# Create gateway certificates in a GATEWAY_EUI folder
mkdir -p "$WORKINGDIR/$GATEWAY_EUI"
cd "$WORKINGDIR/$GATEWAY_EUI"

print_color "$BLUE" "Creating cups.uri file"
ENDPOINT=`aws iotwireless get-service-endpoint --region ${GATEWAY_REGION}|jq -r '.ServiceEndpoint'`
echo -n $ENDPOINT>cups.uri

print_color "$BLUE" "Creating cups.trust file"
aws iotwireless get-service-endpoint --region ${GATEWAY_REGION} --service-type CUPS| jq -r '.ServerTrust'>cups.trust

print_color "$BLUE" "Creating cups.crt, cups.pub and cups.key files"
export cid=`aws iot create-keys-and-certificate --region ${GATEWAY_REGION} \
--certificate-pem-outfile "cups.crt" \
--public-key-outfile "cups.pub" \
--private-key-outfile "cups.key" \
--set-as-active | jq -r '.certificateId'`

print_color "$BLUE" "Creating LoRaWAN Gateway and attaching certificate."
export gid=`aws iotwireless create-wireless-gateway \
    --lorawan GatewayEui=${GATEWAY_EUI},RfRegion=${RF_REGION_CODE} \
    --name ${GATEWAY_NAME} \
    --description "${GATEWAY_DESCRIPTION}" --region ${GATEWAY_REGION}| jq -r '.Id'`

aws iotwireless associate-wireless-gateway-with-certificate \
    --id ${gid} \
    --iot-certificate-id ${cid} \
    --region ${GATEWAY_REGION} 


print_color "$BLUE" "Copy station.conf and required shell scripts from corecell examples"
cp $WORKINGDIR/station.conf $WORKINGDIR/$GATEWAY_EUI/station.conf
cp $WORKINGDIR/basicstation/examples/corecell/*.sh $WORKINGDIR/$GATEWAY_EUI/

print_color "$BLUE" "Update GATEWAY_EUI in station.conf to ${GATEWAY_EUI}"
sed -i "s/GATEWAY_EUI/${GATEWAY_EUI}/g" station.conf

print_color "$MAGENTA" """
        Start Gateway
"""
cd $WORKINGDIR/$GATEWAY_EUI
$WORKINGDIR/basicstation/build-corecell-std/bin/station -h $WORKINGDIR/$GATEWAY_EUI -d -L station.log


# cd "$WORKINGDIR"
# rm -rf basicstation/ sx1302_hal/