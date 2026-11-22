PKG_NAME = OpenList
PKG_VERS = 4.2.10
# must match PKG_VERS of cross/openlist-frontend (adjust if different)
WEB_VERSION = $(PKG_VERS)
PKG_EXT = tar.gz
PKG_DIST_NAME = v$(PKG_VERS).$(PKG_EXT)
PKG_DIST_SITE = https://github.com/OpenListTeam/OpenList/archive
PKG_DIST_FILE = $(PKG_NAME)-$(PKG_VERS).$(PKG_EXT)
PKG_DIR = $(PKG_NAME)-$(PKG_VERS)

DEPENDS = cross/openlist-frontend

HOMEPAGE = https://docs.oplist.org/
COMMENT  = A file list program that supports multiple storage, powered by Gin and SolidJS, fork of AList.
LICENSE = AGPL-3.0

PRE_COMPILE_TARGET = openlist_pre_compile

BUILT_AT = $(shell date +'%F %T %z')
GIT_AUTHOR = "HerbertGao/synology-packages"
GIT_COMMIT = overlay

CGO_ENABLED = 0
GO_SRC_DIR = $(WORK_DIR)/$(PKG_DIR)
GO_BIN_DIR = $(GO_SRC_DIR)/openlist
GO_LDFLAGS = -w -s \
  -X 'github.com/OpenListTeam/OpenList/v4/internal/conf.BuiltAt=$(BUILT_AT)' \
  -X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitAuthor=$(GIT_AUTHOR)' \
  -X 'github.com/OpenListTeam/OpenList/v4/internal/conf.GitCommit=$(GIT_COMMIT)' \
  -X 'github.com/OpenListTeam/OpenList/v4/internal/conf.Version=$(PKG_VERS)' \
  -X 'github.com/OpenListTeam/OpenList/v4/internal/conf.WebVersion=$(WEB_VERSION)'

include ../../mk/spksrc.cross-go.mk

.PHONY: openlist_pre_compile
openlist_pre_compile:
	@$(MSG) "- Use prebuilt openlist-frontend Version $(WEB_VERSION)"
	@$(RUN) ; cp -R $(WORK_DIR)/openlist-frontend/dist/* $(WORK_DIR)/$(PKG_DIR)/public/dist/