#!/bin/bash

# On MacOS the following utilities are needed.
# brew install --with-default-names jq gnu-sed coreutils
# BOXES=(`find output -type f -name "*.box"`)
# parallel -j 4 --xapply res/scripts/silent.sh {1} ::: "${BOXES[@]}"

# Handle self referencing, sourcing etc.
if [[ $0 != $BASH_SOURCE ]]; then
  export CMD=$BASH_SOURCE
else
  export CMD=$0
fi

# Ensure a consistent working directory so relative paths work.
pushd `dirname $CMD` > /dev/null
BASE=`pwd -P`
popd > /dev/null


# This logic allows us to force colorized output regardless of what 
# TERM and/or tput indicate. Activate forced color mode if COLORTERM is set 
# to any value, or if USE_ANSI_COLORS is set to 1, yes, or simply y. 
if [ test -t 1 ]; then 
  test -n "${COLORTERM+set}" && : ${USE_ANSI_COLORS="1"}
  case "$USE_ANSI_COLORS" in
    y|yes|Y|YES) USE_ANSI_COLORS=1 ;;
  esac
  
  # Use ANSI escape sequences.
  if test 1 = "$USE_ANSI_COLORS"; then
    tc_reset='\e[0;0m'
    
    tc_black='\e[0;30m'
    tc_red='\e[0;31m'
    tc_green='\e[0;32m'
    tc_yellow='\e[0;33m'
    tc_blue='\e[0;34m'
    tc_magenta='\e[0;35m'
    tc_cyan='\e[0;36m'
    tc_white='\e[0;37m'
    
    
    tc_black='\e[0;30m'
    tc_red='\e[0;31m'
    tc_green='\e[0;32m'
    tc_yellow='\e[0;33m'
    tc_blue='\e[0;34m'
    tc_magenta='\e[0;35m'
    tc_cyan='\e[0;36m'
    tc_white='\e[0;37m'
    
    
    tc_bold='\e[0;1m'
    tc_underline='\e[0;4m'

    tc_standout='\e[0;7m'
    
  # Fall back to letting tput decide.
  else
    test -n "`tput sgr0 2>/dev/null`" && {
      tc_reset=`tput sgr0`
      test -n "`tput bold 2>/dev/null`" && tc_bold=`tput bold`
      tc_standout=$tc_bold
      test -n "`tput smso 2>/dev/null`" && tc_standout=`tput smso`
      test -n "`tput setaf 1 2>/dev/null`" && tc_red=`tput setaf 1`
      test -n "`tput setaf 2 2>/dev/null`" && tc_green=`tput setaf 2`
      test -n "`tput setaf 4 2>/dev/null`" && tc_blue=`tput setaf 4`
      test -n "`tput setaf 5 2>/dev/null`" && tc_cyan=`tput setaf 5`
    }
  fi
  
fi



