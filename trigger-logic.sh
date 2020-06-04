#! /bin/bash
# Jenkins build trigger for external release changes and package difference

#################################
## Current Build trigger types ##
#################################
# external_blob - An external file blob is downloaded and an md5 is generated to determine the external version
# appveyor - A mostly custom curl command to get a redirect URL and parse it from appveyor
# custom_jq - When you need to perform advanced jq operations for an external API response
# deb_package - When you need to pull a version of a package from a debian style repo endpoint
# full_custom - Raw bash exec of a command for corner cases and extreme versioning

#################
# Set Variables #
#################

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
  -JQ_URL=*)
  JQ_URL="${i#*=}"
  shift
  ;;
  -JQ_LOGIC=*)
  JQ_LOGIC="${i#*=}"
  shift
  ;;
  -DEB_PACKAGES_URL=*)
  DEB_PACKAGES_URL="${i#*=}"
  shift
  ;;
  -DEB_PACKAGE=*)
  DEB_PACKAGE="${i#*=}"
  shift
  ;;
  -DEB_CUSTOM_PARSE=*)
  DEB_CUSTOM_PARSE="${i#*=}"
  shift
  ;;
  -JQ_CUSTOM_PARSE=*)
  JQ_CUSTOM_PARSE="${i#*=}"
  shift
  ;;
  -FULL_CUSTOM=*)
  FULL_CUSTOM="${i#*=}"
  shift
  ;;
  -TWO_STAGE=*)
  TWO_STAGE="${i#*=}"
  shift
  ;;
  -SECOND_COMMAND=*)
  SECOND_COMMAND="${i#*=}"
  shift
  ;;
esac
done


#############
# Functions #
#############

# Send a message explaining the build trigger and reason to discord
function tell_discord {
  curl -X POST -H "Content-Type: application/json" --data '{"avatar_url": "https://wiki.jenkins-ci.org/download/attachments/2916393/headshot.png","embeds": [{"color": 9802903,
                        "description": "**Build Triggered** \n**Reason:**: '"${TRIGGER_REASON}"' \n"}],
                        "username": "Jenkins"}' ${BUILDS_DISCORD}
}

function tell_discord_fail {
  curl -X POST -H "Content-Type: application/json" --data '{"avatar_url": "https://wiki.jenkins-ci.org/download/attachments/2916393/headshot.png","embeds": [{"color": 16711680,
                        "description": "**Trigger Failed** \n**Reason:**: '"${FAILURE_REASON}"' \n"}],
                        "username": "Jenkins"}' ${BUILDS_DISCORD}
}

# Trigger the build for this triggers job
function trigger_build {
# Fail on nulls or unset variables for comparison from external sources
  if [ -z "${CURRENT_TAG}" ] && [ -z "${CURRENT_MD5}" ]; then
    FAILURE_REASON='Unable to get version information from external source for '"${LS_REPO}"' '
    tell_discord_fail
    exit 0
  fi
  curl -X POST \
      https://ci.linuxserver.io/job/Docker-Pipeline-Builders/job/${LS_REPO}/job/${LS_BRANCH}/buildWithParameters?PACKAGE_CHECK=false \
      --user ${JENKINS_USER}:${JENKINS_API_KEY}
  tell_discord
}

# Retrieve the latest image info from docker hub
function get_image_info {

  local repo=$(echo $LS_REPO | sed 's/docker-//g' )
  local image="${LS_USER}/${repo}"
  if [ "${LS_RELEASE_TYPE}" == "stable" ]; then
    local tag="latest"
  elif [ "${LS_RELEASE_TYPE}" == "prerelease" ]; then
    local tag="${LS_BRANCH}"
  else
    local tag="${LS_RELEASE_TYPE}"
  fi
  local token=$(get_token $image)
  local digest=$(get_digest $image $tag $token)

  get_image_configuration $image $token $digest
}

function get_image_configuration() {
  local image=$1
  local token=$2
  local digest=$3

  curl \
    --silent \
    --location \
    --header "Authorization: Bearer $token" \
    "https://registry-1.docker.io/v2/$image/blobs/$digest" \
    | jq -r '.container_config'
}

