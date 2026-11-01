TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME := rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := CloverSpotlight

CloverSpotlight_FILES := Tweak.xm
CloverSpotlight_CFLAGS := -fobjc-arc
CloverSpotlight_FRAMEWORKS := Foundation UIKit

ARCHS := arm64e

include $(THEOS_MAKE_PATH)/tweak.mk
