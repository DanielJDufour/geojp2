FROM ubuntu:16.04

# versions of packages
ENV BUILD_THIRDPARTY=1
ENV EMCC_WASM_BACKEND=0
ENV EMCC_DEBUG=0
ENV PROJ_VERSION=5.1.0
ENV OPENJPEG_VERSION=v2.3.0
ENV GDAL_VERSION=v2.3.1
ENV USE_OPENJPEG=1
ENV ASM_JS=1
ENV LLVM_ROOT='/myfastcomp/emscripten-fastcomp/build/bin'

############
# DOWNLOAD #
############

RUN apt-get update && apt-get -y install \
    build-essential \
    cmake \
    autoconf \
    python \
    python \
    nodejs \
    default-jre \
    liblcms2-dev \
    libpng-dev \
    libtiff5-dev \
    libtool \
    curl \
    git-core \
    vim \
    wget \
    zlib1g-dev \
    zip

# download emsdk
RUN wget --quiet https://github.com/juj/emsdk/archive/master.zip && \
  unzip -q master.zip && \
  mv emsdk-master emsdk && \
  rm master.zip

# download openjpeg
RUN wget --quiet https://github.com/uclouvain/openjpeg/archive/$OPENJPEG_VERSION.zip && unzip -q $OPENJPEG_VERSION.zip && rm $OPENJPEG_VERSION.zip

# download proj4
RUN wget --quiet https://github.com/OSGeo/proj.4/archive/$PROJ_VERSION.zip && unzip -q $PROJ_VERSION.zip && rm $PROJ_VERSION.zip

# download gdal
RUN wget --quiet https://github.com/OSGeo/gdal/archive/$GDAL_VERSION.zip && \
    unzip -q $GDAL_VERSION.zip && \
    rm $GDAL_VERSION.zip

RUN ls /gdal-2.3.1/gdal

###################
# Build & Install #
###################

# build emsdk
RUN bash -c "cd emsdk && ./emsdk update && ./emsdk install latest && ./emsdk activate latest"

RUN ls /emsdk/emscripten/1.38.11/tests

# validate the environment
RUN bash -c "source /emsdk/emsdk_env.sh && emcc /emsdk/emscripten/1.38.11/tests/hello_world.cpp"

# get emcc information
RUN bash -c "source /emsdk/emsdk_env.sh && emcc -v"

# build proj4
RUN bash -c "source /emsdk/emsdk_env.sh && cd proj.4-$PROJ_VERSION && ./autogen.sh && ./configure --enable-shared=no --enable-static --without-mutex && make -j4 && make install"

# build openjpeg
RUN bash -c "source /emsdk/emsdk_env.sh && cd openjpeg-2.3.0 && cmake . && make -j4 && make install"

#####################
# Compile into LLVM #
#####################

# suppress erroneously failing test
RUN sed -i '/long long not found/c\$as_echo "#define HAVE_LONG_LONG 1" >>confdefs.h' /gdal-2.3.1/gdal/configure 

# emconfigure gdal
RUN bash -c "source /emsdk/emsdk_env.sh && cd /gdal-2.3.1/gdal && emconfigure ./configure"

RUN ls /gdal-2.3.1/gdal

# compile proj4 into LLVM
RUN bash -c "source /emsdk/emsdk_env.sh && cd proj.4-$PROJ_VERSION && ./autogen.sh && emconfigure ./configure --enable-shared=no --enable-static --without-mutex && emmake make -j4"

# check if above succeeded
RUN ls /proj.4-$PROJ_VERSION/src/.libs/libproj.a

# compile openjpeg into LLVM
# emmake make doesn't have a target
RUN bash -c "source /emsdk/emsdk_env.sh && cd /openjpeg-2.3.0 && mkdir build && cd build && emconfigure cmake .. -DCMAKE_BUILD_TYPE=Release"

# check if above succeeded
RUN ls /openjpeg-2.3.0/bin/libopenjp2.a

# compile gdal into LLVM
RUN bash -c "source /emsdk/emsdk_env.sh && cd /gdal-2.3.1/gdal && emmake make -j4 lib-target"

# check if above succeeded
RUN ls /gdal-2.3.1/gdal
RUN ls /gdal-2.3.1/gdal/libgdal.a


##############
# Compile JS #
##############

# compile into JavaScript
RUN bash -c "source /emsdk/emsdk_env.sh && \
    emcc /gdal-2.3.1/libgdal.a /proj.4-4.9.3/src/.libs/libproj.a /openjpeg-version.2.0/build/bin/libopenjp2.a \
    -g \
    -o gdal.js \
    --memory-init-file 0 \
    -s TOTAL_MEMORY=256MB \
    -s WASM=0 \
    -s NO_EXIT_RUNTIME=1 \
    -s RESERVED_FUNCTION_POINTERS=20 \
    -s FORCE_FILESYSTEM=1 \
    -s FS_LOG=1 \
    -s ASSERTIONS=1 \
    -s VERBOSE=1 \
    -s DISABLE_EXCEPTION_CATCHING=0 \
    -s SAFE_HEAP=1"