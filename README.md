# Tensorflow build and package for java

This project will allow you to build from scratch, package into a jar file, and install into the local maven repository, a [TensorFlow](https://www.tensorflow.org/) distribution's Java extensions built for the GPU. It will also package the `JNI` native libraries, along with the entire native [TensorFlow](https://www.tensorflow.org/) libraries, into a jar file that can be retrieved using `ai.kognition.pilecv4j.utils.NativeLibrary`.

__* Note: This currently ONLY builds a 64-bit linux (Ubuntu) install using [Docker](https://www.docker.com/). *__

## Prerequisites

To run the build, you will need to have an NVidia GPU with the drivers installed. 

This install script executes the build using a [Docker](https://www.docker.com/) container that's already set up with the appropriate [CUDA](https://developer.nvidia.com/cuda-zone) NVidia libraries, so you don't need to install all of that on your machine to get it to build. However, you wont be able to run an program you write against this [TensorFlow](https://www.tensorflow.org/) build without having the appropriate version of [CUDA](https://developer.nvidia.com/cuda-zone) installed on your environment. The easiest way to do this will be to run whatever you build in a [Docker](https://www.docker.com/) container that's alread set up with these things.

All of this means basically there's two more prerequisites:

1. You'll need [Docker](https://www.docker.com/) installed
1. You'll need the NVidia Docker runtime, [`nvidia-docker`](https://github.com/NVIDIA/nvidia-docker) installed

## Building

By default the container used for the build has Ubuntu 18.04, CUDA 9.2, and CUDNN 7. If you want something different you can modify these scripts and supply a different base container from [NVidia's Docker images in the docker.io registry](https://hub.docker.com/r/nvidia/cuda/). I can't guarantee that the build will work with a different setup and so just changing the script may not be the only change necessary. As it is, [it works on my machine](https://blog.codinghorror.com/the-works-on-my-machine-certification-program/).
