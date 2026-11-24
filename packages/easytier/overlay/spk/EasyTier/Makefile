SPK_NAME = EasyTier
SPK_VERS = 2.7.0
SPK_REV = 9
SPK_ICON = src/EasyTier.png

DEPENDS = cross/easytier

override MAINTAINER = EasyTier
override MAINTAINER_URL = https://github.com/EasyTier/EasyTier
override DISTRIBUTOR = Herbert Gao
override DISTRIBUTOR_URL = https://github.com/HerbertGao/synology-packages
override DISABLE_GITHUB_MAINTAINER = 1
DESCRIPTION = EasyTier mesh VPN (official upstream linux x86_64 binaries). Private overlay build (not SynoCommunity official).
DISPLAY_NAME = EasyTier
CHANGELOG = "9. caphelper: DSM-verified LE vfs_cap blob; TUN mode settle after insmod. 8. caphelper: complete FIPS 180-4 SHA-256 K table (fix hash_mismatch on large binaries). 7. caphelper: fix read_exe_gid; host TUN prep (Tailscale configure-host) then caps. 6. caphelper setuid helper for caps (unsigned SPK; no tool.capabilities). 5. TUN prestart rw diagnostic. 4. privilege tool caps (rejected on install). 3. ctrl-script root. 2. Fix privilege schema. 1. Initial overlay."

HOMEPAGE = https://github.com/EasyTier/EasyTier
LICENSE = LGPL-3.0

REQUIRED_MIN_DSM = 7.3
REQUIRED_MAX_DSM = 7.3
UNSUPPORTED_ARCHS = $(OLD_PPC_ARCHS) $(ARMv5_ARCHS) $(ARMv7L_ARCHS) $(PPC_ARCHS) $(ARMv8_ARCHS) $(32bit_ARCHS) $(i686_ARCHS)

STARTABLE = yes
SERVICE_USER = auto
SERVICE_SETUP = src/service-setup.sh
CONF_DIR = src/conf

POST_STRIP_TARGET = easytier_extra_install

include ../../mk/spksrc.spk.mk

CAPHELPER_SRC = $(CURDIR)/../../cross/caphelper/src/caphelper.c

.PHONY: easytier_extra_install
easytier_extra_install:
	@$(MSG) Install default config template for fresh install and license text
	@install -m 755 -d $(STAGING_DIR)/var
	@install -m 644 src/config.toml $(STAGING_DIR)/var/config.toml
	@install -m 755 -d $(STAGING_DIR)/share
	@install -m 644 src/LICENSE $(STAGING_DIR)/share/LICENSE
	@$(MSG) Build caphelper with embedded easytier-core SHA-256
	@install -m 755 -d $(STAGING_DIR)/bin/helper
	@HASH=$$(sha256sum $(STAGING_DIR)/bin/easytier-core | awk '{print $$1}'); \
	$(CC) -Wall -Wextra -O2 -static \
		-DEASYTIER_CORE_SHA256=\"$$HASH\" \
		-o $(STAGING_DIR)/bin/helper/caphelper \
		$(CAPHELPER_SRC)
	@chmod 755 $(STAGING_DIR)/bin/helper/caphelper