TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = EcpmCtrl
EcpmCtrl_FILES = Tweak.xm
EcpmCtrl_CFLAGS = -fobjc-arc -fblocks
EcpmCtrl_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/library.mk
