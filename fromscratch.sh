#!/bin/bash

# =============================================================================
# Preamble
# =============================================================================
set -e
MAIN_DIR="$(dirname "$BASH_SOURCE")"
cd "$MAIN_DIR"
SCRIPTDIR="$(pwd -P)"
# =============================================================================

usage() {
    echo "[MVN=/path/to/mvn/mvn] $BASH_SOURCE [options]" 
    echo " Options:"
    echo "    -v:  tensorflow version. e.g. \"-v 1.9.0\" This defaults to $DEFAULT_TENSORFLOW_VERSION"
    echo "    -cv: cuda version. e.g. \"-cv 9.2\" This defaults to $DEFAULT_CUDA_VERSION. Note, the"
    echo "           CUDNN version is determined by examining the \"cudnn.h\" header file."
    echo "    -u:  Ubuntu base image version. This defaults to $DEFAULT_UBUNTU_BASE_VERSION"
    echo "    -w:  working directory, where the final container files will be written. This defaults"
    echo "           to \"$DEFAULT_WORKING_DIRECTORY\""
    echo "    -c:  tensorflow compute caps to build. E.g. \"-c \" This defaults to $TENSORFLOW_COMPUTE_CAPS"
    echo "           NOTE: this is NOT the tensorflow build defaut. 1.8.0 and 1.9.0 tensorflow default"
    echo "           compute caps are \"3.5,5.2\". To build these specifcy \"-c '3.5,5.2'\""
    echo "    -b:  bazel version to build tensorflow with. e.g. \"-b $DEFAULT_BAZEL_VERSION\" This defaults to $DEFAULT_BAZEL_VERSION"
    echo "    --deploy: perform a \"mvn deploy\" rather than just a \"mvn install\""
    echo "    --offline: Pass -o to maven."
    echo ""
    echo "    -g:  compile TensorFlow with debug symbols."
    echo "    --container=$DEFAULT_BASE_CONTAINER : use the named container. The default is shown."
    echo "    --just-build: This will assume the docker container has already been prepped and an image of the"
    echo "       preped system has been created. This is done automatically by the script so you're safe using this"
    echo "       if you've already run the build once or even cancelled it after the setup. If you're playing with"
    echo "       different options then once the preped image built, using --just-build will allow subsequent runs"
    echo "       to progress faster."
    echo "    --skip-packaging: Skip the packaging step. That is, only build the tensorflow libraries but"
    echo "       don't package them in a jar file for use with net.dempsy.util.library.NativeLivbraryLoader"
    echo "    --local_resources availableRAM,availableCPU,availableIO : Note the underscore. The value given"
    echo "       is passed directly to bazel (the build tool used by TensorFlow). See: "
    echo "       https://stackoverflow.com/questions/34756370/is-there-a-way-to-limit-the-number-of-cpu-cores-bazel-uses"
    echo "    -bg:  Background the docker build. The can only be specified with --skip-packaging"
    echo "    --help:  Print this message."
    echo ""
    echo "    if MVN isn't set then the script assumes \"mvn\" is on the command line PATH"

    if [ $# -gt 0 ]; then
        exit $1
    else
        exit 1
    fi
}

removeContainer() {
    set -e
    WAS_RUNNING=$($SUDO docker ps -aq --filter=name="$1")
    if [ "$WAS_RUNNING" != "" ]; then
        echo "Removing previous container \"$1\" that's no longer running."
        $SUDO docker rm "$1"
    fi
}

DEFAULT_WORKING_DIRECTORY=/tmp/tensorflow
DEFAULT_TENSORFLOW_COMPUTE_CAPS="5.0,6.1"
DEFAULT_TENSORFLOW_VERSION=1.11.0
DEFAULT_BAZEL_VERSION=0.19.1
DEFAULT_CUDA_VERSION=10.1
DEFAULT_UBUNTU_BASE_VERSION=18.04
DEFAULT_BASE_CONTAINER="nvidia/cuda:${DEFAULT_CUDA_VERSION}-cudnn7-devel-ubuntu${DEFAULT_UBUNTU_BASE_VERSION}"

SKIPP=
TENSORFLOW_VERSION=$DEFAULT_TENSORFLOW_VERSION
TENSORFLOW_COMPUTE_CAPS=$DEFAULT_TENSORFLOW_COMPUTE_CAPS
BAZEL_VERSION=$DEFAULT_BAZEL_VERSION
CUDA_VERSION=$DEFAULT_CUDA_VERSION
UBUNTU_BASE_VERSION=$DEFAULT_UBUNTU_BASE_VERSION

SCRIPT_DIR="$SCRIPTDIR"/container-files
IC_SCRIPT_DIR=/tmp/files
IC_WORKING_DIR=/tmp/output

WORKING_DIRECTORY="$DEFAULT_WORKING_DIRECTORY"

TENSORFLOW_DEBUG_SYMBOLS=
LOCAL_RESOURCES_OPT=
LOCAL_RESOURCES=
DOCKER_RUN_OPT=
JUST_BUILD=
DEPLOY_ME=
OFFLINE=

BASE_CONTAINER=
while [ $# -gt 0 ]; do
    case "$1" in
        --container=*)
            BASE_CONTAINER="$(echo "$1" | sed -e "s/^--container=//1")"
            shift
            ;;
        "-g")
            TENSORFLOW_DEBUG_SYMBOLS=true
            shift
            ;;
        "-w")
            WORKING_DIRECTORY=$2
            shift
            shift
            ;;
        "-v")
            TENSORFLOW_VERSION=$2
            shift
            shift
            ;;
        "-u")
            UBUNTU_BASE_VERSION=$2
            shift
            shift
            ;;
        "-cv")
            CUDA_VERSION=$2
            shift
            shift
            ;;
        "-c")
            TENSORFLOW_COMPUTE_CAPS=$2
            shift
            shift
            ;;
        "-b")
            BAZEL_VERSION=$2
            shift
            shift
            ;;
        "-sp"|"--skip-packaging")
            SKIPP=true
            shift
            ;;
        "--deploy")
            DEPLOY_ME="--deploy"
            shift
            ;;
        "--offline")
            OFFLINE=--offline
            shift
            ;;
        "-bg")
            DOCKER_RUN_OPT="-d"
            shift
            ;;
        "--just-build")
            JUST_BUILD=true
            shift
            ;;
        "--local_resources")
            LOCAL_RESOURCES_OPT="--local_resources"
            LOCAL_RESOURCES=$2
            shift
            shift
            ;;
        "-help"|"--help"|"-h"|"-?")
            usage 0
            ;;
        *)
            echo "ERROR: Unknown option \"$1\""
            usage
            ;;
    esac