function get_token() {
  local image=$1

  curl \
    --silent \
    "https://auth.docker.io/token?scope=repository:$image:pull&service=registry.docker.io" \
    | jq -r '.token'
}

function get_digest() {
  local image=$1
  local tag=$2
  local token=$3

  curl \
    --silent \
    --header "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    --header "Authorization: Bearer $token" \
    "https://registry-1.docker.io/v2/$image/manifests/$tag" \
    | jq -r '.config.digest'
}


# Get the current release info from Docker Hub
LS_RELEASE=$(get_image_info | jq -r '.Labels.build_version' | awk '{print $3}')
EXTERNAL_TAG=$(echo ${LS_RELEASE} | awk -F'-ls' '{print $1}')
LS_VERSION=$(echo ${LS_RELEASE} | sed 's/^.*-ls//g')


################
# Input Checks #
################

# Fail on nulls or unset variables for comparison from Docker Hub
if [ -z "${LS_RELEASE}" ]; then
  FAILURE_REASON='Unable to get version information from Docker Hub for '"${LS_REPO}"' '
  tell_discord_fail
  exit 0
fi


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
  # Sanitize the tag
  CURRENT_TAG=$(echo ${CURRENT_TAG} | sed 's/[~,%@+;:/]//g')
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
      CURRENT_TAG_CHECK=$(echo ${CURRENT_TAG} | tr -d '.[0-9]' | wc -c)
      # Check if the version string has more than 1 character outside of numbers and dots
      if [ "${CURRENT_TAG_CHECK}" -gt 2 ]; then
        FAILURE_REASON='We did not get a standard version number back from:'"${FULL_URL}"' for '"${LS_REPO}"' actual string '"${CURRENT_TAG}"' '
        tell_discord_fail
        exit 0
      fi
    else
      FAILURE_REASON='Unable to get the URL:'"${FULL_URL}"' for '"${LS_REPO}"' make sure URLs used to trigger are up to date'
      tell_discord_fail
      exit 0
    fi
  # Sanitize the tag
  CURRENT_TAG=$(echo ${CURRENT_TAG} | sed 's/[~,%@+;:/]//g')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_TAG}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current: ${CURRENT_TAG}"
    TRIGGER_REASON='A version change was detected for '"${LS_REPO}"' at the URL:'"${FULL_URL}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

# This is a jq trigger
if [ "${TRIGGER_TYPE}" == "custom_jq" ]; then
  echo "This is a custom jq trigger"
  # Determine the current version from the jq command
    # Make sure the endppoint returns a 200
    RESP=$(curl -Ls -w "%{http_code}" -o /dev/null "${JQ_URL}")
    if [ ${RESP} == 200 ] || [ ${RESP} == 000 ] ; then
      if [ -z ${JQ_CUSTOM_PARSE+x} ]; then
        CURRENT_TAG=$(curl -sL "${JQ_URL}" | jq -r ". | ${JQ_LOGIC}")
      else
        CURRENT_TAG_UNPARSED=$(curl -sL "${JQ_URL}" | jq -r ". | ${JQ_LOGIC}")
        CURRENT_TAG=$(bash -c "echo ${CURRENT_TAG_UNPARSED}| ${JQ_CUSTOM_PARSE}")
      fi
    else
      FAILURE_REASON='Unable to get the URL:'"${JQ_URL}"' for '"${LS_REPO}"' make sure URLs used to trigger are up to date'
      tell_discord_fail
      exit 0
    fi
  # Sanitize the tag
  CURRENT_TAG=$(echo ${CURRENT_TAG} | sed 's/[~,%@+;:/]//g')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_TAG}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current: ${CURRENT_TAG}"
    TRIGGER_REASON='A version change was detected for '"${LS_REPO}"' at the URL:'"${JQ_URL}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

