SPK_NAME = EasyTier
SPK_VERS = 2.7.0
SPK_REV = 3
SPK_ICON = src/EasyTier.png

DEPENDS = cross/easytier

override MAINTAINER = EasyTier
override MAINTAINER_URL = https://github.com/EasyTier/EasyTier
override DISTRIBUTOR = Herbert Gao
override DISTRIBUTOR_URL = https://github.com/HerbertGao/synology-packages
override DISABLE_GITHUB_MAINTAINER = 1
DESCRIPTION = EasyTier mesh VPN (official upstream linux x86_64 binaries). Private overlay build (not SynoCommunity official).
DISPLAY_NAME = EasyTier
CHANGELOG = "3. Declare ctrl-script start as root so easytier-core can create the TUN interface on DSM 7.3 (2.7.0-2 ran start as package and failed with TUN EPERM). 2. Fix conf/privilege for DSM 7.3 prepare_install (drop invalid keys; explicit groupname). 1. Initial overlay: official v2.7.0 binaries, config.toml upgrade preservation; Package Center shows EasyTier as developer and Herbert Gao as publisher."

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

.PHONY: easytier_extra_install
easytier_extra_install:
	@$(MSG) Install default config template for fresh install and license text
	@install -m 755 -d $(STAGING_DIR)/var
	@install -m 644 src/config.toml $(STAGING_DIR)/var/config.toml
	@install -m 755 -d $(STAGING_DIR)/share
	@install -m 644 src/LICENSE $(STAGING_DIR)/share/LICENSE