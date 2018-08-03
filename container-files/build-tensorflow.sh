#!/bin/bash

set -e

# what directory is mounted. It contains other files.
MAIN_DIR="$(dirname "$0")"
cd "$MAIN_DIR"
SCRIPTDIR="$(pwd -P)"

echo "Running from \"$SCRIPTDIR\" which also contains:"
ls "$SCRIPTDIR" | cat
set +e


# pertinent environment variables
test "$TENSORFLOW_VERSION" = "" && TENSORFLOW_VERSION=1.9.0
test "$TENSORFLOW_COMPUTE_CAPS" = "" && TENSORFLOW_COMPUTE_CAPS="5.0,6.1"
test "$BAZEL_VERSION" = "" && BAZEL_VERSION=0.15.2
test "$CONTAINER_BUILD_TARGET_DIRECTORY" = "" && CONTAINER_BUILD_TARGET_DIRECTORY=$SCRIPTDIR/target/bin

# fail on any error
set -e

# prep the directories. Might as well fail now if I can't write them
mkdir -p "$CONTAINER_BUILD_TARGET_DIRECTORY"
echo "$TENSORFLOW_VERSION" > "$CONTAINER_BUILD_TARGET_DIRECTORY"/tensorflow.version
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

# Prepare to build tensorflow
cd /opt/tensorflow

# Set up all environment variables that allow the configure to run without being interactive
export TF_NEED_S3=0
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

./configure

# "--copt=-O -c dbg -c opt" <- these are debug options
DEBUG_OPTIONS=
if [ "$TENSORFLOW_DEBUG_SYMBOLS" = "true" ]; then
    echo "Building TensorFlow with debug symbols."
    DEBUG_OPTIONS="--copt=-O -c dbg -c opt"
fi
echo "bazel build $DEBUG_OPTIONS $LOCAL_RESOURCES_OPT $LOCAL_RESOURCES --config=opt --config=cuda --config=monolithic //tensorflow/tools/pip_package:build_pip_package //tensorflow/java:tensorflow //tensorflow/java:libtensorflow_jni"
bazel build $DEBUG_OPTIONS $LOCAL_RESOURCES_OPT $LOCAL_RESOURCES --config=opt --config=cuda --config=monolithic //tensorflow/tools/pip_package:build_pip_package //tensorflow/java:tensorflow //tensorflow/java:libtensorflow_jni

# Build the python packages and install them
./bazel-bin/tensorflow/tools/pip_package/build_pip_package /tmp/tensorflow_pkg
pip3 install /tmp/tensorflow_pkg/tensorflow-*.whl
apt-get clean
apt-get autoclean

# collect the results and put them outside of the container
cp /tmp/tensorflow_pkg/tensorflow-*.whl "$CONTAINER_BUILD_TARGET_DIRECTORY"
cp /opt/tensorflow/bazel-bin/tensorflow/java/libtensorflow.jar "$CONTAINER_BUILD_TARGET_DIRECTORY"
cp /opt/tensorflow/bazel-bin/tensorflow/java/libtensorflow_jni.so "$CONTAINER_BUILD_TARGET_DIRECTORY"
cp /usr/local/cuda-9.2/samples/1_Utilities/deviceQuery/deviceQuery "$CONTAINER_BUILD_TARGET_DIRECTORY"

rm -rf /tmp/tensorflow_pkg
