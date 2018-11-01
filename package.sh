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
    echo "  --offline : Pass -O to maven."
    exit 1
}

if [ "$MVN" = "" ]; then
    MVN=mvn
fi

WORKING_DIRECTORY=/tmp/tensorflow
MVN_TARGET=install
MVN_OFFLINE=
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
        "--offline")
            MVN_OFFLINE=-o
            shift
            ;;
        *)
            usage
            ;;
    esac
done

if [ ! -f "$WORKING_DIRECTORY"/tensorflow.version ]; then
    echo "ERROR: The expected artifact from the build \"$WORKING_DIRECTORY/tensorflow.version\" is missing. Did you execute a build using \"fromscratch.sh\"?"
    exit 1
fi

TENSORFLOW_VERSION=`cat "$WORKING_DIRECTORY"/tensorflow.version`

$MVN $MVN_OFFLINE versions:set -DnewVersion=$TENSORFLOW_VERSION

$MVN $MVN_OFFLINE -Dfromscratch.working.dir="$WORKING_DIRECTORY" clean $MVN_TARGET

$MVN $MVN_OFFLINE versions:set -DnewVersion=0

