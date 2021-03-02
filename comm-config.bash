#!/bin/bash

regex="^\s*\[.*\]\s*$"

_project () {
	grep -E "$regex" "./dist/config.ini" | sort
}

_local () {
	grep -E "$regex" "$(perl -e 'use App::Feedmailer; print App::Feedmailer::get_file("config.ini")')" | sort
}

echo "DOPPELTE PROJECT"
_project | uniq --repeated

echo "DOPPELTE LOCAL"
_local | uniq --repeated

echo "COMM"
comm -3 <(_project) <(_local)

