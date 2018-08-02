#!/bin/bash

# =============================================================================
# Preamble
# =============================================================================
set -e
MAIN_DIR="$(dirname "$0")"
cd "$MAIN_DIR"
SCRIPTDIR="$(pwd -P)"
# =============================================================================

usage() {
    echo "[MVN=/path/to/mvn/mvn] $0 [options]" 
    echo " Options:"
    echo "    -v:  tensorflow version. e.g. \"-v 1.9.0\" This defaults to $TENSORFLOW_VERSION"
    echo "    -w:  working directory, where the final container files will be written. This defaults"
    echo "           to a subdirectory called \"installed/container\" of the directory the script is in."
    echo "    -c:  tensorflow compute caps to build. E.g. \"-c \" This defaults to $TENSORFLOW_COMPUTE_CAPS"
    echo "           NOTE: this is NOT the tensorflow build defaut. 1.8.0 and 1.9.0 tensorflow default"
    echo "           compute caps are \"3.5,5.2\". To build these specifcy \"-c '3.5,5.2'\""
    echo "    -b:  bazel version to build tensorflow with. e.g. \"-b 0.15.2\" This defaults to $BAZEL_VERSION"
    echo "    --container=$BASE_CONTAINER : use the named container. The default is shown."
    echo "    -g:  compile TensorFlow with debug symbols."
    echo ""
    echo "    if MVN isn't set then the script assumes \"mvn\" is on the command line PATH"

    if [ $# -gt 0 ]; then
        exit $1
    else
        exit 1
    fi
}

TENSORFLOW_VERSION=1.9.0
TENSORFLOW_COMPUTE_CAPS="5.0,6.1"
BAZEL_VERSION=0.15.2
CUDA_VERSION=9.2
WORKING_DIRECTORY="$SCRIPTDIR"/installed/container
#WORKING_DIRECTORY=/tmp/container
BASE_CONTAINER="nvidia/cuda:9.2-cudnn7-devel-ubuntu18.04"
TENSORFLOW_DEBUG_SYMBOLS=

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
        "-help"|"--help"|"-h"|"-?")
            usage 0
            ;;
        *)
            echo "ERROR: Unknown option \"$1\""
            usage
            ;;
    esac
done

CONTAINER_NAME=tensorflow_${TENSORFLOW_VERSION}_build

# Are we in the docker group?
CAN_RUN_DOCKER="$(groups | grep docker)"

SUDO=
if [ "$CAN_RUN_DOCKER" = "" ]; then
    SUDO=sudo
else
    echo "Assuming that you can run 'docker' without sudo since you're in the 'docker' group."
fi

cd "$WORKING_DIRECTORY"
ABS_WORKING_DIR="$(pwd -P)"
cd -

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

WAS_RUNNING=$($SUDO docker ps -aq --filter=name=$CONTAINER_NAME)
if [ "$WAS_RUNNING" != "" ]; then
    echo "Removing previous container that's no longer running."
    $SUDO docker rm $CONTAINER_NAME
fi

# move the files we're going to map into the container into target since there will also be
#  files written there once the build finishes.
if [ -d "$WORKING_DIRECTORY" ]; then
    # it's possible that this fails because it has files owned by root
    set +e
    rm -rf "$WORKING_DIRECTORY" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Need to remove the working directory using sudo."
        sudo rm -rf "$WORKING_DIRECTORY" >/dev/null 2>&1
    fi
    set -e
fi

mkdir -p "$WORKING_DIRECTORY"
cp -r container-files/* "$WORKING_DIRECTORY"

$SUDO docker run --runtime=nvidia -it --name="$CONTAINER_NAME" \
       -v "$ABS_WORKING_DIR":/tmp/files \
       -e TENSORFLOW_DEBUG_SYMBOLS=$TENSORFLOW_DEBUG_SYMBOLS \
       -e TENSORFLOW_VERSION=$TENSORFLOW_VERSION \
       -e TENSORFLOW_COMPUTE_CAPS=$TENSORFLOW_COMPUTE_CAPS \
       -e BAZEL_VERSION=$BAZEL_VERSION \
       $BASE_CONTAINER /tmp/files/build-tensorflow.sh

./package.sh