if [ $# != 1 ] && [ $# != 2 ]; then
  tput setaf 1; printf "\n\n  Usage:\n    $0 FILENAME\n\n\n"; tput sgr0
  exit 1
fi

# Make sure the recursion level is numeric.
if [ $# == 2 ] && [ -z "${2##*[!0-9]*}" ]; then
	tput setaf 1; printf "\n\nInvalid recursion level. Exiting instead.\n"; tput sgr0
	exit 1
fi

# Make sure the file exists.
if [ ! -f "$1" ]; then
  tput setaf 1; printf "\n\nThe $1 file does not exist. Exiting.\n\n\n"; tput sgr0
  exit 1
fi

# If a second variable is provided then check to ensure we haven't hit the recursion limit.
if [ $# == 2 ] && [ "$2" -gt "10" ]; then
  tput setaf 1; printf "\n\nThe recursion level has been reached. Exiting.\n\n\n"; tput sgr0
  exit 1
# Otherwise increment the level.
elif [ $# == 2 ]; then
  export RECURSION=$(($2+1))
# If no level is provided set an initial level of 0.
else
  export RECURSION=1
fi

if [ -f /opt/vagrant/embedded/lib64/libssl.so ] && [ -z LD_PRELOAD ]; then
  export LD_PRELOAD="/opt/vagrant/embedded/lib64/libssl.so"
elif [ -f /opt/vagrant/embedded/lib64/libssl.so ]; then
  export LD_PRELOAD="/opt/vagrant/embedded/lib64/libssl.so:$LD_PRELOAD"
fi

if [ -f /opt/vagrant/embedded/lib64/libcrypto.so ] && [ -z LD_PRELOAD ]; then
  export LD_PRELOAD="/opt/vagrant/embedded/lib64/libcrypto.so"
elif [ -f /opt/vagrant/embedded/lib64/libcrypto.so ]; then
  export LD_PRELOAD="/opt/vagrant/embedded/lib64/libcrypto.so:$LD_PRELOAD"
fi

export LD_LIBRARY_PATH="/opt/vagrant/embedded/bin/lib/:/opt/vagrant/embedded/lib64/"

if [[ `uname` == "Darwin" ]]; then
  export CURL_CA_BUNDLE=/opt/vagrant/embedded/cacert.pem
fi

# The jq tool is needed to parse JSON responses.
if [ ! -f /usr/bin/jq ] && [ ! -f /usr/local/bin/jq ]; then
  tput setaf 1; printf "\n\nThe 'jq' utility is not installed.\n\n\n"; tput sgr0
  exit 1
fi

# Ensure the credentials file is available.
if [ -f $BASE/../../.credentialsrc ]; then
  source $BASE/../../.credentialsrc
else
  tput setaf 1; printf "\nError. The credentials file is missing.\n\n"; tput sgr0
  exit 2
fi

if [ -z ${VAGRANT_CLOUD_TOKEN} ]; then
  tput setaf 1; printf "\nError. The vagrant cloud token is missing. Add it to the credentials file.\n\n"; tput sgr0
  exit 2
fi


# See if the log directory exists, if not create it.
if [ ! -d "$BASE/../../logs/" ]; then
  mkdir -p "$BASE/../../logs/" || mkdir "$BASE/../../logs"
fi

export UPLOAD_STD_LOGFILE="$BASE/../../logs/direct.txt"
export UPLOAD_ERR_LOGFILE="$BASE/../../logs/direct.errors.txt"

if [ -f /opt/vagrant/embedded/bin/curl ]; then
  export CURL="/opt/vagrant/embedded/bin/curl"
else
  export CURL="curl"
fi

FILENAME=`basename "$1"`
FILEPATH=`realpath "$1"`

ORG=`echo "$FILENAME" | sed "s/\([a-z]*\)[\-]*\([a-z0-9-]*\)-\(hyperv\|vmware\|libvirt\|docker\|parallels\|virtualbox\)-\([0-9\.]*\).box/\1/g"`
BOX=`echo "$FILENAME" | sed "s/\([a-z]*\)[-]*\([a-z0-9-]*\)-\(hyperv\|vmware\|libvirt\|docker\|parallels\|virtualbox\)-\([0-9\.]*\).box/\2/g"`
PROVIDER=`echo "$FILENAME" | sed "s/\([a-z]*\)[-]*\([a-z0-9-]*\)-\(hyperv\|vmware\|libvirt\|docker\|parallels\|virtualbox\)-\([0-9\.]*\).box/\3/g"`
VERSION=`echo "$FILENAME" | sed "s/\([a-z]*\)[-]*\([a-z0-9-]*\)-\(hyperv\|vmware\|libvirt\|docker\|parallels\|virtualbox\)-\([0-9\.]*\).box/\4/g"`

# Handle the Lavabit boxes.
if [ "$ORG" == "magma" ]; then
  ORG="lavabit"
  if [ "$BOX" == "" ]; then
    BOX="magma"
  else
    BOX="magma-$BOX"
  fi

  # Specialized magma box name mappings.
  [ "$BOX" == "magma-alpine36" ] && BOX="magma-alpine"
  [ "$BOX" == "magma-debian8" ] && BOX="magma-debian"
  [ "$BOX" == "magma-fedora27" ] && BOX="magma-fedora"
  [ "$BOX" == "magma-freebsd11" ] && BOX="magma-freebsd"
  [ "$BOX" == "magma-openbsd6" ] && BOX="magma-openbsd"

fi

# Handle the Lineage boxes.
if [ "$ORG" == "lineage" ] || [ "$ORG" == "lineageos" ]; then
  if [ "$BOX" == "" ]; then
    BOX="lineage"
  else
    BOX="lineage-$BOX"
  fi
fi

# Handle the Vmware provider type.
if [ "$PROVIDER" == "vmware" ]; then
  PROVIDER="vmware_desktop"
fi

# Modify the org/box for 32 bit variants.
if [[ "$BOX" =~ ^.*-x32$ ]]; then
  ORG="${ORG}-x32"
  BOX="`echo $BOX | sed s/-x32//g`"
fi

# Find the box checksum.
if [ -f $FILEPATH.sha256 ]; then

  # Read the hash in from the checksum file.
  HASH="`cat $FILEPATH.sha256 | tail -1 | awk -F' ' '{print $1}'`"

else

  # Generate a hash using the box file.
  HASH="`sha256sum $FILEPATH | awk -F' ' '{print $1}'`"

fi

# Verify the values have been parsed properly.
if [ "$ORG" == "" ]; then
  tput setaf 1; printf "\n\nThe organization couldn't be parsed from the file name.\n\n\n"; tput sgr0
  exit 1
fi

if [ "$BOX" == "" ]; then
  tput setaf 1; printf "\n\nThe box name couldn't be parsed from the file name.\n\n\n"; tput sgr0
  exit 1
fi

if [ "$PROVIDER" == "" ]; then
  tput setaf 1; printf "\n\nThe provider couldn't be parsed from the file name.\n\n\n"; tput sgr0
  exit 1
fi

if [ "$VERSION" == "" ]; then
  tput setaf 1; printf "\n\nThe version couldn't be parsed from the file name.\n\n\n"; tput sgr0
  exit 1
fi

# Generate a hash using the box file if value is invalid.
if [ "$HASH" == "" ] || [ `echo "$HASH" | wc -c` != 65 ]; then
  HASH="`sha256sum $FILEPATH | awk -F' ' '{print $1}'`"
fi

# If the hash is still invalid, then we report an error and exit.
if [ `echo "$HASH" | wc -c` != 65 ]; then
  tput setaf 1; printf "\n\nThe hash couldn't be calculated properly.\n\n\n"; tput sgr0
  exit 1
fi

retry() {
  local COUNT=1
  local RESULT=0
  while [[ "${COUNT}" -le 10 ]]; do
    [[ "${RESULT}" -ne 0 ]] && {
      echo ""
      echo -e "$(tput setaf 1)${*} failed... retrying ${COUNT} of 10.$(tput sgr0)" | tr -d \\n >&2
      echo ""
    }
    "${@}" && { RESULT=0 && break; } || RESULT="${?}"
    COUNT="$((COUNT + 1))"

    # Increase the delay with each iteration.
    DELAY="$((DELAY + 10))"
    sleep $DELAY
  done

  [[ "${COUNT}" -gt 10 ]] && {
    echo -e "\\n$(tput setaf 1)The command failed 10 times.$(tput sgr0)\\n" >&2
  }

  return "${RESULT}"
}

(${CURL} \
  --tlsv1.2 \
  --silent \
  --retry 16 \
  --retry-delay 60 \
  --output /dev/null \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
  "https://app.vagrantup.com/api/v1/box/$ORG/$BOX/versions" \
  --data "
    {
      \"version\": {
        \"version\": \"$VERSION\",
        \"description\": \"A build environment for use in cross platform development.\"
      }
    }
  ") || (tput setaf 1; printf "Version creation failed. { $ORG $BOX $PROVIDER $VERSION }\n"; tput sgr0; exit)


(${CURL} \
  --silent \
  --retry 16 \
  --retry-delay 60 \
  --output /dev/null \
  --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
  --request DELETE \
  https://app.vagrantup.com/api/v1/box/$ORG/$BOX/version/$VERSION/provider/${PROVIDER} )\
  || (tput setaf 1; printf "Unable to delete an existing version of the box. { $ORG $BOX $PROVIDER $VERSION }\n"; tput sgr0)

# Sleep to let the deletion propagate.
sleep 1

(${CURL} \
  --tlsv1.2 \
  --silent \
  --retry 16 \
  --retry-delay 60 \
  --output /dev/null \
  --header "Content-Type: application/json" \
  --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
  https://app.vagrantup.com/api/v1/box/$ORG/$BOX/version/$VERSION/providers \
  --data "{ \"provider\": { \"name\": \"$PROVIDER\", \"checksum\": \"$HASH\", \"checksum_type\": \"SHA256\" } }" )\
  || (tput setaf 1; printf "Unable to create a provider for this box version. { $ORG $BOX $PROVIDER $VERSION }\n"; tput sgr0; exit)

UPLOAD_RESPONSE=`${CURL} \
  --tlsv1.2 \
  --silent \
  --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
  https://app.vagrantup.com/api/v1/box/$ORG/$BOX/version/$VERSION/provider/$PROVIDER/upload/direct`

UPLOAD_PATH="`echo $UPLOAD_RESPONSE | jq -r .upload_path`"
UPLOAD_CALLBACK="`echo $UPLOAD_RESPONSE | jq -r .callback`"

if [ "$UPLOAD_PATH" == "" ] || [ "$UPLOAD_PATH" == "echo" ] || [ "$UPLOAD_CALLBACK" == "" ] || [ "$UPLOAD_CALLBACK" == "echo" ]; then
  printf "\n\n$FILENAME failed to upload...\n\n"
  exit 1
fi

retry ${CURL} --tlsv1.2 \
  --fail \
  --silent \
  --show-error \
  --request PUT \
  --max-time 7200 \
  --expect100-timeout 7200 \
  --header "Connection: keep-alive" \
  --write-out "FILE: $FILENAME\nCODE: %{http_code}\nIP: %{remote_ip}\nBYTES: %{size_upload}\nRATE: %{speed_upload}\nTOTAL TIME: %{time_total}\n\n" \
  --upload-file "$FILEPATH" "$UPLOAD_PATH"

# Submit the callback five times, to reduce the number of boxes without valid download URLs. Delay 1 second between each attempt.
sleep 1
${CURL} --tlsv1.2 \
    --silent \
    --output "/dev/null" \
    --show-error \
    --request PUT \
    --max-time 7200 \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    "$UPLOAD_CALLBACK"

sleep 1
${CURL} --tlsv1.2 \
    --silent \
    --output "/dev/null" \
    --show-error \
    --request PUT \
    --max-time 7200 \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    "$UPLOAD_CALLBACK"

sleep 1
${CURL} --tlsv1.2 \
    --silent \
    --output "/dev/null" \
    --show-error \
    --request PUT \
    --max-time 7200 \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    "$UPLOAD_CALLBACK"

sleep 1
${CURL} --tlsv1.2 \
    --silent \
    --output "/dev/null" \
    --show-error \
    --request PUT \
    --max-time 7200 \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    "$UPLOAD_CALLBACK"

sleep 1
${CURL} --tlsv1.2 \
    --silent \
    --output "/dev/null" \
    --show-error \
    --request PUT \
    --max-time 7200 \
    --header "Authorization: Bearer $VAGRANT_CLOUD_TOKEN" \
    "$UPLOAD_CALLBACK"

# # Add a short pause, with the duration determined by the size of the file uploaded.
# PAUSE="`du -b $FILEPATH | awk -F' ' '{print $1}'`"
# bash -c "usleep $(($PAUSE/20))"
