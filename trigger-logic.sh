#! /bin/bash
# Jenkins build trigger for external release changes and package difference

#################################
## Current Build trigger types ##
#################################
# alpine_package - an array of alpine packages is passed and all their versions are taken from head an md5 is generated to tag their version
# ubuntu_package - an array of alpine packages is passed and all their versions are taken from head an md5 is generated to tag their version
# deb_repo - One or more external repos is used to check an array of packages versions and generate an md5 hash
# alpine_repo - One external repo is used to check an array of packages versions and generate an md5 hash
# external_blob - An external file blob is downloaded and an md5 is generated to determine the external version

################
# Set Varibles #
################

# Set Parameters
for i in "$@"
do
case $i in
  -TRIGGER_TYPE=*)
  TRIGGER_TYPE="${i#*=}"
  shift
  ;;
  -LS_USER=*)
  LS_USER="${i#*=}"
  shift
  ;;
  -LS_REPO=*)
  LS_REPO="${i#*=}"
  shift
  ;;
  -LS_BRANCH=*)
  LS_BRANCH="${i#*=}"
  shift
  ;;
  -LS_RELEASE_TYPE=*)
  LS_RELEASE_TYPE="${i#*=}"
  shift
  ;;
  -EXT_BLOB=*)
  EXT_BLOB="${i#*=}"
  shift
  ;;
  -BUILDS_DISCORD=*)
  BUILDS_DISCORD="${i#*=}"
  shift
  ;;
  -JENKINS_USER=*)
  JENKINS_USER="${i#*=}"
  shift
  ;;
  -JENKINS_API_KEY=*)
  JENKINS_API_KEY="${i#*=}"
  shift
  ;;
  -VEYOR_VARS=*)
  VEYOR_VARS="${i#*=}"
  shift
  ;;
esac
done

# Get the current release info
if [ "${LS_RELEASE_TYPE}" == "stable" ]; then
  LS_RELEASE=$(curl -s https://api.github.com/repos/${LS_USER}/${LS_REPO}/releases/latest | jq -r '. | .name')
  EXTERNAL_TAG=$(echo ${LS_RELEASE} | awk -F'-pkg-' '{print $1}')
  PACKAGE_TAG=$(echo ${LS_RELEASE} | grep -o -P '(?<=-pkg-).*(?=-ls)')
  LS_VERSION=$(echo ${LS_RELEASE} | sed 's/^.*-ls//g')
elif [ "${LS_RELEASE_TYPE}" == "prerelease" ]; then 
  LS_RELEASE=$(curl -s https://api.github.com/repos/${LS_USER}/${LS_REPO}/releases | jq -r 'first(.[] | select(.prerelease == true)) | .tag_name')
  EXTERNAL_TAG=$(echo ${LS_RELEASE} | awk -F'-pkg-' '{print $1}')
  PACKAGE_TAG=$(echo ${LS_RELEASE} | grep -o -P '(?<=-pkg-).*(?=-ls)')
  LS_VERSION=$(echo ${LS_RELEASE} | sed 's/^.*-ls//g')
fi

#############
# Functions #
#############

# Send a message explaining the build trigger and reason to discord
function tell_discord {
  curl -X POST --data '{"avatar_url": "https://wiki.jenkins-ci.org/download/attachments/2916393/headshot.png","embeds": [{"color": 9802903,
                        "description": "**Build Triggered** \n**Reason:**: '"${TRIGGER_REASON}"' \n"}],
                        "username": "Jenkins"}' ${BUILDS_DISCORD}
}

function tell_discord_fail {
  curl -X POST --data '{"avatar_url": "https://wiki.jenkins-ci.org/download/attachments/2916393/headshot.png","embeds": [{"color": 16711680,
                        "description": "**Trigger Failed** \n**Reason:**: '"${FAILURE_REASON}"' \n"}],
                        "username": "Jenkins"}' ${BUILDS_DISCORD}
}

# Trigger the build for this triggers job
function trigger_build {
  curl -X POST \
      https://ci.linuxserver.io/job/Docker-Pipeline-Builders/job/${LS_REPO}/job/${LS_BRANCH}/buildWithParameters?PACKAGE_CHECK=false \
      --user ${JENKINS_USER}:${JENKINS_API_KEY}
  tell_discord
}

######################################
# External Software Release Triggers #
######################################

# This is an external file blob release
if [ "${TRIGGER_TYPE}" == "external_blob" ]; then
  echo "This is an External file blob package trigger"
  # Determine the current md5 for the file blob
    # Make sure the remote file returns a 200 status or fail
    if [ $(curl -I -sL -w "%{http_code}" "${EXT_BLOB}" -o /dev/null) == 200 ]; then
      CURRENT_MD5=$(curl -s -L "${EXT_BLOB}" | md5sum | cut -c1-8)
    else
      FAILURE_REASON='Unable to get the URL:'"${EXT_BLOB}"' for '"${LS_REPO}"' make sure URLs used to trigger are up to date'
      tell_discord_fail
      exit 0
    fi
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_MD5}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current:${CURRENT_MD5}"
    TRIGGER_REASON='An external file change was detected for '"${LS_REPO}"' at the URL:'"${EXT_BLOB}"' old md5:'"${EXTERNAL_TAG}"' new md5:'"${CURRENT_MD5}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

# This is a appveyor trigger
if [ "${TRIGGER_TYPE}" == "appveyor" ]; then
  echo "This is an appveyor trigger"
  # Determine the current version from appveyor
  PROJECT_USER="$(echo "${VEYOR_VARS}" | cut -d'|' -f1)"
  PROJECT_NAME="$(echo "${VEYOR_VARS}" | cut -d'|' -f2)"
  PROJECT_FILE="$(echo "${VEYOR_VARS}" | cut -d'|' -f3)"
  PROJECT_BRANCH="$(echo "${VEYOR_VARS}" | cut -d'|' -f4)"
  FULL_URL="https://ci.appveyor.com/api/projects/${PROJECT_USER}/${PROJECT_NAME}/artifacts/${PROJECT_FILE}?branch=${PROJECT_BRANCH}&pr=false"
    # Make sure appveyor returns a 404
    RESP=$(curl -Ls -w "%{http_code}" -o /dev/null "${FULL_URL}")
    if [ ${RESP} == 404 ]; then
      CURRENT_TAG=$(curl -Ls -w %{url_effective} -o /dev/null "${FULL_URL}" | awk -F / '{print $6}' | sed 's/-/./g')
    else
      FAILURE_REASON='Unable to get the URL:'"${FULL_URL}"' for '"${LS_REPO}"' make sure URLs used to trigger are up to date'
      tell_discord_fail
      exit 0
    fi
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_TAG}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current: ${CURRENT_TAG}"
    TRIGGER_REASON='An version change was detected for '"${LS_REPO}"' at the URL:'"${FULL_URL}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

