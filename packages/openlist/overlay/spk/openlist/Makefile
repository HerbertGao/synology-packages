SPK_NAME = openlist
SPK_VERS = 4.2.10
SPK_REV = 3
SPK_ICON = src/openlist.png

DEPENDS = cross/openlist

MAINTAINER = OpenList Team
MAINTAINER_URL = https://github.com/OpenListTeam/OpenList
DISTRIBUTOR = Herbert Gao
DISTRIBUTOR_URL = https://github.com/HerbertGao/synology-packages
DISABLE_GITHUB_MAINTAINER = 1
DESCRIPTION = A file list program that supports multiple storages, powered by Gin and SolidJS. Private overlay build (not SynoCommunity official).
DISPLAY_NAME = OpenList
CHANGELOG = "3. Package Center shows OpenList Team as developer and Herbert Gao as publisher. 1. Pin DSM integration to upstream port 5244; preserve upgrade config without custom-port metadata sync."

HOMEPAGE = https://docs.oplist.org/
LICENSE = AGPL-3.0

# DSM 7.3 / apollolake (DS918+ class). Broader arches are intentionally out of scope for this round.
REQUIRED_MIN_DSM = 7.3
REQUIRED_MAX_DSM = 7.3
UNSUPPORTED_ARCHS = $(OLD_PPC_ARCHS) $(ARMv5_ARCHS) $(ARMv7L_ARCHS) $(PPC_ARCHS) $(32bit_ARCHS)

SERVICE_SETUP = src/service-setup.sh

STARTABLE = yes
SERVICE_USER = auto
SERVICE_PORT = 5244
ADMIN_PORT = $(SERVICE_PORT)

POST_STRIP_TARGET = openlist_extra_install

WIZARDS_TEMPLATES_DIR = src/wizard_templates

include ../../mk/spksrc.spk.mk

.PHONY: openlist_extra_install
openlist_extra_install:
	@$(MSG) Install default config template for fresh installs only
	@install -m 755 -d $(STAGING_DIR)/var
	@install -m 644 src/config.json $(STAGING_DIR)/var/config.json
	@install -m 755 -d $(STAGING_DIR)/scripts
	@install -m 644 src/openlist-dsm-port-sync.sh $(STAGING_DIR)/scripts/openlist-dsm-port-sync.sh