#!/usr/bin/env bash
. $(dirname $(readlink -f $0))/env

pushToOtherServer
runScriptOnOtherServer