done

if [ "$BASE_CONTAINER" = "" ]; then
    BASE_CONTAINER="nvidia/cuda:${CUDA_VERSION}-cudnn7-devel-ubuntu${UBUNTU_BASE_VERSION}"
fi

# check to make sure that if we're running the build in the background, we're skipping the packaging.
if [ "$DOCKER_RUN_OPT" = "-d" ]; then
    if [ "$SKIPP" != "true" ]; then
        echo "ERROR: You cannot background the build without also skipping the packaging by specifying --skip-packaging."
        usage
    fi
fi

CONTAINER_NAME=tensorflow_${TENSORFLOW_VERSION}_build

# Can we run docker
SUDO=
if [ "$(whoami)" != "root" ]; then
    # Are we in the docker group?
    set +e
    CAN_RUN_DOCKER="$(groups | grep docker)"
    set -e

    if [ "$CAN_RUN_DOCKER" = "" ]; then
	SUDO=sudo
    else
	echo "Assuming that you can run 'docker' without sudo since you're in the 'docker' group."
    fi
fi

set +e
$SUDO type docker >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "ERROR: Can't seem to locate docker. Is it installed?"
    exit 1
fi
set -e

# See if the container exists
RUNNING=$($SUDO docker ps -q --filter=name=$CONTAINER_NAME)

if [ "$RUNNING" != "" ]; then
    echo "ERROR: There's currently a build running for building tensorflow $TENSORFLOW_VERSION. Please stop that build before running another one."
    exit 1
fi

# move the files we're going to map into the container into target since there will also be
#  files written there once the build finishes.
if [ -d "$WORKING_DIRECTORY" ]; then
    # it's possible that this fails because it has files owned by root
    set +e
    rm -rf "$WORKING_DIRECTORY" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Need to remove the working directory using sudo." | tee -a "$WORKING_DIRECTORY"/build.out
        sudo rm -rf "$WORKING_DIRECTORY" >/dev/null 2>&1
    fi
    set -e
fi

# set absolute reference to the WORKING_DIRECTORY
mkdir -p "$WORKING_DIRECTORY"
cd "$WORKING_DIRECTORY"
ABS_WORKING_DIR="$(pwd -P)"
cd - >/dev/null

# Remove the build.out file and recreate it empty
if [ -f "$WORKING_DIRECTORY"/build.out ]; then
    rm "$WORKING_DIRECTORY"/build.out
fi
touch "$WORKING_DIRECTORY"/build.out

# set absolute reference to the SCRIPT_DIR
cd "$SCRIPT_DIR"
ABS_SCRIPT_DIR="$(pwd -P)"
cd - >/dev/null

BUILD_IMAGE="$CONTAINER_NAME"
BUILD_CONTAINER="$CONTAINER_NAME"ing

