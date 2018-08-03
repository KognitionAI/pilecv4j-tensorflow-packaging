#!/bin/bash -x

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
    echo ""
    echo "    -g:  compile TensorFlow with debug symbols."
    echo "    --container=$BASE_CONTAINER : use the named container. The default is shown."
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

SKIPP=
TENSORFLOW_VERSION=1.9.0
TENSORFLOW_COMPUTE_CAPS="5.0,6.1"
BAZEL_VERSION=0.15.2
CUDA_VERSION=9.2
WORKING_DIRECTORY="$SCRIPTDIR"/installed/container
#WORKING_DIRECTORY=/tmp/container
BASE_CONTAINER="nvidia/cuda:9.2-cudnn7-devel-ubuntu18.04"
TENSORFLOW_DEBUG_SYMBOLS=
LOCAL_RESOURCES_OPT=
LOCAL_RESOURCES=
DOCKER_RUN_OPT="-it"
JUST_BUILD=

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
        "-sp"|"--skip-packaging")
            SKIPP=true
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

# check to make sure that if we're running the build in the background, we're skipping the packaging.
if [ "$DOCKER_RUN_OPT" = "-d" ]; then
    if [ "$SKIPP" != "true" ]; then
        echo "ERROR: You cannot background the build without also skipping the packaging by specifying --skip-packaging."
        usage
    fi
fi


CONTAINER_NAME=tensorflow_${TENSORFLOW_VERSION}_build

# Are we in the docker group?
CAN_RUN_DOCKER="$(groups | grep docker)"

SUDO=
if [ "$CAN_RUN_DOCKER" = "" ]; then
    SUDO=sudo
else
    echo "Assuming that you can run 'docker' without sudo since you're in the 'docker' group."
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
        echo "Need to remove the working directory using sudo."
        sudo rm -rf "$WORKING_DIRECTORY" >/dev/null 2>&1
    fi
    set -e
fi

mkdir -p "$WORKING_DIRECTORY"
cd "$WORKING_DIRECTORY"
ABS_WORKING_DIR="$(pwd -P)"
cd -

cp -r container-files/* "$WORKING_DIRECTORY"

BUILD_IMAGE="$CONTAINER_NAME"
BUILD_CONTAINER="$CONTAINER_NAME"ing

if [ "$JUST_BUILD" != "true" ]; then
    # if there's a saved off prevous build prep, then we need to remove
    # that container.
    removeContainer "$BUILD_CONTAINER"
    removeContainer "$CONTAINER_NAME"

    $SUDO docker run --runtime=nvidia $DOCKER_RUN_OPT --name="$CONTAINER_NAME" \
          -v "$ABS_WORKING_DIR":/tmp/files \
          -e TENSORFLOW_DEBUG_SYMBOLS=$TENSORFLOW_DEBUG_SYMBOLS \
          -e TENSORFLOW_VERSION=$TENSORFLOW_VERSION \
          -e TENSORFLOW_COMPUTE_CAPS=$TENSORFLOW_COMPUTE_CAPS \
          -e LOCAL_RESOURCES=$LOCAL_RESOURCES \
          -e LOCAL_RESOURCES_OPT=$LOCAL_RESOURCES_OPT \
          -e BAZEL_VERSION=$BAZEL_VERSION \
          -e BUILD_PHASES="dosetup" \
          $BASE_CONTAINER /tmp/files/build-tensorflow.sh

    # now we will build an image from the current container state.
    echo "Saving off prepared container..."
    $SUDO docker commit "$CONTAINER_NAME" "$BUILD_IMAGE"
    echo "...done."
fi

# check if the image exists
if [ "$(docker images | egrep "^$BUILD_IMAGE ")" = "" ]; then
    echo "ERROR: The prepared image for building isn't available. Please run without the --just-build flag"
    exit 1
fi

removeContainer "$BUILD_CONTAINER"
$SUDO docker run --runtime=nvidia $DOCKER_RUN_OPT --name="$BUILD_CONTAINER" \
      -v "$ABS_WORKING_DIR":/tmp/files \
      -e TENSORFLOW_DEBUG_SYMBOLS=$TENSORFLOW_DEBUG_SYMBOLS \
      -e TENSORFLOW_VERSION=$TENSORFLOW_VERSION \
      -e TENSORFLOW_COMPUTE_CAPS=$TENSORFLOW_COMPUTE_CAPS \
      -e LOCAL_RESOURCES=$LOCAL_RESOURCES \
      -e LOCAL_RESOURCES_OPT=$LOCAL_RESOURCES_OPT \
      -e BAZEL_VERSION=$BAZEL_VERSION \
      -e BUILD_PHASES="doconfigure,dobuild,docleanup" \
      "$BUILD_IMAGE" /tmp/files/build-tensorflow.sh

if [ "$SKIPP" != "true" ]; then
    ./package.sh
fi