# This is a Deb Package trigger
if [ "${TRIGGER_TYPE}" == "deb_package" ]; then
  echo "This is a deb package trigger"
  # Determine the current version
    # Make sure the endppoint returns a 200
    RESP=$(curl -Ls -w "%{http_code}" -o /dev/null "${DEB_PACKAGES_URL}")
    if [ ${RESP} == 200 ]; then
      if [[ ${DEB_PACKAGES_URL} == *".gz" ]]; then
        if [ -z ${DEB_CUSTOM_PARSE+x} ]; then
          CURRENT_TAG=$(curl -sX GET ${DEB_PACKAGES_URL} | gunzip -c |grep -A 7 -m 1 "Package: ${DEB_PACKAGE}" | awk -F ': ' '/Version/{print $2;exit}')
        else
          CURRENT_TAG_UNPARSED=$(curl -sX GET ${DEB_PACKAGES_URL} | gunzip -c |grep -A 7 -m 1 "Package: ${DEB_PACKAGE}" | awk -F ': ' '/Version/{print $2;exit}')
          CURRENT_TAG=$(bash -c "echo ${CURRENT_TAG_UNPARSED}| ${DEB_CUSTOM_PARSE}")
        fi
      else
        if [ -z ${DEB_CUSTOM_PARSE+x} ]; then
          CURRENT_TAG=$(curl -sX GET ${DEB_PACKAGES_URL} |grep -A 7 -m 1 "Package: ${DEB_PACKAGE}" | awk -F ': ' '/Version/{print $2;exit}')
        else
          CURRENT_TAG_UNPARSED=$(curl -sX GET ${DEB_PACKAGES_URL} |grep -A 7 -m 1 "Package: ${DEB_PACKAGE}" | awk -F ': ' '/Version/{print $2;exit}')
          CURRENT_TAG=$(bash -c "echo ${CURRENT_TAG_UNPARSED}| ${DEB_CUSTOM_PARSE}")
        fi
      fi
    else
      FAILURE_REASON='Unable to get the URL:'"${DEB_PACKAGES_URL}"' for '"${LS_REPO}"' make sure URLs used to trigger are up to date'
      tell_discord_fail
      exit 0
    fi
  # Sanitize the tag
  CURRENT_TAG=$(echo ${CURRENT_TAG} | sed 's/[~,%@+;:/]//g')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_TAG}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current: ${CURRENT_TAG}"
    TRIGGER_REASON='A version change was detected for '"${LS_REPO}"' at the URL:'"${DEB_PACKAGES_URL}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

# This is a very custom trigger
# The custom bash you pass to this trigger needs to have some kind of logic to exit badly if a remote resource is not available
if [ "${TRIGGER_TYPE}" == "full_custom" ]; then
  echo "This is a full custom trigger"
  # Determine the current version
  CURRENT_TAG=$(bash -c "${FULL_CUSTOM}")
  # Detect failure in command
  if [ "$?" -ne 0 ]; then
    FAILURE_REASON='Unable to execute custom version command for '"${LS_REPO}"' make sure this command still works in Jenkins'
    tell_discord_fail
    exit 0
  fi
  # Sanitize the tag
  CURRENT_TAG=$(echo ${CURRENT_TAG} | sed 's/[~,%@+;:/]//g')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_TAG}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current: ${CURRENT_TAG}"
    TRIGGER_REASON='A version change was detected for '"${LS_REPO}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi


# This is a two stage trigger
# The custom bash you pass to this trigger needs to have some kind of logic to exit badly if a remote resource is not available for both commands
if [ "${TRIGGER_TYPE}" == "two_stage" ]; then
  echo "This is a two stage trigger"
  # Run first command
  FIRST_STAGE_OUT=$(bash -c "${TWO_STAGE}")
  # Detect failure in command
  if [ "$?" -ne 0 ]; then
    FAILURE_REASON='Unable to execute first stage command for '"${LS_REPO}"' make sure this command still works in Jenkins'
    tell_discord_fail
    exit 0
  fi
  COMMAND=$(echo "${SECOND_COMMAND}" | sed "s/FIRST_STAGE_OUT/${FIRST_STAGE_OUT}/g")
  CURRENT_TAG=$(bash -c "${COMMAND}")
  if [ "$?" -ne 0 ]; then
    FAILURE_REASON='Bad return from second stage command for '"${LS_REPO}"' this is likely by design to prevent triggering until second stage returns OK'
    tell_discord_fail
    exit 0
  fi
  # Sanitize the tag
  CURRENT_TAG=$(echo ${CURRENT_TAG} | sed 's/[~,%@+;:/]//g')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_TAG}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current: ${CURRENT_TAG}"
    TRIGGER_REASON='A version change was detected for '"${LS_REPO}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

