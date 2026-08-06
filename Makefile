export THEOS = $(HOME)/theos

ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = kora_bypass

kora_bypass_FILES = kora_bypass.mm
kora_bypass_CFLAGS = -fobjc-arc -std=c++11
kora_bypass_LIBRARIES = substrate

include $(THEOS)/makefiles/tweak.mk
