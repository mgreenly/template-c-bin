CC := gcc

SSL_LIBS := -lssl -lcrypto
SSL_CFLAGS :=

PNG_LIBS := -lpng
PNG_CFLAGS :=

GLIB_LIBS := $(shell pkg-config --libs glib-2.0 2>/dev/null)
GLIB_CFLAGS := $(shell pkg-config --cflags glib-2.0 2>/dev/null)

DISTRO_CFLAGS := -D_DEFAULT_SOURCE \
  -fanalyzer -fstack-clash-protection \
  -Wduplicated-cond -Wduplicated-branches \
  -Wformat-signedness -fdiagnostics-color \
  $(SSL_CFLAGS) $(PNG_CFLAGS) $(GLIB_CFLAGS)

DISTRO_LDFLAGS := -Wl,-z,relro -Wl,-z,now -Wl,-z,noexecstack -Wl,--as-needed -Wl,--gc-sections -pie \
  $(SSL_LIBS) $(PNG_LIBS) $(GLIB_LIBS)

DEV_PACKAGES := build-essential libssl-dev libpng-dev libglib2.0-dev pkg-config cppcheck

INSTALL_DEPS_CMD := sudo apt-get install $(DEV_PACKAGES)
