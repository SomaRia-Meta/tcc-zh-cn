VERSION := $(shell cat VERSION)

.PHONY: all dist payload test clean help

all: dist

## dist    生成 dist/*.tar.gz 和 dist/*.deb
dist:
	bash tools/make-dist.sh

## payload 从上游源码重新构建中文界面（需要 node/npm/网络）
payload:
	bash tools/build-zh-bundle.sh

## test    在本机做一次“假根目录”安装/卸载冒烟测试（不需要 root）
test:
	bash tools/test-smoke.sh

## clean   清理构建产物
clean:
	rm -rf dist build
	find . -name __pycache__ -type d -prune -exec rm -rf {} +

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## /  /'
