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
    echo "usage: [MVN=[path to maven]] ./package.sh [-r] [-w fromscratch/working/directory]"
    echo "    if MVN isn't set then the script assumes \"mvn\" is on the command line PATH"
    echo ""
    echo "  -w        : The working directory given to fromscratch.sh. This defaults."
    echo "  --deploy  : do a \"mvn deploy\" as part of building."
    exit 1
}

if [ "$MVN" = "" ]; then
    MVN=mvn
fi

WORKING_DIRECTORY=$SCRIPTDIR/installed/container
MVN_TARGET=install
while [ $# -gt 0 ]; do
    case "$1" in
        "-w")
            WORKING_DIRECTORY=$2
            shift
            shift
            ;;
        "--deploy")
            MVN_TARGET=deploy
            shift
            ;;
        *)
            usage
            ;;
    esac
done

CONTAINER_DIR="$WORKING_DIRECTORY"/target/bin

if [ ! -f "$CONTAINER_DIR"/tensorflow.version ]; then
    echo "ERROR: The expected artifact from the build \"$CONTAINER_DIR/tensorflow.version\" is missing. Did you execute a build using \"fromscratch.sh\"?"
    exit 1
fi

TENSORFLOW_VERSION=`cat "$CONTAINER_DIR"/tensorflow.version`

$MVN versions:set -DnewVersion=$TENSORFLOW_VERSION

$MVN -Dfromscratch.working.dir="$WORKING_DIRECTORY" clean $MVN_TARGET

$MVN versions:set -DnewVersion=0

