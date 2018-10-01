#!/bin/bash

# =============================================================================
# Preamble
# =============================================================================
set -e

# what directory is mounted. It contains other files.
MAIN_DIR="$(dirname "$0")"
cd "$MAIN_DIR"
SCRIPTDIR="$(pwd -P)"
# =============================================================================

OUTPUT_DIR="$1"

if [ ! -d "$OUTPUT_DIR" ]; then
    echo "ERROR: The given working directory isn't mapped into the container correctly. It should be at \"$OUTPUT_DIR\""
    exit 1
fi

echo "Running from \"$SCRIPTDIR\" which also contains:"
ls "$SCRIPTDIR" | cat
set +e


# pertinent environment variables
test "$TENSORFLOW_VERSION" = "" && TENSORFLOW_VERSION=1.9.0
test "$TENSORFLOW_COMPUTE_CAPS" = "" && TENSORFLOW_COMPUTE_CAPS="5.0,6.1"
test "$BAZEL_VERSION" = "" && BAZEL_VERSION=0.15.2
test "$BUILD_PHASES" = "" && BUILD_PHASES="dosetup,doconfigure,dobuild,docleanup"

# fail on any error
set -e

if [ "$(echo "$BUILD_PHASES" | grep dosetup)" != "" ]; then
    echo "Setting up the container for the build."
    # prep the directories. Might as well fail now if I can't write them
    echo "$TENSORFLOW_VERSION" > "$OUTPUT_DIR"/tensorflow.version
    mkdir -p /opt

    # These commands are transliterated from a pom.xml file (read: maven Dockerfile)

    test "`ldconfig -p | grep libcuda.so`" = "" && echo "This container is not being built using nvidia-docker. Please see the README for details"; test true
    test "`ldconfig -p | grep libcuda.so`" != ""
    
    # Install dependencies
    apt-get update
    apt-get upgrade -y
    apt-get install -y git wget

    # before we go too far, let's make sure we can get the specified tensorflow
    # Checkout tensorflow
    mkdir -p /opt
    cd /opt
    git clone https://github.com/tensorflow/tensorflow
    cd tensorflow
    git checkout v$TENSORFLOW_VERSION

    # make sure we can pull the bazel version specified
    cd /tmp
    echo "Getting bazel $BAZEL_VERSION"
    wget -q https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-installer-linux-x86_64.sh
    cd -

    # continue installing more dependencies
    apt-get install -y build-essential curl pkg-config python3-dev unzip zip
    apt-get install -y openjdk-8-jdk
    apt-get install -y python3-numpy python3-dev python3-pip python3-wheel

    # Build the sample cuda program "deviceQuery"
    cd /
    tar -xvf "$SCRIPTDIR"/device_query.tar.gz
    #rm "$SCRIPTDIR"/device_query.tar.gz <- don't remove, this is a mounted file
    cd /usr/local/cuda-9.2/samples/1_Utilities/deviceQuery/
    make
    ./deviceQuery

    # Hack make python use python3
    ln -s /usr/bin/python3 /usr/bin/python

    # Hack, fix assumptions tensorflow build makes about NCCL installation
    mkdir /usr/local/cuda-9.2/nccl
    ln -s /usr/include /usr/local/cuda-9.2/nccl/include
    ln -s /usr/lib/x86_64-linux-gnu /usr/local/cuda-9.2/nccl/lib
    cp "$SCRIPTDIR"/NCCL-SLA.txt /usr/local/cuda-9.2/nccl

    # Install bazel using the installer
    cd /tmp
    chmod +x bazel-$BAZEL_VERSION-installer-linux-x86_64.sh
    ./bazel-$BAZEL_VERSION-installer-linux-x86_64.sh
    rm bazel-$BAZEL_VERSION-installer-linux-x86_64.sh

    # Needed for (apparently) 1.10 and (certainly) 1.11
    pip3 install keras_applications==1.0.4 --no-deps
    pip3 install keras_preprocessing==1.0.2 --no-deps
    pip3 install h5py==2.8.0
else
    echo "Skipping the setup."
fi

