TARGET := iphone:clang:14.5:13.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = XSao
XSao_FILES = XSao.xm QRScannerViewController.m QRCodeUtil.m
XSao_CFLAGS = -fobjc-arc -O2 -Wno-unused-function
XSao_FRAMEWORKS = UIKit AVFoundation Vision CoreImage CoreMedia AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk
