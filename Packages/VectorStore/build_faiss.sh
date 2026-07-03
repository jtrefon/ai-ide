#!/bin/bash
set -euo pipefail

# Build FAISS from source for macOS arm64
# Produces: Libraries/arm64/libfaiss_full.a + headers
# Depends on: cmake, libomp (brew install libomp)

FAISS_VERSION="v1.14.3"
FAISS_DIR="$(cd "$(dirname "$0")" && pwd)/.faiss_source"
LIBRARIES_DIR="$(cd "$(dirname "$0")" && pwd)/Libraries"
ARCH="arm64"
MACOSX_SDK=$(xcrun --sdk macosx --show-sdk-path)
JOBS=$(sysctl -n hw.logicalcpu)

echo "=== Building FAISS ${FAISS_VERSION} for ${ARCH} ==="

# Clean
rm -rf "${FAISS_DIR}" "${LIBRARIES_DIR}"
mkdir -p "${FAISS_DIR}" "${LIBRARIES_DIR}"

# Clone FAISS source at the tagged version (shallow clone, no history)
echo "→ Cloning FAISS ${FAISS_VERSION}..."
git clone --depth 1 --branch "${FAISS_VERSION}" \
    https://github.com/facebookresearch/faiss.git \
    "${FAISS_DIR}" 2>&1

# libomp provides OpenMP support on macOS
LIBOMP_PREFIX=$(brew --prefix libomp)

# Patch root CMakeLists.txt to skip perf_tests (avoids gflags dependency)
sed -i '' '/add_subdirectory(perf_tests)/d' "${FAISS_DIR}/CMakeLists.txt"

echo "→ Configuring CMake..."
cmake -S "${FAISS_DIR}" -B "${FAISS_DIR}/build" \
    -DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
    -DCMAKE_OSX_SYSROOT="${MACOSX_SDK}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DFAISS_ENABLE_C_API=ON \
    -DFAISS_ENABLE_PYTHON=OFF \
    -DFAISS_ENABLE_GPU=OFF \
    -DFAISS_ENABLE_EXTRAS=OFF \
    -DFAISS_ENABLE_METAL=OFF \
    -DBLA_VENDOR=Apple \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_CXX_FLAGS="-O3 -flto -I${LIBOMP_PREFIX}/include -Xclang -fopenmp" \
    -DCMAKE_C_FLAGS="-O3 -flto -I${LIBOMP_PREFIX}/include -Xclang -fopenmp" \
    -DFAISS_OPT_LEVEL=generic \
    -DOpenMP_CXX_FLAGS="-Xclang -fopenmp -I${LIBOMP_PREFIX}/include" \
    -DOpenMP_C_FLAGS="-Xclang -fopenmp -I${LIBOMP_PREFIX}/include" \
    -DOpenMP_CXX_LIB_NAMES="omp" \
    -DOpenMP_C_LIB_NAMES="omp" \
    -DOpenMP_omp_LIBRARY="${LIBOMP_PREFIX}/lib/libomp.dylib"

echo "→ Building..."
cmake --build "${FAISS_DIR}/build" -j "${JOBS}" --target faiss_c 2>&1

echo "→ Creating combined static library via libtool..."
mkdir -p "${LIBRARIES_DIR}/arm64"
libtool -static -o "${LIBRARIES_DIR}/arm64/libfaiss_full.a" \
    "${FAISS_DIR}/build/faiss/libfaiss.a" \
    "${FAISS_DIR}/build/c_api/libfaiss_c.a"

# Copy FAISS C API headers (including subdirectories like impl/)
mkdir -p "${LIBRARIES_DIR}/include/faiss/c_api"
cp -R "${FAISS_DIR}/c_api/"*.h "${FAISS_DIR}/c_api/impl" "${LIBRARIES_DIR}/include/faiss/c_api/" 2>/dev/null || true
# Also copy any impl/ directory if it exists
if [ -d "${FAISS_DIR}/c_api/impl" ]; then
    mkdir -p "${LIBRARIES_DIR}/include/faiss/c_api/impl"
    cp "${FAISS_DIR}/c_api/impl/"*.h "${LIBRARIES_DIR}/include/faiss/c_api/impl/"
fi

echo "→ Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "${LIBRARIES_DIR}/arm64/libfaiss_full.a" \
    -headers "${LIBRARIES_DIR}/include" \
    -output "${LIBRARIES_DIR}/FAISS.xcframework" 2>&1 || {
    echo "  (xcframework creation skipped; static library available below)"
}

# Cleanup source (comment out to keep for debugging)
# rm -rf "${FAISS_DIR}"

echo ""
echo "=== FAISS build complete ==="
echo "Static library: ${LIBRARIES_DIR}/arm64/libfaiss_full.a"
echo "Headers:        ${LIBRARIES_DIR}/include/"
echo "XCFramework:    ${LIBRARIES_DIR}/FAISS.xcframework"
ls -lh "${LIBRARIES_DIR}/arm64/libfaiss_full.a" 2>/dev/null || true