if [ "$(echo "$BUILD_PHASES" | grep doconfigure)" != "" ]; then
    echo "Configuring TensorFlow."
    # Prepare to build tensorflow
    cd /opt/tensorflow

    # Set up all environment variables that allow the configure to run without being interactive

    # 1.9.0 uses TF_NEED_S3. 1.10.0 uses TF_NEED_AWS
    export TF_NEED_S3=0
    export TF_NEED_AWS=$TF_NEED_S3
    
    export TF_NEED_GCP=0
    export TF_NEED_HDFS=0
    export TF_NEED_JEMALLOC=0
    export TF_NEED_KAFKA=1
    export TF_NEED_OPENCL=0
    export TF_NEED_COMPUTECPP=1
    export TF_NEED_OPENCL=0
    export TF_CUDA_CLANG=0
    export TF_NEED_TENSORRT=0
    export PYTHONPATH=/usr/bin/python3
    export PYTHON_BIN_PATH="$PYTHONPATH"
    export USE_DEFAULT_PYTHON_LIB_PATH=1
    export TF_ENABLE_XLA=0
    export TF_NEED_GDR=0
    export TF_NEED_VERBS=0
    export TF_NEED_OPENCL_SYCL=0
    export TF_NEED_CUDA=1
    export TF_CUDA_VERSION=9.2
    export CUDA_PATH=/usr/local/cuda-9.2
    export CUDA_TOOLKIT_PATH="$CUDA_PATH"
    export TF_CUDNN_VERSION=7.1
    export CUDNN_INSTALL_PATH="$CUDA_TOOLKIT_PATH"
    export TF_NCCL_VERSION=2.2.13
    export NCCL_INSTALL_PATH="$CUDA_TOOLKIT_PATH"/nccl
    export TF_CUDA_COMPUTE_CAPABILITIES="$TENSORFLOW_COMPUTE_CAPS"
    export GCC_HOST_COMPILER_PATH=/usr/bin/gcc
    export TF_NEED_MPI=0
    export CC_OPT_FLAGS="-march=native"
    export TF_SET_ANDROID_WORKSPACE=0

    # Help the linker
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/extras/CUPTI/lib64

    # added in 1.11
    export TF_NEED_NGRAPH=0

    ./configure
else
    echo "Skipping TensorFlow configuration."
fi

if [ "$(echo "$BUILD_PHASES" | grep dobuild)" != "" ]; then
    # "--copt=-O -c dbg -c opt" <- these are debug options
    DEBUG_OPTIONS=
    if [ "$TENSORFLOW_DEBUG_SYMBOLS" = "true" ]; then
        echo "Building TensorFlow with debug symbols."
        DEBUG_OPTIONS="--copt=-O -c dbg -c opt"
    fi
    echo "bazel build $DEBUG_OPTIONS $LOCAL_RESOURCES_OPT $LOCAL_RESOURCES --config=opt --config=cuda --config=monolithic //tensorflow/tools/pip_package:build_pip_package //tensorflow/java:tensorflow //tensorflow/java:libtensorflow_jni"

    if [ "$JUST_PREPARE_IMAGE" ]; then
        exit 0
    fi

    bazel build $DEBUG_OPTIONS --config=opt --config=cuda --config=monolithic $LOCAL_RESOURCES_OPT $LOCAL_RESOURCES //tensorflow/tools/pip_package:build_pip_package //tensorflow/java:tensorflow //tensorflow/java:libtensorflow_jni

    # Build the python packages and install them
    ./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
    pip3 install /tmp/tensorflow_pkg/tensorflow-*.whl

    # prep the directories in case we restarted since the setup. 
    echo "$TENSORFLOW_VERSION" > "$OUTPUT_DIR"/tensorflow.version

    # collect the results and put them outside of the container
    cp /tmp/tensorflow_pkg/tensorflow-*.whl "$OUTPUT_DIR"
    cp /opt/tensorflow/bazel-bin/tensorflow/java/libtensorflow.jar "$OUTPUT_DIR"
    cp /opt/tensorflow/bazel-bin/tensorflow/java/libtensorflow_jni.so "$OUTPUT_DIR"
    cp /usr/local/cuda-9.2/samples/1_Utilities/deviceQuery/deviceQuery "$OUTPUT_DIR"
fi

if [ "$(echo "$BUILD_PHASES" | grep docleanup)" != "" ]; then
    apt-get clean
    apt-get autoclean

    rm -rf /tmp/tensorflow_pkg
fi

