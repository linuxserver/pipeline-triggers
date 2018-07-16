# LinuxServer.io Build Environment

- [LinuxServer.io Build Environment](#linuxserverio-build-environment)
  * [Intro](#intro)
  * [The basics](#the-basics)
  * [Triggering a build](#triggering-a-build)
      - [LinuxServer Github Commits](#linuxserver-github-commits)
      - [External OS Package Change](#external-os-package--change)
      - [External Software Change](#external-software-change)
          + [Triggering based on changes in external JSON](#triggering-based-on-changes-in-external-json)
          + [Triggering based on custom external releases](#triggering-based-on-custom-external-releases)
  * [The JenkinsFile](#the-jenkinsfile)
      - [Build Types](#build-types)
      - [Header Variables](#header-variables)
  * [Appendix](#appendix)
      - [Repo Logic examples](#repo-logic-examples)
          + [Use a git release tag to download the source code and extract it](#use-a-git-release-tag-to-download-the-source-code-and-extract-it)
          + [Use a git release tag to download the source code and extract it when the package needed is not base source code](#use-a-git-release-tag-to-download-the-source-code-and-extract-it-when-the-package-needed-is-not-base-source-code)
          + [Use a git commit tag to download the source code and extract it](#use-a-git-commit-tag-to-download-the-source-code-and-extract-it)
          + [Use an NPM version tag to install a specific version](#use-an-npm-version-tag-to-install-a-specific-version)
          + [Use an PIP version tag to install a specific version](#use-an-pip-version-tag-to-install-a-specific-version)
          + [Set an ENV argument for post build installation](#set-an-env-argument-for-post-build-installation)
      - [Multi Arch and cross-building](#multi-arch-and-cross-building)
      - [Setting up a Jenkins Build slave](#setting-up-a-jenkins-build-slave)

## Intro

The purpose of this document is to be an evolving written explanation of the current state of the build system surrounding the LinuxServer.io Docker containers. It revolves around some core concepts:

- All containers should be built as soon as an external package release, internal code change, or system level package is changed. This will allow the team to deal with issues as they arrise instead of in bulk with timed operations.

- The code used should be as self documenting as possible and should avoid using externally linked libraries where possible. Preferably in a beginner level scripting language like BASH or Python.

 - All build logic should be contained within the source repository that is being built against.

 - Build logic should be as self contained as possible as to not lock into a specific build system. A triggered build should be able to determine the most current version of all component software being used to build the current image.

 - Notifications should be sent to the most active community platform for the team, and include as much information as possible to allow any member of the team to quickly troubleshoot and resolve.

 - The build process should be transparent to the end users participating in the community effort and they should recieve feedback on any pull requests or branched commits.

 - The build logic should stay generalized where possible to be easily and quickly templated to new projects.

## The basics

Given the general theme of LinuxServer we operate our own build servers and slaves using Jenkins. All of our repositories are hosted on github https://github.com/linuxserver .

The build system in general looks something like this:

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/LSLogic.png  "BuildLogic")

A conventional project will contain 3 different build triggers:

- Commit to LinuxServer base repository

- Change in referenced OS level packages

- Change in a referenced external software package the project is based on

When any of these triggers fire, the job for the given repo will be triggered on the Jenkins Master.

## Triggering a build

The logic for all of the custom triggers can be found in this repository:

https://github.com/linuxserver/pipeline-triggers/blob/master/trigger-logic.sh

This is pulled and passed parameters on a timer based on the custom configuration for your trigger job.

#### LinuxServer Github Commits

 This is the most baked in methodology of triggering a build for a Jenkins Pipeline. It is a two step process to configure the repository with a JenkinsFile and add it to Jenkins at https://pipeline.linuxserver.io/blue/organizations/jenkins/create-pipeline . ( In this example for a development user for docker-freshrss )

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/addpipeline.png  "Addpipeline")

 With the Pipeline in place you will also need to configure the repository to use the Jenkins Github plugin to trigger builds when a commit or pull request is sent to the repo. The URL to use for this integraiton is:

 https://pipeline.linuxserver.io/github-webhook/

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/addtriggergithub.png  "triggergithub")

 With these setup the pipeline defined in the Master branch of the project will be triggered whenever code is changed.

#### External OS Package  Change

 Again the code for this job can be found in this repo under https://github.com/linuxserver/pipeline-triggers/blob/master/trigger-logic.sh . In order for this to fire off a build job on a change a timed job needs to be configured to run every hour in Jenkins.

 A good reference job to copy when setting this up is:

 https://pipeline.linuxserver.io/job/package-trigger-docker-cops/configure

 The job takes a series of string parameters to pass to the trigger-logic bash script. Using these parameters we can generate an MD5SUM of all of the package versions passed to the script.

 The logic depends on the OS, but essentially we run a package index update then pass an array of packages to the CLI package manager to print out the package versions and description. This huge blob is then piped into md5sum and the first 8 characters are used to form a unique tag that we can detect changes in.

#### External Software Change

In this document we will be covering two different external software change jobs. One uses the logic in the trigger-logic script for custom jobs, the other uses an http URL checker plugin for Jenkins.

###### Triggering based on changes in external JSON

The most common use for a job like this would be to reference the current version displayed on the Github API endpoint. An example of this type of job can be seen at:

https://pipeline.linuxserver.io/job/external-trigger-docker-cops/configure

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/httptrigger.png  "HTTPTrigger")

###### Triggering based on custom external releases

Some projects either do not live on GitHub or their release process requires us to do some unorthadox things to determine if there is a new release. These specialized checks live in bash in the logic script and are executed on a timed basis to consistently reach out and check for new versions.

In this example we will be checking an external file blob for a Plex deb package. The full job configuration can be seen here:

https://pipeline.linuxserver.io/job/external-trigger-docker-plex/configure

Here we are passing a file to the parameters that will be downloaded and referenced by this code segment in the trigger-logic to calculate an MD5 for the file:

```
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
```

If the MD5 does not match the current release, a build will be triggered.

## The JenkinsFile

At the core of a the build process is a git stored build configuration that is used for the LinuxServer repository when a build is triggered.

Templates for the different external release types can be found here:

https://github.com/linuxserver/pipeline-triggers/blob/master/JenkinsFiles/

#### Build Types

This file uses a series of parameters in the header to determine what type of build this will be to dictate the logic used to determine versions of the software to include in the container tagging process. A complete list of the types can be seen below:

- os- This project only uses OS level installed packages no need for an external release tag to be generated.
- github_stable- The GitHub releases api is polled to get the latest release for the project
- github_devel- The Github releases api is polled when there is no latest release and the first return in the array is used for the tag
- deb_repo- A string of debian (or ubuntu) repos is passed along with a list of packages and their package versions are checked by running a docker container at the version requested. An apt version for all of the listed packages is md5summed  for the release tagging.
- alpine_repo- An Alpine repo along with a  list of packages used from that repo are used to run a docker container at the version of alpine requested to generate an md5sum of the output for release tagging.
- github_commit- The GitHub commits api endpoint is polled to get the latest commit sha at the branch requested to generate a release tag.
- github_tag- The GitHub tags api endpoint is polled to get the latest tag for the project to generate a release tag.
- npm_version- The NPM api is polled to get the version number to generate a release tag.
- pip_version- The pyPIP api is polled to get the latest verison number to generate a release tag.
- external_blob- A custom http/https endpoint is defined and the file at that endpoint is downloaded to generate an md5sum for the release tag.
- custom_json- When you have a custom JSON endpoint to read versions from this will allow you to manually set a path in the JQ language format.

In all of these examples these extracted tags are what is passed to the subsequent build job and determines the version of software the user gets when running the container.

#### Header Variables

In the header of the Jenkinsfile is all that a normal contributor should be modifying the build logic will handle the rest.

For all of these variables, if they do not apply to the repo in question "none" is used as a boolean logic identifier.

A brief explanation of all of the variables used:

- EXT_RELEASE_TYPE- This will be one of the variables in the "Build Types" section of this document.
- EXT_GIT_BRANCH- The external project git branch you want to use for builds.
- EXT_USER- The GitHub user for the external project.
- EXT_REPO- The GitHub repo for the external project.
- EXT_NPM- The NPM package name for the external project.
- EXT_PIP- The PIP package name for the external project.
- EXT_BLOB- The URL used to calculate an MD5 for the external project.
- BUILD_VERSION_ARG- This is used to pass the data to the Dockerfile, it will be the ARG referenced in the Dockerfile being built.
- LS_USER- This should always be linuxserver unless on a forked repo.
- LS_REPO- This is the name of the LinuxServer repository currently being used.
- DOCKERHUB_IMAGE- This is the full string for the Live DockerHub endpoint IE "linuxserver/your-project"
- DEV_DOCKERHUB_IMAGE- This is the full string for the Dev DockerHub endpoint IE "linuxserver-dev/your-project". Branches outside of master will be pushed here.
- PR_DOCKERHUB_IMAGE- This is the full string for the Pull Request DockerHub endpoint IE "linuxserver-pr/your-project". Any pull requests will be pushed here.
- BUILDS_DISCORD- This pulls credentials from the Jenkins Master Server
- GITHUB_TOKEN- This pulls credentials from the Jenkins Master Server
- DIST_IMAGE- This is used for the package tag generation logic IE "alpine" or "ubuntu"
- DIST_TAG- This is used for the package tag generation logic IE "3.7" or "xenial"
- DIST_PACKAGES- This is a list of OS level packages
- DIST_REPO- If special repos are used for your image, this contains the external release that will be used to populate a command to pull package versions.
- DIST_REPO_PACKAGES-  If special repos are used for your image this contains the external release that will be a list of packages to check versions to generate a tag.
- JSON_URL- When using a custom JSON endpoint this is the URL of the endpoint
- JSON_PATH- This is the path to the item you want to watch for changes and use for the version code on the build IE '.linux.x86_64.version'
- MULTIARCH- if this will be built against the 3 architectures amd64, armhf, and arm64 (true/false)
- CI- true/false to enable continuous integration
- CI_PORT- The port the application you are building listens on a web interface internally
- CI_SSL- true/false to use an https endpoint to capture a screenshot of the endpoint
- CI_DELAY- amount of time in seconds to wait after the container spins up to grab a screenshot
- CI_DOCKERENV- single env variable or multiple seperated by '|' IE 'APP_URL=_|DB_CONNECTION=sqlite_testing'
- CI_AUTH- if the web application requires basic authentication format user:password
- CI_WEBPATH- custom path to use when capturing a screenshot of the web application



## Appendix

#### Repo Logic examples

This logic applies to the stuff outside of the Jenkins Workflow in the general Dockerfile and startup scripts for the container. These examples can be used to parse the external release tags into a working container.

###### Use a git release tag to download the source code and extract it

```
  echo "**** install app ****" && \
  mkdir -p \
    /app/hydra && \
  curl -o \
    /tmp/hydra.tar.gz -L \
    "https://github.com/theotherp/nzbhydra/archive/${HYDRA_RELEASE}.tar.gz" && \
  tar xf /tmp/hydra.tar.gz -C \
    /app/hydra --strip-components=1

```

Where HYDRA_RELEASE is the release tag passed by Docker build args.

###### Use a git release tag to download the source code and extract it when the package needed is not base source code

Some projects publish multiple versions of pre-built releases and you will need to use tags to determine which one to grab.

```
 echo "**** install ombi ****" && \
 mkdir -p \
        /opt/ombi && \
 ombi_url=$(curl -s https://api.github.com/repos/tidusjar/Ombi/releases/tags/"${OMBI_RELEASE}" |jq -r '.assets[].browser_download_url' |grep linux |grep -v arm) && \
 curl -o \
 /tmp/ombi-src.tar.gz -L \
        "${ombi_url}" && \
 tar xzf /tmp/ombi-src.tar.gz -C /opt/ombi/ && \
 chmod +x /opt/ombi/Ombi && \

```

Here we are using a grep command to pull out only the download URL that contains "linux"

###### Use a git commit tag to download the source code and extract it

```
 echo "**** install app ****" && \
 mkdir -p \
   /app/mylar && \
 curl -o \
 /tmp/mylar.tar.gz -L \
        "https://github.com/evilhero/mylar/archive/${MYLAR_COMMIT}.tar.gz" && \
 tar xf \
 /tmp/mylar.tar.gz -C \
        /app/mylar --strip-components=1 && \

```

###### Use an NPM version tag to install a specific version

```
 echo "**** install shout-irc ****" && \
 mkdir -p \
	/app && \
 cd /app && \
 npm install \
	thelounge@${THELOUNGE_VERSION} && \
```

###### Use an PIP version tag to install a specific version
```
 echo "**** install pip packages ****" && \
 pip install --no-cache-dir -U \
	beautifulsoup4 \
	beets==${BEETS_VERSION} \
	beets-copyartifacts \
	flask \
	pillow \
	pip \
	pyacoustid \
	pylast \
	unidecode && \
```

###### Set an ENV argument for post build installation

This can be useful if the software is installed when the container is first started up.

In the DockerFile:

```
ARG MUXIMUX_RELEASE
ENV MUXIMUX_RELEASE=${MUXIMUX_RELEASE}
```

In the Startup Logic:

```
# fetch site
if [ ! -d /config/www/muximux ]; then
	echo "First Run downloading MuxiMux at ${MUXIMUX_RELEASE}"
  mkdir -p /config/www/muximux
  curl -o /tmp/muximux.tar.gz -L "https://github.com/mescon/Muximux/archive/${MUXIMUX_RELEASE}.tar.gz"
  tar xf /tmp/muximux.tar.gz -C /config/www/muximux --strip-components=1
  rm -f /tmp/muximux.tar.gz
fi
```

#### Multi Arch and cross-building

When building applications some projects require building and pushing arm, and arm64 variants. To achieve this you must set the flag "MULTIARCH" to true in the Jenkinsfile and have a specific file structure in the repository.

```
Dockerfile.amd64
Dockerfile.armhf
Dockerfile.aarch64
qemu-aarch64-static
qemu-arm-static
```

The Qemu binaries can be downloaded here ( swap out for a new version )

https://github.com/multiarch/qemu-user-static/releases/download/v2.12.0/x86_64_qemu-aarch64-static.tar.gz
https://github.com/multiarch/qemu-user-static/releases/download/v2.12.0/x86_64_qemu-arm-static.tar.gz

The arm variants of the image need to copy these binaries to the image before running any RUN commands in the Dockerfile . IE:

```
FROM lsiobase/alpine.nginx.arm64:3.7
# Add qemu to build on x86_64 systems
COPY qemu-aarch64-static /usr/bin
```

```
FROM lsiobase/alpine.nginx.armhf:3.7
# Add qemu to build on x86_64 systems
COPY qemu-arm-static /usr/bin
```

This will push a manifest style tag to the DockerHub endpoint and allow users to download from any architecture using the same "latest" or specific tag.


#### Setting up a Jenkins Build slave

Jenkins build slaves work by being accessable via SSH and having some core programs installed we use for the build process here is an example of configuration on a Debian Server.

```
apt-get update && apt-get install apt-transport-https ca-certificates curl gnupg2 software-properties-common jq git default-jre
add-apt-repository    "deb [arch=amd64] https://download.docker.com/linux/$(. /etc/os-release; echo "$ID") \
$(lsb_release -cs) \
stable"
apt-get update && apt-get install docker-ce -y
```

You will also want to add the following cron job to the machine to keep it from filling up with built images over time:

```
0 0 * * 0 root /usr/bin/docker system prune -af
```

This will clear out the machine once a week.

To allow multi-arch builds first you need to register the interpreters with Docker using:

```
docker run --rm --privileged multiarch/qemu-user-static:register --reset

```

Then enable experimental CLI features:

```
echo '{"experimental": "enabled"}' > /root/.docker/config.json

```
