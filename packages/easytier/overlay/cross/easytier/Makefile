PKG_NAME = easytier
PKG_VERS = 2.7.0
PKG_EXT = zip
# spksrc downloads $(PKG_DIST_SITE)/$(PKG_DIST_NAME); PKG_DIST_FILE only names the local cache file.
PKG_DIST_NAME = easytier-linux-x86_64-v$(PKG_VERS).$(PKG_EXT)
PKG_DIST_FILE = $(PKG_DIST_NAME)
PKG_DIST_SITE = https://github.com/EasyTier/EasyTier/releases/download/v$(PKG_VERS)
PKG_DIR = easytier-linux-x86_64

DEPENDS =

HOMEPAGE = https://github.com/EasyTier/EasyTier
COMMENT  = EasyTier — decentralized virtual private network (official linux x86_64 release binaries).
LICENSE  = LGPL-3.0

# Pre-built official zip; apollolake/x86_64 only in this overlay round.
UNSUPPORTED_ARCHS = $(OLD_PPC_ARCHS) $(ARMv5_ARCHS) $(ARMv7L_ARCHS) $(PPC_ARCHS) $(ARMv8_ARCHS) $(32bit_ARCHS) $(i686_ARCHS)

INSTALL_TARGET = easytier_install

include ../../mk/spksrc.cross-install.mk

.PHONY: easytier_install
easytier_install:
	@mkdir -p $(STAGING_INSTALL_PREFIX)/bin
	@install -m 755 $(WORK_DIR)/$(PKG_DIR)/easytier-core $(STAGING_INSTALL_PREFIX)/bin/
	@install -m 755 $(WORK_DIR)/$(PKG_DIR)/easytier-cli $(STAGING_INSTALL_PREFIX)/bin/
	@install -m 755 $(WORK_DIR)/$(PKG_DIR)/easytier-web $(STAGING_INSTALL_PREFIX)/bin/
	@install -m 755 $(WORK_DIR)/$(PKG_DIR)/easytier-web-embed $(STAGING_INSTALL_PREFIX)/bin/