if [ "$JUST_BUILD" != "true" ]; then
    # if there's a saved off prevous build prep, then we need to remove
    # that container.
    removeContainer "$CONTAINER_NAME"

    $SUDO docker run --runtime=nvidia $DOCKER_RUN_OPT --name="$CONTAINER_NAME" \
          -v "$ABS_SCRIPT_DIR":"$IC_SCRIPT_DIR" \
          -v "$ABS_WORKING_DIR":"$IC_WORKING_DIR" \
          -e TENSORFLOW_DEBUG_SYMBOLS=$TENSORFLOW_DEBUG_SYMBOLS \
          -e TENSORFLOW_VERSION=$TENSORFLOW_VERSION \
          -e TENSORFLOW_COMPUTE_CAPS=$TENSORFLOW_COMPUTE_CAPS \
          -e LOCAL_RESOURCES=$LOCAL_RESOURCES \
          -e LOCAL_RESOURCES_OPT=$LOCAL_RESOURCES_OPT \
          -e BAZEL_VERSION=$BAZEL_VERSION \
          -e BUILD_PHASES="dosetup" \
          $BASE_CONTAINER "$IC_SCRIPT_DIR"/build-tensorflow.sh "$IC_WORKING_DIR" | tee -a "$WORKING_DIRECTORY"/build.out

    # now we will build an image from the current container state.
    echo "Saving off prepared container..." | tee -a "$WORKING_DIRECTORY"/build.out
    $SUDO docker commit "$CONTAINER_NAME" "$BUILD_IMAGE"
    echo "...done." | tee -a "$WORKING_DIRECTORY"/build.out
fi

# check if the image exists
if [ "$(docker images | egrep "^$BUILD_IMAGE ")" = "" ]; then
    echo "ERROR: The prepared image for building isn't available. Please run without the --just-build flag" | tee -a "$WORKING_DIRECTORY"/build.out
    exit 1
fi

removeContainer "$BUILD_CONTAINER"
$SUDO docker run --runtime=nvidia $DOCKER_RUN_OPT --name="$BUILD_CONTAINER" \
      -v "$ABS_SCRIPT_DIR":"$IC_SCRIPT_DIR" \
      -v "$ABS_WORKING_DIR":"$IC_WORKING_DIR" \
      -e TENSORFLOW_CUDA_VERSION=$CUDA_VERSION \
      -e TENSORFLOW_DEBUG_SYMBOLS=$TENSORFLOW_DEBUG_SYMBOLS \
      -e TENSORFLOW_VERSION=$TENSORFLOW_VERSION \
      -e TENSORFLOW_COMPUTE_CAPS=$TENSORFLOW_COMPUTE_CAPS \
      -e LOCAL_RESOURCES=$LOCAL_RESOURCES \
      -e LOCAL_RESOURCES_OPT=$LOCAL_RESOURCES_OPT \
      -e BAZEL_VERSION=$BAZEL_VERSION \
      -e BUILD_PHASES="doconfigure,dobuild-python,docleanup" \
      "$BUILD_IMAGE" "$IC_SCRIPT_DIR"/build-tensorflow.sh "$IC_WORKING_DIR" | tee -a "$WORKING_DIRECTORY"/build.out

removeContainer "$BUILD_CONTAINER"
$SUDO docker run --runtime=nvidia $DOCKER_RUN_OPT --name="$BUILD_CONTAINER" \
      -v "$ABS_SCRIPT_DIR":"$IC_SCRIPT_DIR" \
      -v "$ABS_WORKING_DIR":"$IC_WORKING_DIR" \
      -e TENSORFLOW_CUDA_VERSION=$CUDA_VERSION \
      -e TENSORFLOW_DEBUG_SYMBOLS=$TENSORFLOW_DEBUG_SYMBOLS \
      -e TENSORFLOW_VERSION=$TENSORFLOW_VERSION \
      -e TENSORFLOW_COMPUTE_CAPS=$TENSORFLOW_COMPUTE_CAPS \
      -e LOCAL_RESOURCES=$LOCAL_RESOURCES \
      -e LOCAL_RESOURCES_OPT=$LOCAL_RESOURCES_OPT \
      -e BAZEL_VERSION=$BAZEL_VERSION \
      -e BUILD_PHASES="doconfigure,dobuild-java,docleanup" \
      "$BUILD_IMAGE" "$IC_SCRIPT_DIR"/build-tensorflow.sh "$IC_WORKING_DIR" | tee -a "$WORKING_DIRECTORY"/build.out

if [ "$SKIPP" != "true" ]; then
    ./package.sh $OFFLINE -w "$WORKING_DIRECTORY" $DEPLOY_ME | tee -a "$WORKING_DIRECTORY"/build.out
fi

