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
      - [Templating](#templating)
          + [jenkins-vars](#jenkins-vars)
      - [Header Variables](#header-variables)
  * [Automating README updates](#automating-readme-updates)
  * [Appendix](#appendix)
      - [Repo Logic examples](#repo-logic-examples)
          + [Use a git release tag to download the source code and extract it](#use-a-git-release-tag-to-download-the-source-code-and-extract-it)
          + [Use a git release tag to download the source code and extract it when the package needed is not base source code](#use-a-git-release-tag-to-download-the-source-code-and-extract-it-when-the-package-needed-is-not-base-source-code)
          + [Use a git commit tag to download the source code and extract it](#use-a-git-commit-tag-to-download-the-source-code-and-extract-it)
          + [Use an NPM version tag to install a specific version](#use-an-npm-version-tag-to-install-a-specific-version)
          + [Use an PIP version tag to install a specific version](#use-an-pip-version-tag-to-install-a-specific-version)
          + [Set an ENV argument for post build installation](#set-an-env-argument-for-post-build-installation)
      - [Multi Arch and cross-building](#multi-arch-and-cross-building)
      - [Setting up a Jenkins Build Agent](#setting-up-a-jenkins-build-agent)
      - [Running from SSD on arm devices](#running-from-ssd-on-arm-devices)

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

Given the general theme of LinuxServer we operate our own build servers and agents using Jenkins. All of our repositories are hosted on github https://github.com/linuxserver .

The build system in general looks something like this:

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/LSLogic.png  "BuildLogic")

A conventional project will contain 3 different build triggers:

- Commit to LinuxServer base repository

- Change in OS level packages

- Change in a referenced external software package the project is based on

When any of these triggers fire, the job for the given repo will be triggered on the Jenkins Master.

## Triggering a build

The logic for all of the custom triggers can be found in this repository:

https://github.com/linuxserver/pipeline-triggers/blob/master/trigger-logic.sh

This is pulled and passed parameters on a timer based on the custom configuration for your trigger job.

The vast majority of repositories do not use these custom triggers, we simply use a polling plugin that reaches out to api endpoints and checks for changes in specific JSON objects (IE github releases or commits api).

#### LinuxServer Github Commits

This is the most baked in methodology of triggering a build for a Jenkins Pipeline. It is a two step process to configure the repository with a JenkinsFile and add it to Jenkins at https://ci.linuxserver.io/blue/organizations/jenkins/create-pipeline . ( In this example for a development user for docker-freshrss )

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/addpipeline.png  "Addpipeline")

With the Pipeline in place you will also need to configure the repository with a webhook to push events in JSON format to the following endpoint:

https://ci.linuxserver.io/github-webhook/

Below is the configuration:

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/add_webhook.png  "triggergithub")

This should happen automatically, but some users do not have these privileges, so adding this webhook is documented here.

With these setup and the Jenkinsfile for the project in repo the project will be built on all commits.

We break up the endpoints for a dockerhub push based on the type of commit:

- [linuxserver](https://hub.docker.com/u/linuxserver/) - All commits to the master branch will push to our live endpoint
- [lsiodev](https://hub.docker.com/u/lsiodev/) - All commits to non master branches will push to this endpoint
- [lspipepr](https://hub.docker.com/u/lspipepr/) - All pull requests will push to this endpoint

#### External OS Package Change

The Jenkinsfile contains logic to automatically maintain a list of all of the installed packages and their versions dumped after the build succeeds, this can be found in package_versions.txt in the repository under the master branch. If this file does not exist it will automatically be generated and committed on the first build.

If any of the packages are updated in our docker images we want to rebuild and push a fresh build. In order to achieve this we trigger the existing jobs to build once a week with a special parameter passed to the build job:

```
PACKAGE_CHECK=true
```

An example of the weekly package check trigger can be found here:

https://ci.linuxserver.io/job/External-Triggers/job/snipe-it-package-trigger/configure

When creating a new trigger simply copy this job and swap in the endpoints you need to build.

#### External Software Change

In this document we will be covering two different external software change jobs. One uses the logic in the trigger-logic script for custom jobs, the other uses an http URL checker plugin for Jenkins.

###### Triggering based on changes in external JSON

The most common use for a job like this would be to reference the current version displayed on the Github API endpoint. An example of this type of job can be seen at:

https://ci.linuxserver.io/job/External-Triggers/job/snipe-it-external-trigger/configure

![ ](https://s3-us-west-2.amazonaws.com/linuxserver-docs/images/httptrigger.png  "HTTPTrigger")

Here we poll this URL every 15 minutes and check the release tag for changes in the JSON payload.

###### Triggering based on custom external releases

Some projects either do not live on GitHub or their release process requires us to do some unorthodox things to determine if there is a new release. These specialized checks live in bash in the logic script and are executed on a timed basis to consistently reach out and check for new versions.

In this example we will be checking an external Debian style repo for a change to mariadb:

https://ci.linuxserver.io/job/External-Triggers/job/mariadb-external-trigger/

Here we are passing debian repo URL and the package name we want to parse out to this logic:

```
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
    TRIGGER_REASON='An version change was detected for '"${LS_REPO}"' at the URL:'"${DEB_PACKAGES_URL}"' old version:'"${EXTERNAL_TAG}"' new version:'"${CURRENT_TAG}"
    trigger_build
  else
    echo "Nothing to do release is up to date"
  fi
fi
```

The Specific bash logic is as follows for calling the trigger script:

```
./trigger-logic.sh \
-TRIGGER_TYPE="deb_package" \
-LS_USER="linuxserver" \
-LS_REPO="docker-mariadb" \
-LS_BRANCH="master" \
-LS_RELEASE_TYPE="stable" \
-DEB_PACKAGES_URL="http://mirror.sax.uk.as61049.net/mariadb/repo/10.3/ubuntu/dists/bionic/main/binary-amd64/Packages" \
-DEB_PACKAGE="mariadb-server" \
-BUILDS_DISCORD=${BUILDS_DISCORD} \
-JENKINS_USER=thelamer \
-JENKINS_API_KEY=${JENKINS_API_KEY}
```

If the Tag does not match we will trigger a build on the master branch of docker-mariadb. 

## The JenkinsFile

At the core of a the build process is a git stored build configuration that is used for the LinuxServer repository when a build is triggered.

Templates for the different external release types can be found here:

https://github.com/linuxserver/pipeline-triggers/blob/master/Jenkinsfiles/

#### Build Types

This file uses a series of parameters in the header to determine what type of build this will be to dictate the logic used to determine versions of the software to include in the container tagging process. A complete list of the types can be seen below:

- os- This project only uses OS level installed packages no need for an external release tag to be generated.
- github_stable- The GitHub releases api is polled to get the latest release for the project
- github_devel- The Github releases api is polled when there is no latest release and the first return in the array is used for the tag
- deb_repo- A string of debian (or ubuntu) repos is passed along with a list of packages and their package versions are checked by running a docker container at the version requested. An apt version for all of the listed packages is md5summed  for the release tagging.
- alpine_repo- An Alpine repo along with a  list of packages used from that repo are used to run a docker container at the version of alpine requested to generate an md5sum of the output for release tagging.
- github_commit- The GitHub commits api endpoint is polled to get the latest commit sha at the branch requested to generate a release tag.
- npm_version- The NPM api is polled to get the version number to generate a release tag.
- pip_version- The pyPIP api is polled to get the latest verison number to generate a release tag.
- external_blob- A custom http/https endpoint is defined and the file at that endpoint is downloaded to generate an md5sum for the release tag.
- custom_json- When you have a custom JSON endpoint to read versions from this will allow you to manually set a path in the JQ language format.

In all of these examples these extracted tags are what is passed to the subsequent build job and determines the version of software the user gets when running the container.

#### Templating

In order to maintain the build logic across all of our repos we leverage a helper container to render the current Jenkinsfile at build time and compare it with current. If changes are found the updates will be pushed to the selected branch of the repo.

When initially creating a project or converting from older build logic two files will need to be included in the repo:

 - Jenkinsfile- This is the main build logic, but at a minimum it only needs to contain the logic to template from the jenkins variables passed to it. Examples of minimal files are included in this repository under the Jenkinsfiles folder.
 - jenkins-vars.yml- Contains all of the custom variables for this project needed by the build logic.

In order to participate in the development of the build logic that waterfalls to all of the pipeline repos, please see:

https://github.com/linuxserver/docker-jenkins-builder

##### jenkins-vars

This file will contain all of the needed variables covered in the Repo Variables section covered below and will have its own header for logic wrapping:

 - project_name- Full name of repository.
 - external_type- This will be one of the Build types above IE github_stable .
 - release_type- This determines if it is a stable or prerelease in github, this can be useful for branched projects where you want to build a development or nightly build in the case of prerelease.
 - release_tag- Determines the finished meta tag for the dockerhub endpoint, for all master branch builds this will be latest, for development branches this can vary IE nightly or development
 - ls_branch- The branch you are currently building on, this is hardcoded into the variables file to avoid any mistakes. It will be used to keep metadata files and template files up to date in that branch. If you are working on a temporary branch you **DO NOT** need to switch this around as you do not want the resulting builds to update anything in your temp branch. Again, only use this for permanent development branches for building nightly or dev version of the software.

#### Repo Variables

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
- DIST_TAG- This is used for the package tag generation logic IE "3.8" or "bionic"
- DIST_REPO- If special repos are used for your image, this contains the external release that will be used to populate a command to pull package versions.
- DIST_REPO_PACKAGES-  If special repos are used for your image this contains the external release that will be a list of packages to check versions to generate a tag.
- JSON_URL- When using a custom JSON endpoint this is the URL of the endpoint
- JSON_PATH- This is the path to the item you want to watch for changes and use for the version code on the build IE '.linux.x86_64.version'
- MULTIARCH- if this will be built against the 3 architectures amd64, armhf, and arm64 (true/false)
- CI- true/false to enable continuous integration
- CI_WEB- true/false to enable screen shotting the web application for the CI process
- CI_PORT- The port the application you are building listens on a web interface internally
- CI_SSL- true/false to use an https endpoint to capture a screenshot of the endpoint
- CI_DELAY- amount of time in seconds to wait after the container spins up to grab a screenshot
- CI_DOCKERENV- single env variable or multiple seperated by '|' IE 'APP_URL=blah.com|DB_CONNECTION=sqlite_testing'
- CI_AUTH- if the web application requires basic authentication format user:password
- CI_WEBPATH- custom path to use when capturing a screenshot of the web application

## Automating README updates

Another pain point we have as an organization is managing over 100 READMEs across Github and Dockerhub. The build process uses helper containers in conjunction with an in repo yaml file to template the README from a master template and push the updates to both Github and Dockerhub.

This means the repo will need a "readme-vars.yml file in the root of the repo, an example can be seen below:

```
---

# project information
project_name: smokeping
project_url: "https://oss.oetiker.ch/smokeping/"
project_logo: "https://camo.githubusercontent.com/e0694ef783e3fd1d74e6776b28822ced01c7cc17/687474703a2f2f6f73732e6f6574696b65722e63682f736d6f6b6570696e672f696e632f736d6f6b6570696e672d6c6f676f2e706e67"
project_blurb: "[{{ project_name|capitalize }}]({{ project_url }}) keeps track of your network latency. For a full example of what this application is capable of visit [UCDavis](http://smokeping.ucdavis.edu/cgi-bin/smokeping.fcgi)."
project_lsio_github_repo_url: "https://github.com/linuxserver/docker-{{ project_name }}"

# supported architectures
available_architectures:
  - { arch: "{{ arch_x86_64 }}", tag: "tbc"}
  - { arch: "{{ arch_arm64 }}", tag: "tbc"}
  - { arch: "{{ arch_armhf }}", tag: "tbc"}

# container parameters
param_container_name: "{{ project_name }}"
param_usage_include_vols: true
param_volumes:
  - { vol_path: "/config", vol_host_path: "</path/to/smokeping/config>", desc: "Configure the `Targets` file here" }
  - { vol_path: "/data", vol_host_path: "</path/to/{{ project_name }}/data>", desc: "Storage location for db and application data (graphs etc)" }
param_usage_include_ports: true
param_ports:
  - { external_port: "80", internal_port: "80", port_desc: "Allows HTTP access to the internal webserver." }
param_usage_include_env: true
param_env_vars:
  - { env_var: "TZ", env_value: "Europe/London", desc: "Specify a timezone to use EG Europe/London"}

# application setup block
app_setup_block_enabled: true
app_setup_block: |
  - Once running the URL will be `http://<host-ip>/smokeping/smokeping.cgi`.
  - Basics are, edit the `Targets` file to ping the hosts you're interested in to match the format found there.
  - Wait 10 minutes.

# changelog
changelogs:
  - { date: "28.04.18:", desc: "Rebase to alpine 3.8." }
  - { date: "09.04.18:", desc: "Add bc package." }
  - { date: "08.04.18:", desc: "Add tccping script and tcptraceroute package (thanks rcarmo)." }
  - { date: "13.12.17:", desc: "Expose httpd_conf to /config." }
  - { date: "13.12.17:", desc: "Rebase to alpine 3.7." }
  - { date: "24.07.17:", desc: "Add :unraid tag for hosts without ipv6." }
  - { date: "12.07.17:", desc: "Add inspect commands to README, move to jenkins build and push." }
  - { date: "28.05.17:", desc: "Rebase to alpine 3.6." }
  - { date: "07.05.17:", desc: "Expose smokeping.conf in /config/site-confs to allow user customisations" }
  - { date: "12.04.17:", desc: "Fix cropper.js path, thanks nibbledeez." }
  - { date: "09.02.17:", desc: "Rebase to alpine 3.5." }
  - { date: "17.10.16:", desc: "Add ttf-dejavu package as per [LT forum](http://lime-technology.com/forum/index.php?topic=43602.msg507875#msg507875)." }
  - { date: "10.09.16:", desc: "Add layer badges to README." }
  - { date: "05.09.16:", desc: "Add curl package." }
  - { date: "28.08.16:", desc: "Add badges to README." }
  - { date: "25.07.16:", desc: "Rebase to alpine linux." }
  - { date: "23.07.16:", desc: "Fix apt script confusion." }
  - { date: "29.06.15:", desc: "This is the first release, it is mostly stable, but may contain minor defects. (thus a beta tag)" }
```

These variables will be applied to the master template found here:

https://github.com/linuxserver/docker-jenkins-builder/blob/master/roles/generate-jenkins/templates/README.j2

If this is the first time templating a README in a repo it is recommended to build it locally and commit the finished readme.

Once you have the variables setup the way to like you can test the output by executing:

```
docker pull linuxserver/jenkins-builder:latest && \
docker run --rm \
 -v $(pwd):/tmp \
 -e LOCAL=true \
 linuxserver/jenkins-builder:latest && \
rm -f "$(basename $PWD).md"
```

This will output all necessary templated files in your current working directory (should be the repo you are working on), including README.md and Jenkinsfile and can be pushed with the commit or left out and a bot will commit the new README to master via the build agent. It also saves the readme file for the docs repo named `<project-name>.md`, which gets deleted in the last part or the above command.

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
Dockerfile
Dockerfile.armhf
Dockerfile.aarch64
```

In order to build and run arm stuff on x86 locally you will need the following command: 

```
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
```
To build using the specific Dockerfiles: 

```
docker build -f Dockerfile.aarch64 -t testarm64 .
docker build -f Dockerfile.armhf -t testarm .
```
It is important to note that qemu emulation is not perfect, but it is very useful when you have no access to native arm hardware.

#### Setting up a Jenkins Build Agent

Jenkins build agents work by being accessible via SSH and having some core programs installed we use for the build process here are the steps to preparing a jenkins build agent:

1. Install docker via the convenience script
```
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```
2. Create a separate build agent container for each executor (customize the paths and the ports)
```
services:
  build-agent-a:
    image: lscr.io/linuxserver/build-agent:latest
    privileged: true
    container_name: build-agent-a
    environment:
      - TZ=Etc/UTC
      - 'PUBLIC_KEY=<insert public key here>'
    volumes:
      - /docker-data/build-agent-a:/config
    ports:
      - 2222:2222
    restart: unless-stopped
  build-agent-b:
    image: lscr.io/linuxserver/build-agent:latest
    privileged: true
    container_name: build-agent-b
    environment:
      - TZ=Etc/UTC
      - 'PUBLIC_KEY=<insert public key here>'
    volumes:
      - /docker-data/build-agent-b:/config
    ports:
      - 2223:2222
    restart: unless-stopped
```
3. In Jenkins, add each new build agent container as a single executor builder. Set the remote root directory to `/config/jenkins` and don't forget to set the unique port, which is hidden under the advanced button.
4. *[X86_64 only]* To allow multi-arch builds first you need to register the interpreters with Docker and it needs to be done every time the docker service is re/started. This can be accomplished by creating a new systemd service (ie. `/lib/systemd/system/multiarch.service`) with the following content and enabling it via `sudo systemctl enable multiarch.service`. The command should now run every time the docker service is re/started:

    ```
    [Unit]
    Description=Multi-arch docker builds
    Requires=docker.service
    After=docker.service

    [Service]
    Type=simple
    ExecStart=/usr/bin/docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

    [Install]
    WantedBy=docker.service
    ```


#### Running from SSD on arm devices

Arm devices often fail during long builds due to SD cards and poor IO. On most arm devices you can move the bootfs to an external SSD connected via a USB-SATA adapter, which yields much higher stability.  

Hardware needed:
1. 128GB SSD (~$20)
2. USB-SATA adapter (either needs to be a powered one, or it needs to be plugged into a powered USB hub because most arm devices do not have enough power to supply an external drive) ($10-$20)

Raspberry Pi now support booting from USB with an updated bootloader. If your bootloader needs to be updated, you can use Raspberry Pi Imager to flash the bootloader updater to an SD card and update the bootloader that way.

You can use Raspberry Pi Imager to flash Ubuntu Server directly onto the SSD via a USB-SATA adapter. As long as the bootloader is updated, the Rpi should now be able to boot directly from the USB-SATA without an SD card inserted.
