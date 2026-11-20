.PHONY: all build release test generate install clean

all: build

build:
	swift build

release:
	swift build -c release

test:
	swift test

generate:
	xcodegen generate

install:
	./install.sh

clean:
	swift package clean
	rm -rf .build DerivedData
