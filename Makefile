ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RavenEngineAi

RavenEngineAi_FILES = Tweak.mm RavenMenu.mm EmbeddedModel.S
RavenEngineAi_CFLAGS = -fobjc-arc
RavenEngineAi_CCFLAGS = -std=c++17

RavenEngineAi_FRAMEWORKS = \
	UIKit \
	Foundation \
	QuartzCore \
	CoreML \
	Vision \
	CoreImage \
	Metal \
	MetalPerformanceShaders \
	CoreVideo

RavenEngineAi_LDFLAGS = -ObjC
RavenEngineAi_BUNDLE_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/tweak.mk


MODEL_ZIP := RavenModelPackage_Upload.zip
MODEL_PACKAGE := Resources/RavenModel.mlpackage

before-all::
	@echo "[RAVEN] Preparing CoreML model package..."
	@rm -rf Resources/RavenModelPackage "$(MODEL_PACKAGE)"
	@mkdir -p Resources
	@unzip -oq "$(MODEL_ZIP)" -d .
	@mv Resources/RavenModelPackage "$(MODEL_PACKAGE)"
	@echo "[RAVEN] CoreML model ready at $(MODEL_PACKAGE)"
