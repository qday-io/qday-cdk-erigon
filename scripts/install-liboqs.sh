#!/bin/sh
# Install liboqs 0.16.x and a liboqs-go.pc so CGO can compile qday-pqc-sdk.
# Compile-time: headers + shared lib + pkg-config.
# Runtime: the same shared lib (and OpenSSL libcrypto).
set -eu

LIBOQS_VERSION="${LIBOQS_VERSION:-0.16.0}"
OQS_MINIMAL_BUILD="${OQS_MINIMAL_BUILD:-SIG_ml_dsa_44;SIG_ml_dsa_65;SIG_ml_dsa_87;SIG_falcon_512;SIG_falcon_1024;SIG_falcon_padded_512;SIG_falcon_padded_1024}"

UNAME="$(uname -s)"
jobs="$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

if [ -z "${PREFIX:-}" ]; then
	if [ "$UNAME" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
		PREFIX="$(brew --prefix)"
	else
		PREFIX="/usr/local"
	fi
fi

OPENSSL_LIB="${OPENSSL_LIB:-}"
if [ -z "$OPENSSL_LIB" ] && [ "$UNAME" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
	OPENSSL_LIB="$(brew --prefix openssl@3 2>/dev/null || true)/lib"
fi

PKG_CONFIG_DIR="${PKG_CONFIG_DIR:-$PREFIX/lib/pkgconfig}"

run_install() {
	if [ "$(id -u)" -eq 0 ] || [ -w "$PREFIX" ]; then
		"$@"
	else
		sudo "$@"
	fi
}

liboqs_present() {
	[ -f "$PREFIX/include/oqs/oqs.h" ] || return 1
	[ -e "$PREFIX/lib/liboqs.dylib" ] && return 0
	[ -e "$PREFIX/lib/liboqs.a" ] && return 0
	[ -e "$PREFIX/lib/liboqs.so" ] && return 0
	ls "$PREFIX/lib"/liboqs.so.* >/dev/null 2>&1
}

write_pc() {
	run_install mkdir -p "$PKG_CONFIG_DIR"
	pc="$PKG_CONFIG_DIR/liboqs-go.pc"
	tmp="$(mktemp)"
	{
		echo "prefix=$PREFIX"
		echo "Name: liboqs-go"
		echo "Description: Go bindings for liboqs"
		echo "Version: $LIBOQS_VERSION"
		echo "Cflags: -I\${prefix}/include"
		if [ "$UNAME" = "Darwin" ]; then
			echo "Ldflags: '-extldflags \"-Wl,-stack_size -Wl,0x1000000\"'"
		fi
		if [ -n "$OPENSSL_LIB" ] && [ -d "$OPENSSL_LIB" ]; then
			echo "Libs: -L\${prefix}/lib -loqs -L$OPENSSL_LIB -lcrypto"
		else
			echo "Libs: -L\${prefix}/lib -loqs -lcrypto"
		fi
	} >"$tmp"
	run_install mv "$tmp" "$pc"
	echo "wrote $pc"
}

install_from_brew() {
	echo "Installing liboqs $LIBOQS_VERSION via Homebrew"
	brew install liboqs pkgconf openssl@3
}

install_from_source() {
	echo "Building liboqs $LIBOQS_VERSION from source into $PREFIX"
	src="${LIBOQS_SRC:-$(mktemp -d "${TMPDIR:-/tmp}/liboqs.XXXXXX")}"
	if [ ! -f "$src/CMakeLists.txt" ]; then
		git clone --depth 1 --branch "$LIBOQS_VERSION" https://github.com/open-quantum-safe/liboqs.git "$src"
	fi
	cmake -S "$src" -B "$src/build" \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DOQS_USE_OPENSSL=ON \
		-DOQS_BUILD_ONLY_LIB=ON \
		-DBUILD_TESTING=OFF \
		-DOQS_MINIMAL_BUILD="$OQS_MINIMAL_BUILD" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_INSTALL_LIBDIR=lib
	cmake --build "$src/build" --parallel "$jobs"
	run_install cmake --install "$src/build"
	# Alpine/musl ldconfig is a stub and must not fail the image build (set -e).
	if command -v ldconfig >/dev/null 2>&1; then
		ldconfig 2>/dev/null || true
	fi
	if ! ls "$PREFIX/lib"/liboqs.so* >/dev/null 2>&1 && [ ! -e "$PREFIX/lib/liboqs.dylib" ] && [ ! -e "$PREFIX/lib/liboqs.a" ]; then
		echo "liboqs did not install a library under $PREFIX/lib" >&2
		exit 1
	fi
}

if [ "$UNAME" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
	if ! liboqs_present; then
		install_from_brew
	else
		echo "liboqs already present in $PREFIX"
	fi
else
	if ! liboqs_present; then
		install_from_source
	else
		echo "liboqs already present in $PREFIX"
	fi
fi

write_pc

echo "CGO_ENABLED=1 is required; the Makefile exports it."
echo "Compile:  PKG_CONFIG_PATH=$PKG_CONFIG_DIR:\$PKG_CONFIG_PATH"
if [ "$UNAME" = "Darwin" ]; then
	echo "Runtime:  dylib install name (or DYLD_LIBRARY_PATH=$PREFIX/lib)"
else
	echo "Runtime:  LD_LIBRARY_PATH=$PREFIX/lib (or rpath $PREFIX/lib)"
fi
