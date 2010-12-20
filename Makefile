GO_EASY_ON_ME=1
export SDKVERSION=4.1
FW_DEVICE_IP=appletv.local
include theos/makefiles/common.mk

TOOL_NAME = screencapture
screencapture_FILES = main.m
screencapture_PRIVATE_FRAMEWORKS=IOSurface, CoreSurface
screencapture_INSTALL_PATH = /usr/bin
screencapture_LDFLAGS=-framework UIKit -framework CoreGraphics -undefined dynamic_lookup
screencapture_CFLAGS =-I../ATV2Includes
include $(FW_MAKEDIR)/tool.mk
