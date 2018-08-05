FROM ubuntu:16.04

# versions of packages
ENV BUILD_THIRDPARTY=1
ENV EMCC_WASM_BACKEND=0
ENV EMCC_DEBUG=0
ENV PROJ_VERSION=4.9.3
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
RUN bash -c "source /emsdk/emsdk_env.sh && cd /gdal-2.3.1/gdal && emconfigure ./configure --enable-static --enable-pdf-plugin=no --with-dods-root=no --with-freexl=no --with-geotiff=internal --with-libjson-c=internal --with-libtiff=internal --with-libz=internal --with-jpeg=internal --with-static-proj=/proj.4-$PROJ_VERSION --with-openjpeg=/openjpeg-2.3.0 --without-armadillo --without-bsb --without-cfitsio --without-cryptopp --without-curl --without-dds --without-ecw --without-epsilon --without-expat --without-fgdb --without-fme --without-geos --without-gif --without-grass --without-grib --without-gta --without-hdf4 --without-hdf5 --without-idb --without-ingres --without-jasper --without-java --without-jp2mrsid --without-jpeg12 --without-kakadu --without-kea --without-libkml --without-ld-shared --without-libgrass --without-libiconv-prefix --without-liblzma --without-libtool --without-mdb --without-mongocxx --without-mrf --without-mrsid --without-mrsid_lidar --without-msg --without-mysql --without-netcdf --without-oci --without-oci-include --without-oci-lib --without-odbc --without-ogdi --without-pam --without-pcraster --without-pcre --without-pdfium --without-perl --without-pg --without-php --without-podofo --without-poppler --without-python --without-qhull --without-rasdaman --without-sde --without-sosi --without-spatialite --without-sqlite3 --without-threads --without-webp --without-xerces --without-xml2"

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
RUN ls /gdal-2.3.1/gdal/libgdal.a


##############
# Compile JS #
##############

# compile into JavaScript
RUN ./emsdk/emscripten/1.38.11/emcc /gdal-2.3.1/gdal/libgdal.a /proj.4-$PROJ_VERSION/src/.libs/libproj.a /openjpeg-2.3.0/bin/libopenjp2.a -o gdal.js \
    --memory-init-file 0 \
    -s TOTAL_MEMORY=256MB \
    -s WASM=0 \
    -s DEMANGLE_SUPPORT=1 \
    -s NO_EXIT_RUNTIME=1 \
    -s RESERVED_FUNCTION_POINTERS=20 \
    -s FORCE_FILESYSTEM=1 \
    -s FS_LOG=1 \
    -s EXPORTED_FUNCTIONS='["_GDALAllRegister", "_GDALOpen", "_GDALClose", "_GDALGetRasterXSize"]' \
    -s EXTRA_EXPORTED_RUNTIME_METHODS='["ccall", "cwrap"]' \
    -s ASSERTIONS=1 \
    -s VERBOSE=0
