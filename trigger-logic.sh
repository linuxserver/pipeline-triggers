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
  -EXT_GIT_BRANCH=*)
  EXT_GIT_BRANCH="${i#*=}"
  shift
  ;;
  -EXT_USER=*)
  EXT_USER="${i#*=}"
  shift
  ;;
  -EXT_REPO=*)
  EXT_REPO="${i#*=}"
  shift
  ;;
  -EXT_NPM=*)
  EXT_NPM="${i#*=}"
  shift
  ;;
  -EXT_PIP=*)
  EXT_PIP="${i#*=}"
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
  -DIST_IMAGE=*)
  DIST_IMAGE="${i#*=}"
  shift
  ;;
  -DIST_TAG=*)
  DIST_TAG="${i#*=}"
  shift
  ;;
  -DIST_PACKAGES=*)
  DIST_PACKAGES="${i#*=}"
  shift
  ;;
  -DIST_REPO=*)
  DIST_REPO="${i#*=}"
  shift
  ;;
  -DIST_REPO_PACKAGES=*)
  DIST_REPO_PACKAGES="${i#*=}"
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
esac
done

# Get the current release info
LS_RELEASE=$(curl -s https://api.github.com/repos/${LS_USER}/${LS_REPO}/releases/latest | jq -r '. | .name')
EXTERNAL_TAG=$(echo ${LS_RELEASE} | awk -F'-pkg-' '{print $1}')
PACKAGE_TAG=$(echo ${LS_RELEASE} | grep -o -P '(?<=-pkg-).*(?=-ls)')
LS_VERSION=$(echo ${LS_RELEASE} | sed 's/^.*-ls//g')

#############
# Functions #
#############

# Send a message explaining the build trigger and reason to discord
function tell_discord {
  curl -X POST --data '{"avatar_url": "https://wiki.jenkins-ci.org/download/attachments/2916393/headshot.png","embeds": [{"color": 9802903,
                        "description": "**Build Triggerd** \n**Reason:**: '"${TRIGGER_REASON}"' \n"}],
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
      https://pipeline.linuxserver.io/job/${LS_REPO}/job/master/build \
      --user ${JENKINS_USER}:${JENKINS_API_KEY}
  tell_discord
}

####################
# Package triggers #
####################

# This is an Alpine package trigger
if [ "${TRIGGER_TYPE}" == "alpine_package" ]; then
  echo "This is an alpine package trigger"
  # Pull the latest alpine image
  docker pull alpine:${DIST_TAG}
  # Determine the current tag
  CURRENT_PACKAGE=$(docker run --rm alpine:${DIST_TAG} sh -c 'apk update --quiet\
  && apk info '"${DIST_PACKAGES}"' | md5sum | cut -c1-8')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_PACKAGE}" != "${PACKAGE_TAG}" ]; then
    TRIGGER_REASON="An Alpine base package change was detected for ${LS_REPO} old md5:${PACKAGE_TAG} new md5:${CURRENT_PACKAGE}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

# This is an Ubuntu package trigger
if [ "${TRIGGER_TYPE}" == "ubuntu_package" ]; then
  echo "This is an ubuntu package trigger"
  # Pull the latest ubuntu image
  docker pull ubuntu:${DIST_TAG}
  # Determine the current tag
  CURRENT_PACKAGE=$(docker run --rm ubuntu:${DIST_TAG} sh -c\
                   'apt-get --allow-unauthenticated update -qq >/dev/null 2>&1 &&\
                    apt-cache --no-all-versions show '"${DIST_PACKAGES}"' | md5sum | cut -c1-8')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_PACKAGE}" != "${PACKAGE_TAG}" ]; then
    TRIGGER_REASON="An Ubuntu base package change was detected for ${LS_REPO} old md5:${PACKAGE_TAG} new md5:${CURRENT_PACKAGE}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi


######################################
# External Software Release Triggers #
######################################

# This is a debian repo package trigger
if [ "${TRIGGER_TYPE}" == "deb_repo" ]; then
  echo "This is an deb repo package trigger"
  # Pull the latest image
  docker pull ${DIST_IMAGE}:${DIST_TAG}
  # Determine the current tag
  CURRENT_PACKAGE=$(docker run --rm ${DIST_IMAGE}:${DIST_TAG} sh -c\
                    'echo "${DIST_REPO}" > /etc/apt/sources.list.d/check.list \
                     && apt-get --allow-unauthenticated update -qq >/dev/null 2>&1\
                     && apt-cache --no-all-versions show ${DIST_PACKAGES} | md5sum | cut -c1-8')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_PACKAGE}" != "${EXTERNAL_TAG}" ]; then
    TRIGGER_REASON="A Debian package update has been detected for the ${LS_REPO} old md5:${EXTERNAL_TAG} new md5:${CURRENT_PACKAGE}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi

# This is an external file blob release
if [ "${TRIGGER_TYPE}" == "external_blob" ]; then
  echo "This is an External file blob package trigger"
  # Determine the current md5 for the file blob
    # Make sure the remote file returns a 200 status or fail
    if [ $(curl -I -sL -w "%{http_code}" ${EXT_BLOB} -o /dev/null) == 200 ]; then
      CURRENT_MD5=$(curl -s -L ${EXT_BLOB} | md5sum | cut -c1-8)
    else
      FAILURE_REASON="Unable to get the URL:${EXT_BLOB} for ${LS_REPO} make sure URLs used to trigger are up to date"
      tell_discord_fail
      exit 0
    fi
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_MD5}" != "${EXTERNAL_TAG}" ]; then
    echo "ext: ${EXTERNAL_TAG}"
    echo "current:${CURRENT_MD5}"
    TRIGGER_REASON="An external file change was detected for ${LS_REPO} at the URL:${EXT_BLOB} old md5:${EXTERNAL_TAG} new md5:${CURRENT_MD5}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi


# This is an Alpine repo trigger
if [ "${TRIGGER_TYPE}" == "alpine_repo" ]; then
  echo "This is an alpine package trigger"
  # Pull the latest alpine image
  docker pull alpine:${DIST_TAG}
  # Determine the current tag
  CURRENT_PACKAGE=$(docker run --rm alpine:${DIST_TAG} sh -c 'apk update --repository ${DIST_REPO} --quiet\
  && apk info --repository ${DIST_REPO} '"${DIST_PACKAGES}"' | md5sum | cut -c1-8')
  # If the current tag does not match the external release then trigger a build
  if [ "${CURRENT_PACKAGE}" != "${EXTERNAL_TAG}" ]; then
    TRIGGER_REASON="An Alpine repo package change was detected for ${LS_REPO} old md5:${EXTERNAL_TAG} new md5:${CURRENT_PACKAGE}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi
