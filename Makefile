ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RavenEngineAi

RavenEngineAi_FILES = Tweak.mm RavenMenu.mm
RavenEngineAi_CFLAGS = -fobjc-arc
RavenEngineAi_CCFLAGS = -std=c++17

RavenEngineAi_FRAMEWORKS = \
	UIKit \
	Foundation \
	QuartzCore \
	CoreML \
	Vision \
	CoreImage \
	Metal

RavenEngineAi_LDFLAGS = -ObjC

include $(THEOS_MAKE_PATH)/tweak.mk
