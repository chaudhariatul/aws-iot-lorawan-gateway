#!/bin/bash

GWSETUPDIR=${PWD}

REMOTE_TAG='v2.0.6'
ARCH=`arch`
PLATFORM='corecell'
VARIANT='std'


git clone https://github.com/Lora-net/sx1302_hal.git
cd sx1302_hal
make
cd tools
patch reset_lgw.sh -i ${GWSETUPDIR}/reset_lgw.patch -o reset_lgw.sh

GATEWAY_EUI=`../util_chip_id/chip_id|grep 'INFO: concentrator EUI:'| awk -F 'EUI: 0x' '{print $2}'`
